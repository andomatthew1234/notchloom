import Foundation
import UniformTypeIdentifiers

/// textutil ships with macOS. It handles common editable documents, but is not a PDF engine.
struct TextUtilConversionEngine: ConversionEngine {
    let id = "textutil"
    let requiresExternalExecutable = true
    let supportsProgress = false
    let supportsCancellation = true

    private static let accepted = Set(["txt", "rtf", "html", "doc", "docx", "odt"])
    private let outputs: [ConversionFormat] = [
        ConversionFormats.txt, ConversionFormats.rtf, ConversionFormats.html,
        ConversionFormats.docx, ConversionFormats.odt, ConversionFormats.doc
    ]

    func formats(for input: ConversionInput) async -> [ConversionFormat] {
        guard input.category == .document,
              ExternalProcess.executable("textutil") != nil,
              Self.accepted.contains(input.url.pathExtension.lowercased()) else { return [] }
        return outputs.filter { $0.fileExtension != input.url.pathExtension.lowercased() }
    }

    func convert(input: ConversionInput, to format: ConversionFormat, preset: ConversionPreset,
                 preserveMetadata: Bool,
                 temporaryURL: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        guard let executable = ExternalProcess.executable("textutil"),
              Self.accepted.contains(format.fileExtension) else {
            throw ConversionError.unavailable("macOS textutil cannot write this document format.")
        }
        var arguments = ["-convert", format.fileExtension, "-output", temporaryURL.path, "-noload"]
        if !preserveMetadata { arguments.append("-strip") }
        arguments += ["--", input.url.path]
        let result = try await ExternalProcess.run(executable, arguments)
        try Task.checkCancellation()
        guard result.exitCode == 0,
              FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw ConversionError.failed(result.errors.isEmpty ? "The document could not be converted." :
                String(result.errors.suffix(500)))
        }
        progress(1)
    }

    static func probe(url: URL, size: Int64, bookmark: Data?,
                      fallbackType: UTType?) async -> ConversionInput? {
        guard accepted.contains(url.pathExtension.lowercased()),
              let executable = ExternalProcess.executable("textutil"),
              let result = try? await ExternalProcess.run(executable, ["-info", "-noload", "-timeout", "3", "--", url.path]),
              result.exitCode == 0, result.output.contains("Type:") else { return nil }
        return ConversionInput(url: url, bookmark: bookmark,
                               type: fallbackType ?? UTType(filenameExtension: url.pathExtension) ?? .data,
                               size: size, category: .document, duration: nil, hasAudio: false,
                               isDirectory: false)
    }
}
