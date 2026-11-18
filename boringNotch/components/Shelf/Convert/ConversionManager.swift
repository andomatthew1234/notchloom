import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ConversionManager: ObservableObject {
    static let shared = ConversionManager()

    enum Stage: Equatable { case idle, preparing, setup, running, finished }
    enum Presentation: Equatable {
        case shelf, entering, ready, converting, success, failure, cancelled, exiting
        var isExpanded: Bool { self != .shelf && self != .exiting }
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var presentation: Presentation = .shelf
    @Published private(set) var presentationScreenID: String?
    @Published private(set) var inputs: [ConversionInput] = []
    @Published private(set) var jobs: [ConversionJob] = []
    @Published private(set) var formats: [ConversionFormat] = []
    @Published var selectedFormatID = ""
    @Published var selectedCategory: ConversionCategory = .image
    @Published var preset: ConversionPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: "notchloom.convert.preset") }
    }
    @Published private(set) var message: String?
    @Published private(set) var technicalDetails: String?
    @Published var isHovered = false

    private let engines: [any ConversionEngine] = [
        ImageIOConversionEngine(), AVFoundationConversionEngine(), FFmpegConversionEngine(),
        TextUtilConversionEngine(), ArchiveConversionEngine()
    ]
    private var runTask: Task<Void, Never>?
    private var currentTask: Task<Void, Error>?
    private var dismissTask: Task<Void, Never>?
    private var cancelAllRequested = false
    private var closeAfterCancellation = false
    private var interactionHeld = false
    private var generation = UUID()
    private var convertedInputIDs = Set<UUID>()
    private var selectedInputID: UUID?
    private init() {
        preset = ConversionPreset(rawValue: UserDefaults.standard.string(forKey: "notchloom.convert.preset") ?? "") ?? .balanced
    }

    var categoryInputs: [ConversionInput] {
        inputs.filter { $0.category == selectedCategory && !convertedInputIDs.contains($0.id)
            && (selectedInputID == nil || $0.id == selectedInputID) }
    }
    var availableCategories: [ConversionCategory] {
        Array(Set(inputs.filter { !convertedInputIDs.contains($0.id) }.map(\.category)))
            .sorted { $0.rawValue < $1.rawValue }
    }
    var nextCategory: ConversionCategory? {
        inputs.first { !convertedInputIDs.contains($0.id) }?.category
    }
    var selectedFormat: ConversionFormat? { formats.first { $0.id == selectedFormatID } }
    var completedCount: Int { jobs.filter { $0.state == .completed }.count }
    var failedCount: Int { jobs.filter { $0.state == .failed }.count }
    var cancelledCount: Int { jobs.filter { $0.state == .cancelled }.count }
    var queuedCount: Int { jobs.filter { $0.state == .queued }.count }
    var totalSize: Int64 { categoryInputs.reduce(0) { $0 + $1.size } }
    var currentJob: ConversionJob? { jobs.first { $0.state == .running } }
    var outputs: [URL] { jobs.compactMap(\.outputURL) }
    var overallProgress: Double? {
        guard !jobs.isEmpty else { return nil }
        let done = Double(completedCount + failedCount + jobs.filter { $0.state == .cancelled }.count)
        if let current = currentJob?.progress?.fraction {
            return (done + current) / Double(jobs.count)
        }
        return currentJob == nil ? done / Double(jobs.count) : nil
    }

    func prepare(providers: [NSItemProvider], screenID: String?) {
        guard presentation == .shelf || presentation == .success || presentation == .failure
                || presentation == .cancelled else { return }
        generation = UUID()
        let currentGeneration = generation
        resetState()
        presentationScreenID = screenID
        presentation = .entering
        stage = .preparing
        holdInteraction()
        Task { @MainActor in
            var found: [ConversionInput] = []
            var rejected = 0
            var firstRejection: String?
            for provider in providers.prefix(200) {
                guard generation == currentGeneration else { return }
                let primary = await provider.extractFileURL()
                let url: URL?
                if let primary { url = primary } else { url = await provider.extractURL() }
                guard let url,
                      url.isFileURL else {
                    rejected += 1
                    firstRejection = firstRejection ?? "Only files and folders can be converted."
                    continue
                }
                let rootScoped = url.startAccessingSecurityScopedResource()
                defer { if rootScoped { url.stopAccessingSecurityScopedResource() } }
                let urls = [url]
                for fileURL in urls where found.count < 200 {
                    let scoped = fileURL.startAccessingSecurityScopedResource()
                    defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
                    do {
                        let bookmark = try? Bookmark(url: fileURL).data
                        found.append(try await ConversionInspector.inspect(fileURL, bookmark: bookmark))
                    } catch {
                        rejected += 1
                        firstRejection = firstRejection ?? error.localizedDescription
                    }
                }
            }
            guard generation == currentGeneration, presentation != .exiting else { return }
            inputs = found
            if found.isEmpty {
                message = firstRejection ?? "No supported files were found."
                technicalDetails = "\(rejected) item(s) could not be read or decoded."
                stage = .finished
                presentation = .failure
                scheduleDismissal()
                return
            }
            selectedCategory = found[0].category
            selectedInputID = nil
            if rejected > 0 { message = "\(rejected) item(s) skipped. \(firstRejection ?? "")" }
            await refreshFormats()
            guard generation == currentGeneration, presentation != .exiting else { return }
            stage = .setup
            if presentation != .entering { presentation = .ready }
        }
    }

    func selectCategory(_ category: ConversionCategory) {
        guard stage == .setup else { return }
        selectedCategory = category
        selectedInputID = nil
        Task { await refreshFormats() }
    }

    private func refreshFormats() async {
        let currentGeneration = generation
        let group = categoryInputs
        guard !group.isEmpty else { formats = []; selectedFormatID = ""; return }
        var offered: [(ConversionInput, [ConversionFormat])] = []
        for input in group { offered.append((input, await formatsFor(input))) }
        let initial = offered[0].1
        var sharedIDs = Set(initial.map(\.id))
        for (_, options) in offered.dropFirst() { sharedIDs.formIntersection(options.map(\.id)) }
        guard generation == currentGeneration, presentation != .exiting else { return }
        if sharedIDs.isEmpty && group.count > 1 {
            if let choice = offered.first(where: { !$0.1.isEmpty }) {
                selectedInputID = choice.0.id
                formats = choice.1
                message = "These files need different formats. Convert this one first; the rest will follow."
            } else {
                formats = []
            }
        } else {
            selectedInputID = nil
            formats = initial.filter { sharedIDs.contains($0.id) }
        }
        selectedFormatID = formats.first?.id ?? ""
        if formats.isEmpty {
            message = "These files have no common output format with the converters available on this Mac."
        }
    }

    private func formatsFor(_ input: ConversionInput) async -> [ConversionFormat] {
        let scopedURL = input.bookmark.flatMap { Bookmark(data: $0).resolveURL() } ?? input.url
        let scoped = scopedURL.startAccessingSecurityScopedResource()
        defer { if scoped { scopedURL.stopAccessingSecurityScopedResource() } }
        var all: [ConversionFormat] = []
        for engine in engines { all.append(contentsOf: await engine.formats(for: input)) }
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted }
    }

    func start() {
        guard stage == .setup, let format = selectedFormat, !categoryInputs.isEmpty else { return }
        do {
            try ConversionPreferences.shared.authorizeOutputFolders(for: categoryInputs)
        } catch {
            message = error.localizedDescription
            return
        }
        cancelAllRequested = false
        message = nil
        technicalDetails = nil
        jobs = categoryInputs.map { ConversionJob(input: $0, format: format) }
        convertedInputIDs.formUnion(jobs.map { $0.input.id })
        stage = .running
        presentation = .converting
        let currentGeneration = generation
        runTask = Task { await runQueue(generation: currentGeneration) }
    }

    func retryFailed() {
        guard stage == .finished else { return }
        let failed = jobs.filter { $0.state == .failed }
        guard !failed.isEmpty else { return }
        do {
            try ConversionPreferences.shared.authorizeOutputFolders(for: failed.map(\.input))
        } catch {
            message = error.localizedDescription
            return
        }
        jobs = failed.map { ConversionJob(input: $0.input, format: $0.format) }
        cancelAllRequested = false
        message = nil
        stage = .running
        presentation = .converting
        holdInteraction()
        let currentGeneration = generation
        runTask = Task { await runQueue(generation: currentGeneration) }
    }

    func continueWithNextCategory() {
        guard stage == .finished, let category = nextCategory else { return }
        selectedCategory = category
        selectedInputID = nil
        jobs = []
        message = nil
        technicalDetails = nil
        stage = .setup
        presentation = .ready
        Task { await refreshFormats() }
    }

    private func runQueue(generation activeGeneration: UUID) async {
        for index in jobs.indices {
            guard generation == activeGeneration, jobs.indices.contains(index) else { return }
            if cancelAllRequested || Task.isCancelled {
                jobs[index].state = .cancelled
                continue
            }
            jobs[index].state = .running
            jobs[index].startedAt = Date()
            let input = jobs[index].input
            let format = jobs[index].format
            let started = Date()
            let sourceURL = input.bookmark.flatMap { Bookmark(data: $0).resolveURL() } ?? input.url
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                let folder = try ConversionPreferences.shared.resolvedFolder(for: input.url)
                let folderScoped = folder.startAccessingSecurityScopedResource()
                defer { if folderScoped { folder.stopAccessingSecurityScopedResource() } }
                let destination = ConversionOutputPlanner.uniqueURL(
                    for: input.url, in: folder, extension: format.fileExtension,
                    addConverted: ConversionPreferences.shared.naming == .converted,
                    collision: ConversionPreferences.shared.collision)
                let temporary = folder.appendingPathComponent(
                    ".notchloom-\(UUID().uuidString).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    throw ConversionError.invalidInput("The original file is no longer available.")
                }
                let capacity = try? destination.deletingLastPathComponent().resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                let free = capacity?.volumeAvailableCapacityForImportantUsage ?? 0
                if free > 0 && Int64(free) < max(input.size, 32 * 1024 * 1024) {
                    throw ConversionError.noSpace
                }
                guard let engine = await engine(for: input, format: format) else {
                    throw ConversionError.unavailable("The converter for this format is no longer available.")
                }
                currentTask = Task {
                    try await engine.convert(input: input, to: format, preset: preset,
                                             preserveMetadata: ConversionPreferences.shared.preserveMetadata,
                                             temporaryURL: temporary) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == activeGeneration,
                              self.jobs.indices.contains(index), self.jobs[index].state == .running else { return }
                        let elapsed = Date().timeIntervalSince(started)
                        let bounded = fraction.map { min(1, max(0, $0)) }
                        let remaining = bounded.flatMap { $0 > 0.02 ? elapsed * (1 - $0) / $0 : nil }
                        let previous = self.jobs[index].progress
                        let monotonic = bounded.map { max(previous?.fraction ?? 0, $0) }
                        if let previous, elapsed - previous.elapsed < 0.08,
                           abs((monotonic ?? 0) - (previous.fraction ?? 0)) < 0.025 { return }
                        self.jobs[index].progress = ConversionProgress(
                            fraction: monotonic, elapsed: elapsed, remaining: remaining)
                    }
                    }
                }
                try await currentTask?.value
                currentTask = nil
                guard generation == activeGeneration else { return }
                try Task.checkCancellation()
                let result = try destinationResult(at: temporary)
                guard result > 0 else { throw ConversionError.failed("The output file is empty.") }
                let checked = try await ConversionInspector.inspect(temporary)
                guard checked.category == format.category else {
                    throw ConversionError.failed("The output could not be decoded as \(format.category.rawValue.lowercased()).")
                }
                // The temporary output and destination are in one directory, so the move is atomic.
                try FileManager.default.moveItem(at: temporary, to: destination)
                jobs[index].outputURL = destination
                jobs[index].state = .completed
            } catch {
                currentTask = nil
                guard generation == activeGeneration else { return }
                jobs[index].state = (error as? ConversionError).map {
                    if case .cancelled = $0 { return .cancelled }
                    return .failed
                } ?? (Task.isCancelled || error is CancellationError ? .cancelled : .failed)
                jobs[index].error = error.localizedDescription
                technicalDetails = String(describing: error)
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
        guard generation == activeGeneration else { return }
        stage = .finished
        presentation = (cancelAllRequested || cancelledCount > 0) && failedCount == 0 ? .cancelled
            : failedCount > 0 ? .failure : .success
        runTask = nil
        if closeAfterCancellation {
            closeAfterCancellation = false
            scheduleDismissal(after: 2)
        } else { scheduleDismissal() }
    }

    private func engine(for input: ConversionInput, format: ConversionFormat) async -> (any ConversionEngine)? {
        for engine in engines where await engine.formats(for: input).contains(where: { $0.id == format.id }) {
            return engine
        }
        return nil
    }

    func cancelCurrent() { currentTask?.cancel() }
    func cancelAll() {
        guard stage == .running else { return }
        cancelAllRequested = true
        currentTask?.cancel()
    }

    func close() {
        guard presentation != .exiting && presentation != .shelf else { return }
        if stage == .running {
            closeAfterCancellation = true
            cancelAll()
            return
        }
        dismissTask?.cancel()
        presentation = .exiting
    }

    func entranceCompleted() {
        if presentation == .entering { presentation = .ready }
    }

    func exitCompleted() {
        guard presentation == .exiting else { return }
        generation = UUID()
        resetState()
        stage = .idle
        presentation = .shelf
        releaseInteraction()
    }

    private func resetState() {
        dismissTask?.cancel()
        presentationScreenID = nil
        inputs = []
        convertedInputIDs = []
        selectedInputID = nil
        jobs = []
        formats = []
        selectedFormatID = ""
        message = nil
        technicalDetails = nil
    }

    private func holdInteraction() {
        guard !interactionHeld else { return }
        interactionHeld = true
        SharingStateManager.shared.beginInteraction()
    }

    private func releaseInteraction() {
        guard interactionHeld else { return }
        interactionHeld = false
        SharingStateManager.shared.endInteraction()
    }

    private func scheduleDismissal(after seconds: Double = 10) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, !isHovered, stage == .finished else { return }
            close()
        }
    }

    func hoverChanged(_ hovering: Bool) {
        isHovered = hovering
        if hovering { dismissTask?.cancel() }
        else if stage == .finished { scheduleDismissal() }
    }

    private func destinationResult(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ConversionError.failed("No output file was created.") }
        return Int64(values.fileSize ?? 0)
    }
}
