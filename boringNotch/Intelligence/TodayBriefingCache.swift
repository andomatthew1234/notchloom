import Foundation
import CryptoKit

protocol TodayBriefingCaching: Sendable {
    func load() async throws -> TodayBriefingEntry?
    func save(_ entry: TodayBriefingEntry, generation: Int) async throws
    func clear(generation: Int) async
}

/// Single encrypted report, not a context/history store. The key is local, non-synchronizing Keychain data.
actor TodayBriefingCache: TodayBriefingCaching {
    private let url: URL
    private let keys: any GeminiCredentialStoring
    private var minimumGeneration = 0
    init(directory: URL? = nil, keys: any GeminiCredentialStoring = GeminiKeychainStore(service: "Notchloom.Today.Cache", account: "encryption-key")) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notchloom/Today", isDirectory: true)
        url = base.appendingPathComponent("briefing-v1.encrypted")
        self.keys = keys
        Self.purgeExpiredFile(url)
    }
    private static func header(expiration: Date) throws -> Data {
        let milliseconds = expiration.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds > Double(Int64.min), milliseconds < Double(Int64.max) else { throw TodayBriefingError.cacheUnavailable }
        var value = Int64(milliseconds.rounded(.down)).bigEndian
        var data = Data("NLTD1".utf8)
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        return data
    }
    private static func expiration(_ header: Data) -> Date? {
        guard header.count == 13, header.prefix(5) == Data("NLTD1".utf8) else { return nil }
        let milliseconds = header.dropFirst(5).withUnsafeBytes { Int64(bigEndian: $0.loadUnaligned(as: Int64.self)) }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
    private static func purgeExpiredFile(_ url: URL) {
        // Thirteen bytes of non-content expiry metadata; no credential read or context decryption at startup.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 13), let deadline = expiration(data), deadline > Date() else {
            try? FileManager.default.removeItem(at: url); return
        }
    }
    private func key(create: Bool) throws -> SymmetricKey? {
        if let string = try keys.load() {
            guard let data = Data(base64Encoded: string), data.count == 32 else { throw TodayBriefingError.cacheUnavailable }
            return SymmetricKey(data: data)
        }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        try keys.save(key.withUnsafeBytes { Data($0).base64EncodedString() })
        return key
    }
    func load() throws -> TodayBriefingEntry? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 256_000 else { throw TodayBriefingError.cacheUnavailable }
            let encrypted = try Data(contentsOf: url, options: .mappedIfSafe)
            let header = Data(encrypted.prefix(13))
            guard let deadline = Self.expiration(header), deadline > Date() else { try? FileManager.default.removeItem(at: url); return nil }
            guard let key = try key(create: false) else { throw TodayBriefingError.cacheUnavailable }
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted.dropFirst(13)), using: key, authenticating: header)
            guard plaintext.count <= 200_000 else { throw TodayBriefingError.invalidReport }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let entry = try decoder.decode(TodayBriefingEntry.self, from: plaintext)
            _ = try entry.validated()
            return entry
        } catch {
            try? FileManager.default.removeItem(at: url)
            // Cache failure never exposes cryptography errors or private contents.
            throw TodayBriefingError.cacheUnavailable
        }
    }
    func save(_ entry: TodayBriefingEntry, generation: Int) throws {
        try Task.checkCancellation()
        guard generation >= minimumGeneration else { throw CancellationError() }
        _ = try entry.validated()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entry)
        let header = try Self.header(expiration: entry.privacyExpiresAt)
        guard data.count <= 200_000, let key = try key(create: true), let sealed = try AES.GCM.seal(data, using: key, authenticating: header).combined else { throw TodayBriefingError.cacheUnavailable }
        var encrypted = header; encrypted.append(sealed)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Stage with restrictive permissions before writing; atomically replace the final ciphertext.
        let temporary = directory.appendingPathComponent(".briefing-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw TodayBriefingError.cacheUnavailable }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: encrypted); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw TodayBriefingError.cacheUnavailable }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: url) }
        var excluded = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }
    func clear(generation: Int) {
        minimumGeneration = max(minimumGeneration, generation)
        try? FileManager.default.removeItem(at: url)
        try? keys.delete()
    }
}
