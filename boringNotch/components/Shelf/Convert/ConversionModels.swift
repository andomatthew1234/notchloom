import AppKit
import Foundation
import UniformTypeIdentifiers

enum ConversionCategory: String, CaseIterable, Identifiable {
    case image = "Images"
    case video = "Video"
    case audio = "Audio"
    case document = "Documents"
    case ebook = "Ebooks"
    case archive = "Archives"

    var id: String { rawValue }
}

struct ConversionFormat: Identifiable, Hashable {
    let id: String
    let name: String
    let fileExtension: String
    let category: ConversionCategory
    let detail: String
    let codec: String?

    init(_ id: String, _ name: String, _ ext: String, _ category: ConversionCategory,
         _ detail: String, codec: String? = nil) {
        self.id = id
        self.name = name
        fileExtension = ext
        self.category = category
        self.detail = detail
        self.codec = codec
    }
}

struct ConversionInput: Identifiable {
    let id = UUID()
    let url: URL
    let bookmark: Data?
    let type: UTType
    let size: Int64
    let category: ConversionCategory
    let duration: TimeInterval?
    let hasAudio: Bool
    let isDirectory: Bool

    var name: String { url.lastPathComponent }
    var displayType: String { type.localizedDescription ?? url.pathExtension.uppercased() }
}

enum ConversionPreset: String, CaseIterable, Identifiable {
    case original = "Original quality"
    case high = "High quality"
    case balanced = "Balanced"
    case small = "Small file"
    case compatible = "Maximum compatibility"
    var id: String { rawValue }
}

enum ConversionCollision: String, CaseIterable, Identifiable {
    case numbered = "Add a number"
    case timestamped = "Add date and time"
    var id: String { rawValue }
}

enum ConversionError: LocalizedError {
    case unsupported(String)
    case unavailable(String)
    case invalidInput(String)
    case noSpace
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let reason), .unavailable(let reason), .invalidInput(let reason),
             .failed(let reason): reason
        case .noSpace: "There is not enough free space to save the converted file."
        case .cancelled: "Conversion cancelled."
        }
    }
}

struct ConversionProgress {
    let fraction: Double?
    let elapsed: TimeInterval
    let remaining: TimeInterval?
}

struct ConversionJob: Identifiable {
    enum State { case queued, running, completed, failed, cancelled }
    let id = UUID()
    let input: ConversionInput
    let format: ConversionFormat
    var state: State = .queued
    var outputURL: URL?
    var outputBookmark: Data?
    var outputDirectoryURL: URL?
    var error: String?
    var progress: ConversionProgress?
    var startedAt: Date?
}

protocol ConversionEngine {
    var id: String { get }
    var requiresExternalExecutable: Bool { get }
    var supportsProgress: Bool { get }
    var supportsCancellation: Bool { get }
    func formats(for input: ConversionInput) async -> [ConversionFormat]
    func convert(input: ConversionInput, to format: ConversionFormat, preset: ConversionPreset,
                 preserveMetadata: Bool,
                 temporaryURL: URL, progress: @escaping @Sendable (Double?) -> Void) async throws
}

enum ConversionOutputPlanner {
    static func uniqueURL(for input: URL, in folder: URL, extension ext: String,
                          addConverted: Bool = false,
                          collision: ConversionCollision = .numbered) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let base = addConverted ? "\(stem) converted" : stem
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        if (FileManager.default.fileExists(atPath: candidate.path) || candidate == input),
           collision == .timestamped {
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyy-MM-dd HH-mm-ss"
            candidate = folder.appendingPathComponent("\(base) \(stamp.string(from: .now))")
                .appendingPathExtension(ext)
        }
        let collisionBase = candidate.deletingPathExtension().lastPathComponent
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) || candidate == input {
            candidate = folder.appendingPathComponent("\(collisionBase) \(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}
