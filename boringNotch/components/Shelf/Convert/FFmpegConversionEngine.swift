import Foundation
import UniformTypeIdentifiers

private final class ProcessOutput {
    private let lock = NSLock()
    private var data = Data()
    private var pending = Data()
    private let onLine: ((String) -> Void)?

    init(onLine: ((String) -> Void)? = nil) { self.onLine = onLine }

    func append(_ chunk: Data) {
        lock.lock()
        if data.count < 1_048_576 { data.append(chunk.prefix(1_048_576 - data.count)) }
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline)
            if let string = String(data: line, encoding: .utf8) { lines.append(string) }
            pending.removeSubrange(...newline)
        }
        if pending.count > 4_096 { pending.removeAll() }
        lock.unlock()
        for line in lines { onLine?(line) }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct ProcessResult {
    let exitCode: Int32
    let output: String
    let errors: String
}

enum ExternalProcess {
    static func executable(_ name: String, appPaths: [String] = []) -> URL? {
        let paths = appPaths + [
            "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    static func run(_ executable: URL, _ arguments: [String],
                    onLine: ((String) -> Void)? = nil) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let out = ProcessOutput(onLine: onLine)
        let err = ProcessOutput()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { out.append(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { err.append(chunk) }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                    // Cancellation can arrive between the preflight check and launch.
                    if Task.isCancelled && process.isRunning { process.terminate() }
                    DispatchQueue.global(qos: .userInitiated).async {
                        process.waitUntilExit()
                        stdout.fileHandleForReading.readabilityHandler = nil
                        stderr.fileHandleForReading.readabilityHandler = nil
                        try? stdout.fileHandleForWriting.close()
                        try? stderr.fileHandleForWriting.close()
                        out.append(stdout.fileHandleForReading.readDataToEndOfFile())
                        err.append(stderr.fileHandleForReading.readDataToEndOfFile())
                        continuation.resume(returning: ProcessResult(
                            exitCode: process.terminationStatus, output: out.text, errors: err.text))
                    }
                } catch {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ConversionError.unavailable(
                        "Could not start \(executable.lastPathComponent): \(error.localizedDescription)"))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

actor CapabilityDetector {
    static let shared = CapabilityDetector()
    struct FFmpegCapabilities {
        let ffmpeg: URL
        let ffprobe: URL
        let encoders: Set<String>
        let decoders: Set<String>
        let muxers: Set<String>
    }
    private var loaded = false
    private var cached: FFmpegCapabilities?

    func ffmpeg() async -> FFmpegCapabilities? {
        if loaded { return cached }
        loaded = true
        guard let ffmpeg = ExternalProcess.executable("ffmpeg"),
              let ffprobe = ExternalProcess.executable("ffprobe"),
              let encoders = try? await ExternalProcess.run(ffmpeg, ["-hide_banner", "-encoders"]),
              let decoders = try? await ExternalProcess.run(ffmpeg, ["-hide_banner", "-decoders"]),
              let muxers = try? await ExternalProcess.run(ffmpeg, ["-hide_banner", "-muxers"]),
              encoders.exitCode == 0, decoders.exitCode == 0, muxers.exitCode == 0 else { return nil }
        let encoderNames = Set(encoders.output.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0].count == 6 else { return nil }
            return String(fields[1])
        })
        let muxerNames = Set(muxers.output.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0].count <= 2 else { return nil }
            return String(fields[1])
        })
        let decoderNames = Set(decoders.output.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0].count == 6 else { return nil }
            return String(fields[1])
        })
        cached = FFmpegCapabilities(ffmpeg: ffmpeg, ffprobe: ffprobe,
                                     encoders: encoderNames, decoders: decoderNames,
                                     muxers: muxerNames)
        return cached
    }
}

struct FFmpegConversionEngine: ConversionEngine {
    let id = "ffmpeg"
    let requiresExternalExecutable = true
    let supportsProgress = true
    let supportsCancellation = true

