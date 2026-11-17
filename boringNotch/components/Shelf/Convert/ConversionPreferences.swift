import AppKit
import Combine
import Foundation

@MainActor
final class ConversionPreferences: ObservableObject {
    static let shared = ConversionPreferences()

    enum Naming: String, CaseIterable, Identifiable {
        case original = "Original name"
        case converted = "Add “converted”"
        var id: String { rawValue }
    }

    @Published var naming: Naming {
        didSet { UserDefaults.standard.set(naming.rawValue, forKey: "notchloom.convert.naming") }
    }
    @Published var preserveMetadata: Bool {
        didSet { UserDefaults.standard.set(preserveMetadata, forKey: "notchloom.convert.metadata") }
    }
    @Published var collision: ConversionCollision {
        didSet { UserDefaults.standard.set(collision.rawValue, forKey: "notchloom.convert.collision") }
    }
    @Published private(set) var folderBookmark: Data? {
        didSet { UserDefaults.standard.set(folderBookmark, forKey: "notchloom.convert.folder") }
    }
    private var sourceFolderBookmarks: [String: Data] {
        didSet { UserDefaults.standard.set(sourceFolderBookmarks, forKey: "notchloom.convert.source-folders") }
    }

    var folderName: String {
        guard let folderBookmark,
              let url = Bookmark(data: folderBookmark).resolveURL() else { return "Beside original" }
        return url.lastPathComponent
    }

    private init() {
        let defaults = UserDefaults.standard
        naming = Naming(rawValue: defaults.string(forKey: "notchloom.convert.naming") ?? "") ?? .original
        preserveMetadata = defaults.object(forKey: "notchloom.convert.metadata") as? Bool ?? true
        collision = ConversionCollision(rawValue: defaults.string(forKey: "notchloom.convert.collision") ?? "") ?? .numbered
        folderBookmark = defaults.data(forKey: "notchloom.convert.folder")
        sourceFolderBookmarks = defaults.dictionary(forKey: "notchloom.convert.source-folders") as? [String: Data] ?? [:]
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use for conversions"
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? Bookmark(url: url) else { return }
        folderBookmark = bookmark.data
    }

    func useOriginalFolder() { folderBookmark = nil }

    /// A dropped file grants access to that file, but not necessarily to create a sibling.
    /// Ask once for each source directory and keep its security-scoped bookmark.
    func authorizeOutputFolders(for inputs: [ConversionInput]) throws {
        let folders = folderBookmark == nil
            ? Array(Set(inputs.map { $0.url.deletingLastPathComponent().standardizedFileURL.path })).sorted()
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
            : [try resolvedFolder(for: inputs[0].url)]
        for folder in folders {
            let scopedFolder = resolvedScopedFolder(folder)
            if canWrite(in: scopedFolder) { continue }

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.prompt = "Allow Access"
            panel.message = "Allow Notchloom to save converted files in \(folder.lastPathComponent)."
            guard panel.runModal() == .OK,
                  let selected = panel.url?.standardizedFileURL,
                  selected.path == folder.standardizedFileURL.path else {
                throw ConversionError.unavailable("Choose \(folder.lastPathComponent) to save beside the original, or select another output folder in Settings.")
            }
            let bookmark = try Bookmark(url: selected).data
            if folderBookmark != nil {
                folderBookmark = bookmark
            } else {
                sourceFolderBookmarks[folder.standardizedFileURL.path] = bookmark
            }
            guard canWrite(in: selected) else {
                throw ConversionError.unavailable("macOS did not grant write access to \(folder.lastPathComponent). Choose another output folder in Settings.")
            }
        }
    }

    func resolvedFolder(for input: URL) throws -> URL {
        let parent = input.deletingLastPathComponent().standardizedFileURL
        guard let bookmark = folderBookmark ?? sourceFolderBookmarks[parent.path] else { return parent }
        guard let folder = Bookmark(data: bookmark).resolveURL(),
              FileManager.default.fileExists(atPath: folder.path) else {
            throw ConversionError.invalidInput("The output folder is no longer available. Choose it again in Settings.")
        }
        return folder
    }

    private func resolvedScopedFolder(_ folder: URL) -> URL {
        let data = folderBookmark ?? sourceFolderBookmarks[folder.standardizedFileURL.path]
        return data.flatMap { Bookmark(data: $0).resolveURL() } ?? folder
    }

    private func canWrite(in folder: URL) -> Bool {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let probe = folder.appendingPathComponent(".notchloom-write-check-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            try? FileManager.default.removeItem(at: probe)
            return false
        }
    }
}
