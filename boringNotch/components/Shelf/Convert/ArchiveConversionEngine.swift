import Foundation
import UniformTypeIdentifiers

/// Archive creation is an operation, not a media or document transcode.
/// Extraction is deliberately not exposed until path and size limits are enforced.
struct ArchiveConversionEngine: ConversionEngine {
    let id = "ditto"
    let requiresExternalExecutable = true
    let supportsProgress = false
    let supportsCancellation = true

    func formats(for input: ConversionInput) async -> [ConversionFormat] {
        guard input.isDirectory,
              ExternalProcess.executable("ditto") != nil,
              ExternalProcess.executable("unzip") != nil else { return [] }
        return [ConversionFormats.zip]
    }

    func convert(input: ConversionInput, to format: ConversionFormat, preset: ConversionPreset,
                 preserveMetadata: Bool, temporaryURL: URL,
                 progress: @escaping @Sendable (Double?) -> Void) async throws {
        guard input.isDirectory, format.id == ConversionFormats.zip.id,
              let ditto = ExternalProcess.executable("ditto") else {
            throw ConversionError.unsupported("Only folder-to-ZIP creation is available.")
        }
        var arguments = ["-c", "-k", "--keepParent"]
        if !preserveMetadata { arguments.append("--norsrc") }
        arguments += [input.url.path, temporaryURL.path]
        let result = try await ExternalProcess.run(ditto, arguments)
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw ConversionError.failed(result.errors.isEmpty ? "Could not create the ZIP archive." :
                String(result.errors.suffix(500)))
        }
        guard let unzip = ExternalProcess.executable("unzip") else {
            throw ConversionError.unavailable("The macOS ZIP checker is unavailable.")
        }
        let check = try await ExternalProcess.run(unzip, ["-tqq", temporaryURL.path])
        guard check.exitCode == 0 else {
            throw ConversionError.failed("The new ZIP archive did not pass integrity checking.")
        }
        progress(1)
    }

    static func probeZIP(_ url: URL, size: Int64, bookmark: Data?) async -> ConversionInput? {
        guard url.pathExtension.lowercased() == "zip",
              let unzip = ExternalProcess.executable("unzip"),
              let result = try? await ExternalProcess.run(unzip, ["-tqq", url.path]),
              result.exitCode == 0 else { return nil }
        return ConversionInput(url: url, bookmark: bookmark, type: .zip, size: size,
                               category: .archive, duration: nil, hasAudio: false, isDirectory: false)
    }
}
