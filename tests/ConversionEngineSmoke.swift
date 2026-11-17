import AppKit
import AVFoundation
import CoreVideo
import Foundation
import ImageIO

@main
struct ConversionEngineSmoke {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchloom-convert-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let original = folder.appendingPathComponent("holiday résumé 🧪.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<16 { for x in 0..<16 {
            bitmap.setColor(NSColor(calibratedRed: 0.1, green: 0.8, blue: 0.9, alpha: 1), atX: x, y: y)
        } }
        try bitmap.representation(using: .png, properties: [:])!.write(to: original)
        let input = try await ConversionInspector.inspect(original)
        precondition(input.category == .image)
        let firstDestination = ConversionOutputPlanner.uniqueURL(
            for: original, in: folder, extension: "jpg")
        try Data("occupied".utf8).write(to: firstDestination)
        let secondDestination = ConversionOutputPlanner.uniqueURL(
            for: original, in: folder, extension: "jpg")
        precondition(secondDestination != firstDestination && secondDestination.lastPathComponent.contains(" 2"))
        let sameExtension = ConversionOutputPlanner.uniqueURL(
            for: original, in: folder, extension: "png")
        precondition(sameExtension != original)
        let timestamped = ConversionOutputPlanner.uniqueURL(
            for: original, in: folder, extension: "jpg", collision: .timestamped)
        precondition(timestamped != firstDestination && timestamped.lastPathComponent.contains("20"))
        print("PASS output collisions and source protection")
        let engine = ImageIOConversionEngine()
        let formats = await engine.formats(for: input)
        precondition(formats.contains(ConversionFormats.jpeg))
        for format in formats where ["jpeg", "tiff", "bmp"].contains(format.id) {
            let output = folder.appendingPathComponent("result.\(format.fileExtension)")
            try await engine.convert(input: input, to: format, preset: .balanced, preserveMetadata: true,
                                     temporaryURL: output, progress: { _ in })
            let checked = try await ConversionInspector.inspect(output)
            precondition(checked.category == .image && checked.size > 0)
            guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                fatalError("Could not decode \(output.lastPathComponent)")
            }
            precondition(decoded.width == 16 && decoded.height == 16)
            print("PASS image: PNG → \(format.name), \(checked.size) bytes")
        }
        let brandingImage = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("branding/notchloom-generated.png")
        if FileManager.default.fileExists(atPath: brandingImage.path) {
            let brandingInput = try await ConversionInspector.inspect(brandingImage)
            let advertised = await engine.formats(for: brandingInput)
            var failures: [String] = []
            for format in advertised {
                let output = folder.appendingPathComponent("branding.\(format.fileExtension)")
                do {
                    try await engine.convert(input: brandingInput, to: format, preset: .balanced,
                                             preserveMetadata: true, temporaryURL: output, progress: { _ in })
                    let checked = try await ConversionInspector.inspect(output)
                    precondition(checked.category == .image && checked.size > 0)
                    let imageSource = CGImageSourceCreateWithURL(output as CFURL, nil)!
                    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
                    let alpha = properties?[kCGImagePropertyHasAlpha] as? Bool ?? false
                    FileHandle.standardError.write(Data("PASS advertised image format: \(format.name), alpha=\(alpha)\n".utf8))
                } catch {
                    failures.append("\(format.name): \(error.localizedDescription)")
                }
            }
            precondition(failures.isEmpty, failures.joined(separator: "; "))
        }

        let wav = folder.appendingPathComponent("tone with spaces.wav")
        var samples = Data()
        for i in 0..<8_000 {
            let value = Int16(sin(Double(i) * 2 * .pi * 440 / 8_000) * 10_000)
            samples.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        }
        var wave = Data("RIFF".utf8)
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            wave.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        }
        appendLE(UInt32(36 + samples.count))
        wave.append(contentsOf: Data("WAVEfmt ".utf8))
        appendLE(UInt32(16))
        appendLE(UInt16(1))
        appendLE(UInt16(1))
        appendLE(UInt32(8_000))
        appendLE(UInt32(16_000))
        appendLE(UInt16(2))
        appendLE(UInt16(16))
        wave.append(contentsOf: Data("data".utf8))
        appendLE(UInt32(samples.count))
        wave.append(samples)
        try wave.write(to: wav)
        let audioInput = try await ConversionInspector.inspect(wav)
        precondition(audioInput.category == .audio)
        let mediaEngine = AVFoundationConversionEngine()
        let audioFormats = await mediaEngine.formats(for: audioInput)
        precondition(audioFormats.contains(ConversionFormats.m4a))
        let m4a = folder.appendingPathComponent("tone converted.m4a")
        try await mediaEngine.convert(input: audioInput, to: ConversionFormats.m4a, preset: .balanced, preserveMetadata: true,
                                      temporaryURL: m4a, progress: { _ in })
        let checkedAudio = try await ConversionInspector.inspect(m4a)
        precondition(checkedAudio.category == .audio && checkedAudio.size > 0)
        print("PASS audio: WAV → M4A, \(checkedAudio.size) bytes")

        let movie = folder.appendingPathComponent("short movie.mov")
        try await makeMovie(at: movie)
        let movieInput = try await ConversionInspector.inspect(movie)
        precondition(movieInput.category == .video)
        let movieFormats = await mediaEngine.formats(for: movieInput)
        precondition(movieFormats.contains(ConversionFormats.mp4))
        let mp4 = folder.appendingPathComponent("short movie converted.mp4")
        try await mediaEngine.convert(input: movieInput, to: ConversionFormats.mp4,
                                      preset: .balanced, preserveMetadata: true,
                                      temporaryURL: mp4, progress: { _ in })
        let checkedMovie = try await ConversionInspector.inspect(mp4)
        precondition(checkedMovie.category == .video && checkedMovie.size > 0)
        print("PASS video: MOV → MP4, \(checkedMovie.size) bytes")

        let textFile = folder.appendingPathComponent("notes with spaces.txt")
        try Data("Meeting notes\nOne important line.\n".utf8).write(to: textFile)
        let documentInput = try await ConversionInspector.inspect(textFile)
        precondition(documentInput.category == .document)
        let documentEngine = TextUtilConversionEngine()
        let documentFormats = await documentEngine.formats(for: documentInput)
        precondition(documentFormats.contains(ConversionFormats.docx))
        let word = folder.appendingPathComponent("notes converted.docx")
        try await documentEngine.convert(input: documentInput, to: ConversionFormats.docx,
                                         preset: .balanced, preserveMetadata: true, temporaryURL: word, progress: { _ in })
        let checkedWord = try await ConversionInspector.inspect(word)
        precondition(checkedWord.category == .document && checkedWord.size > 0)
        let rtf = folder.appendingPathComponent("notes roundtrip.rtf")
        try await documentEngine.convert(input: checkedWord, to: ConversionFormats.rtf,
                                         preset: .balanced, preserveMetadata: true, temporaryURL: rtf, progress: { _ in })
        let rtfText = try String(contentsOf: rtf, encoding: .utf8)
        precondition(rtfText.contains("Meeting notes") && rtfText.contains("One important line"))
        print("PASS document: TXT → DOCX → RTF, text preserved")

        let sourceFolder = folder.appendingPathComponent("Project Files", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try Data("archive contents".utf8).write(to: sourceFolder.appendingPathComponent("read me.txt"))
        let archiveInput = try await ConversionInspector.inspect(sourceFolder)
        precondition(archiveInput.category == .archive && archiveInput.isDirectory)
        let archiveEngine = ArchiveConversionEngine()
        let archiveFormats = await archiveEngine.formats(for: archiveInput)
        precondition(archiveFormats == [ConversionFormats.zip])
        let zip = folder.appendingPathComponent("Project Files.zip")
        try await archiveEngine.convert(input: archiveInput, to: ConversionFormats.zip,
                                        preset: .balanced, preserveMetadata: true,
                                        temporaryURL: zip, progress: { _ in })
        let checkedZIP = try await ConversionInspector.inspect(zip)
        precondition(checkedZIP.category == .archive && checkedZIP.size > 0)
        let extracted = folder.appendingPathComponent("Extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, extracted.path]
        try ditto.run()
        ditto.waitUntilExit()
        precondition(ditto.terminationStatus == 0)
        let restored = extracted.appendingPathComponent("Project Files/read me.txt")
        let restoredText = try String(contentsOf: restored, encoding: .utf8)
        precondition(restoredText == "archive contents")
        print("PASS archive: folder → ZIP → extracted contents")

        let corrupt = folder.appendingPathComponent("broken.png")
        try Data("not a PNG".utf8).write(to: corrupt)
        do {
            _ = try await ConversionInspector.inspect(corrupt)
            fatalError("Corrupt input was accepted")
        } catch {
            print("PASS malformed input rejected")
        }
        let unsupported = folder.appendingPathComponent("unsupported.xyz")
        try Data("nothing to convert".utf8).write(to: unsupported)
        do {
            _ = try await ConversionInspector.inspect(unsupported)
            fatalError("Unsupported input was accepted")
        } catch {
            print("PASS unsupported input rejected")
        }
        if await CapabilityDetector.shared.ffmpeg() == nil {
            let optionalFormats = await FFmpegConversionEngine().formats(for: movieInput)
            precondition(optionalFormats.isEmpty)
            print("PASS absent FFmpeg does not advertise formats")
        }
        let cancellationStart = Date()
        let processTask = Task {
            try await ExternalProcess.run(URL(fileURLWithPath: "/bin/sleep"), ["5"])
        }
        try await Task.sleep(for: .milliseconds(150))
        processTask.cancel()
        _ = try? await processTask.value
        precondition(Date().timeIntervalSince(cancellationStart) < 2,
                     "External process did not terminate promptly after cancellation")
        print("PASS external conversion process cancellation")
    }

    private static func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            let attributes: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                                             kCVPixelFormatType_32ARGB,
                                             attributes as CFDictionary, &buffer) == kCVReturnSuccess)
            precondition(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        precondition(writer.status == .completed)
    }
}
