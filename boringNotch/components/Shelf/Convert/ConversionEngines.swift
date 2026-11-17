import AVFoundation
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConversionFormats {
    static let png = ConversionFormat("png", "PNG", "png", .image, "Lossless · transparency")
    static let jpeg = ConversionFormat("jpeg", "JPEG", "jpg", .image, "Smaller photos · no transparency")
    static let tiff = ConversionFormat("tiff", "TIFF", "tiff", .image, "Lossless · large files")
    static let gif = ConversionFormat("gif", "GIF", "gif", .image, "Static · 256 colors; soft transparency may change")
    static let heic = ConversionFormat("heic", "HEIC", "heic", .image, "Efficient photos")
    static let bmp = ConversionFormat("bmp", "BMP", "bmp", .image, "Uncompressed bitmap")
    static let webp = ConversionFormat("webp", "WebP", "webp", .image, "Efficient web image")
    static let avif = ConversionFormat("avif", "AVIF", "avif", .image, "Modern high-compression image")
    static let mp4 = ConversionFormat("mp4-system", "MP4", "mp4", .video, "macOS compatible encoding")
    static let mov = ConversionFormat("mov-system", "MOV", "mov", .video, "QuickTime movie")
    static let m4a = ConversionFormat("m4a-system", "M4A", "m4a", .audio, "AAC audio")
    static let mp4H264 = ConversionFormat("mp4-h264", "MP4 · H.264", "mp4", .video, "Maximum compatibility", codec: "libx264")
    static let mp4HEVC = ConversionFormat("mp4-hevc", "MP4 · HEVC", "mp4", .video, "Smaller files on modern devices", codec: "libx265")
    static let webmVP9 = ConversionFormat("webm-vp9", "WebM · VP9", "webm", .video, "Open web video", codec: "libvpx-vp9")
    static let mkvH264 = ConversionFormat("mkv-h264", "MKV · H.264", "mkv", .video, "Matroska video", codec: "libx264")
    static let mp3 = ConversionFormat("mp3", "MP3", "mp3", .audio, "Widely compatible", codec: "libmp3lame")
    static let flac = ConversionFormat("flac", "FLAC", "flac", .audio, "Lossless container; source quality cannot improve", codec: "flac")
    static let wav = ConversionFormat("wav", "WAV", "wav", .audio, "Uncompressed PCM", codec: "pcm_s16le")
    static let opus = ConversionFormat("opus", "Opus", "opus", .audio, "Efficient speech and music", codec: "libopus")
    static let aac = ConversionFormat("aac", "M4A · AAC", "m4a", .audio, "Efficient, widely supported", codec: "aac")
    static let txt = ConversionFormat("txt", "Plain text", "txt", .document, "Text only · formatting removed")
    static let rtf = ConversionFormat("rtf", "Rich Text", "rtf", .document, "Basic styles and formatting")
    static let html = ConversionFormat("html", "HTML", "html", .document, "Web document · external resources may change")
    static let docx = ConversionFormat("docx", "Word DOCX", "docx", .document, "Complex layouts may change")
    static let odt = ConversionFormat("odt", "OpenDocument", "odt", .document, "Complex layouts may change")
    static let doc = ConversionFormat("doc", "Word DOC", "doc", .document, "Legacy Word format · layout may change")
    static let zip = ConversionFormat("zip-folder", "ZIP archive", "zip", .archive, "Package a folder without changing its contents")
}

struct ImageIOConversionEngine: ConversionEngine {
    let id = "imageio"
    let requiresExternalExecutable = false
    let supportsProgress = false
    let supportsCancellation = true

    private let candidates: [(ConversionFormat, String)] = [
        (ConversionFormats.png, UTType.png.identifier), (ConversionFormats.jpeg, UTType.jpeg.identifier),
        (ConversionFormats.tiff, UTType.tiff.identifier), (ConversionFormats.gif, UTType.gif.identifier),
        (ConversionFormats.heic, UTType.heic.identifier), (ConversionFormats.bmp, UTType.bmp.identifier),
        (ConversionFormats.webp, UTType.webP.identifier),
        (ConversionFormats.avif, "public.avif")
    ]

    func formats(for input: ConversionInput) async -> [ConversionFormat] {
        guard input.category == .image,
              let source = CGImageSourceCreateWithURL(input.url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) == 1 else { return [] }
        let writable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = metadata?[kCGImagePropertyHasAlpha] as? Bool ?? false
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32
        ] as CFDictionary) else { return [] }
        return candidates.filter {
            writable.contains($0.1) && $0.1 != input.type.identifier
                && !($0.0.id == "jpeg" && hasAlpha)
                && canEncode(thumbnail, type: $0.1, metadata: metadata ?? [:], format: $0.0)
        }.map(\.0)
    }

    private func canEncode(_ image: CGImage, type: String, metadata: [CFString: Any],
                           format: ConversionFormat) -> Bool {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return false }
        var properties = metadata
        if format.id == "jpeg" || format.id == "heic" {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.82
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let output = CGImageSourceCreateWithData(data, nil),
              CGImageSourceGetStatus(output) == .statusComplete,
              CGImageSourceCreateImageAtIndex(output, 0, nil) != nil else { return false }
        return true
    }

    func convert(input: ConversionInput, to format: ConversionFormat, preset: ConversionPreset,
                 preserveMetadata: Bool,
                 temporaryURL: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        let work = Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(input.url as CFURL, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  CGImageSourceGetCount(source) == 1,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ConversionError.invalidInput("This image could not be decoded, or it contains multiple frames.")
            }
            guard let destinationType = candidates.first(where: { $0.0.id == format.id })?.1,
                  let destination = CGImageDestinationCreateWithURL(
                    temporaryURL as CFURL, destinationType as CFString, 1, nil) else {
                throw ConversionError.unavailable("macOS could not create the output file. Check access to the output folder and try again.")
            }
            if format.id == "jpeg" && image.alphaInfo != .none &&
                image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast {
                throw ConversionError.unsupported("JPEG cannot preserve transparency. Choose PNG, TIFF, or HEIC.")
            }
            try Task.checkCancellation()
            var properties = preserveMetadata
                ? (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:])
                : [:]
            if !preserveMetadata,
               let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] {
                properties[kCGImagePropertyOrientation] = orientation
            }
            if format.id == "jpeg" || format.id == "heic" {
                properties[kCGImageDestinationLossyCompressionQuality] =
                    preset == .small ? 0.55 : (preset == .high || preset == .original ? 0.95 : 0.82)
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ConversionError.failed("The image encoder could not finish the output.")
            }
            progress(1)
        }
        try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }
}