    func formats(for input: ConversionInput) async -> [ConversionFormat] {
        guard input.category == .video || input.category == .audio,
              let cap = await CapabilityDetector.shared.ffmpeg() else { return [] }
        var candidates: [(ConversionFormat, String)] = []
        if input.category == .video {
            candidates += [
                (ConversionFormats.mp4H264, "mp4"), (ConversionFormats.mp4HEVC, "mp4"),
                (ConversionFormats.mkvH264, "matroska"), (ConversionFormats.webmVP9, "webm")
            ]
        }
        if input.hasAudio {
            candidates += [
                (ConversionFormats.mp3, "mp3"), (ConversionFormats.flac, "flac"),
                (ConversionFormats.wav, "wav"), (ConversionFormats.opus, "opus"),
                (ConversionFormats.aac, "ipod")
            ]
        }
        return candidates.filter {
            guard let codec = $0.0.codec else { return false }
            if $0.0.id == "webm-vp9" && input.hasAudio && !cap.encoders.contains("libopus") { return false }
            if $0.0.category == .video && $0.0.id != "webm-vp9" && input.hasAudio &&
                !cap.encoders.contains("aac") { return false }
            return cap.encoders.contains(codec) && cap.muxers.contains($0.1)
                && (input.category == .video || input.url.pathExtension.lowercased() != $0.0.fileExtension)
        }.map(\.0)
    }

    func convert(input: ConversionInput, to format: ConversionFormat, preset: ConversionPreset,
                 preserveMetadata: Bool,
                 temporaryURL: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        guard let cap = await CapabilityDetector.shared.ffmpeg(), let codec = format.codec else {
            throw ConversionError.unavailable("FFmpeg is not available.")
        }
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-i", input.url.path]
        if format.category == .video {
            args += ["-map", "0:v:0", "-map", "0:a:0?", "-sn", "-c:v", codec]
            let quality = preset == .high || preset == .original ? "18" :
                (preset == .small ? "30" : "23")
            args += ["-crf", quality]
            if codec == "libx264" || codec == "libx265" { args += ["-preset", "medium"] }
            if format.id == "webm-vp9" {
                args += ["-b:v", "0", "-c:a", "libopus", "-b:a", "128k"]
            } else {
                args += ["-c:a", "aac", "-b:a", "192k"]
            }
            if format.fileExtension == "mp4" { args += ["-movflags", "+faststart"] }
        } else {
            args += ["-vn", "-sn", "-c:a", codec]
            if codec == "libmp3lame" || codec == "aac" || codec == "libopus" {
                args += ["-b:a", preset == .small ? "96k" : "192k"]
            }
        }
        args += ["-map_metadata", preserveMetadata ? "0" : "-1",
                 "-progress", "pipe:1", "-nostats", "-y", temporaryURL.path]
        let duration = input.duration
        let result = try await ExternalProcess.run(cap.ffmpeg, args) { line in
            let fields = line.split(separator: "=", maxSplits: 1)
            guard fields.count == 2,
                  fields[0] == "out_time_us" || fields[0] == "out_time_ms",
                  let microseconds = Double(fields[1]), let duration, duration > 0 else { return }
            progress(min(0.99, max(0, microseconds / 1_000_000 / duration)))
        }
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw ConversionError.failed(result.errors.isEmpty ? "FFmpeg could not convert this file." :
                String(result.errors.suffix(500)))
        }
        progress(1)
    }

    static func probe(url: URL, size: Int64, bookmark: Data?,
                      fallbackType: UTType?) async -> ConversionInput? {
        guard let cap = await CapabilityDetector.shared.ffmpeg(),
              let result = try? await ExternalProcess.run(cap.ffprobe, [
                "-v", "error", "-show_entries", "stream=codec_type,codec_name:format=duration",
                "-of", "json", url.path
              ]), result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else { return nil }
        let hasVideo = streams.contains { $0["codec_type"] as? String == "video" }
        let hasAudio = streams.contains { $0["codec_type"] as? String == "audio" }
        guard hasVideo || hasAudio else { return nil }
        let essentialStreams = streams.filter {
            let kind = $0["codec_type"] as? String
            return kind == "video" || kind == "audio"
        }
        guard essentialStreams.allSatisfy({ stream in
            guard let codec = stream["codec_name"] as? String else { return false }
            return cap.decoders.contains(codec)
        }) else { return nil }
        let format = json["format"] as? [String: Any]
        let duration = (format?["duration"] as? String).flatMap(Double.init)
        return ConversionInput(url: url, bookmark: bookmark,
                               type: fallbackType ?? UTType(filenameExtension: url.pathExtension) ?? .data,
                               size: size, category: hasVideo ? .video : .audio,
                               duration: duration, hasAudio: hasAudio, isDirectory: false)
    }
}