struct AVFoundationConversionEngine: ConversionEngine {
    let id = "avfoundation"
    let requiresExternalExecutable = false
    let supportsProgress = true
    let supportsCancellation = true

    func formats(for input: ConversionInput) async -> [ConversionFormat] {
        guard input.category == .video || input.category == .audio else { return [] }
        let asset = AVURLAsset(url: input.url)
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else { return [] }
        if !videoTracks.isEmpty {
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return [] }
            var formats = [(ConversionFormats.mp4, AVFileType.mp4), (ConversionFormats.mov, AVFileType.mov)]
                .filter { export.supportedFileTypes.contains($0.1) && input.url.pathExtension.lowercased() != $0.0.fileExtension }
                .map(\.0)
            if !audioTracks.isEmpty,
               let audioExport = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A),
               audioExport.supportedFileTypes.contains(.m4a) {
                formats.append(ConversionFormats.m4a)
            }
            return formats
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A),
              export.supportedFileTypes.contains(.m4a),
              input.url.pathExtension.lowercased() != "m4a" else { return [] }
        return [ConversionFormats.m4a]
    }

    func convert(input: ConversionInput, to format: ConversionFormat, preset: ConversionPreset,
                 preserveMetadata: Bool,
                 temporaryURL: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        let asset = AVURLAsset(url: input.url)
        let presetName = format.category == .audio ? AVAssetExportPresetAppleM4A :
            (preset == .small ? AVAssetExportPresetMediumQuality : AVAssetExportPresetHighestQuality)
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ConversionError.unsupported("This media cannot be exported by macOS.")
        }
        let type: AVFileType = format.fileExtension == "mp4" ? .mp4 :
            (format.fileExtension == "mov" ? .mov : .m4a)
        guard session.supportedFileTypes.contains(type) else {
            throw ConversionError.unsupported("The selected container is unavailable for this media.")
        }
        session.outputURL = temporaryURL
        session.outputFileType = type
        if !preserveMetadata { session.metadata = [] }
        let monitor = Task {
            while !Task.isCancelled {
                if session.status == .exporting { progress(Double(session.progress)) }
                if session.status == .completed || session.status == .failed || session.status == .cancelled { break }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
        defer { monitor.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed: continuation.resume()
                    case .cancelled: continuation.resume(throwing: ConversionError.cancelled)
                    default: continuation.resume(throwing: session.error ?? ConversionError.failed("Media export failed."))
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }
        progress(1)
    }
}

enum ConversionInspector {
    static func inspect(_ url: URL, bookmark: Data? = nil) async throws -> ConversionInput {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentTypeKey]) else {
            throw ConversionError.invalidInput("Only regular files can be converted.")
        }
        if values.isDirectory == true {
            return ConversionInput(url: url, bookmark: bookmark, type: .folder, size: 0,
                                   category: .archive, duration: nil, hasAudio: false, isDirectory: true)
        }
        guard values.isRegularFile == true else {
            throw ConversionError.invalidInput("Only regular files and folders can be converted.")
        }
        let size = Int64(values.fileSize ?? 0)
        guard size > 0 else { throw ConversionError.invalidInput("The file is empty.") }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetStatus(source) == .statusComplete,
           let identifier = CGImageSourceGetType(source) as String?,
           let type = UTType(identifier) {
            guard !type.conforms(to: .pdf) else {
                throw ConversionError.unsupported("PDF pages are not rasterized automatically. The original vector document is untouched.")
            }
            guard CGImageSourceGetCount(source) == 1 else {
                throw ConversionError.unsupported("Animated or multipage images are not converted yet; no frames were discarded.")
            }
            return ConversionInput(url: url, bookmark: bookmark, type: type, size: size,
                                   category: .image, duration: nil, hasAudio: false, isDirectory: false)
        }
        let asset = AVURLAsset(url: url)
        let video = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let assetDuration = try? await asset.load(.duration).seconds
        if !video.isEmpty {
            return ConversionInput(url: url, bookmark: bookmark, type: values.contentType ?? .movie,
                                   size: size, category: .video, duration: assetDuration, hasAudio: !audio.isEmpty,
                                   isDirectory: false)
        }
        if !audio.isEmpty {
            return ConversionInput(url: url, bookmark: bookmark, type: values.contentType ?? .audio,
                                   size: size, category: .audio, duration: assetDuration, hasAudio: true,
                                   isDirectory: false)
        }
        if let probed = await FFmpegConversionEngine.probe(url: url, size: size, bookmark: bookmark, fallbackType: values.contentType) {
            return probed
        }
        if let probed = await TextUtilConversionEngine.probe(url: url, size: size,
                                                            bookmark: bookmark, fallbackType: values.contentType) {
            return probed
        }
        if let probed = await ArchiveConversionEngine.probeZIP(url, size: size, bookmark: bookmark) {
            return probed
        }
        throw ConversionError.unsupported("No installed converter can read this file.")
    }
}
