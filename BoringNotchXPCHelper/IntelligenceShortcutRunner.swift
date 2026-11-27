import Foundation

private struct ShortcutReply: Codable {
    let response: String?
    let error: String?
}

/// Runs the public Shortcuts CLI outside the app sandbox. The helper is already
/// embedded and signed with Notchloom; no shell, download, or private AI API is used.
final class IntelligenceShortcutRunner {
    private let lock = NSLock()
    private var processes: [String: Process] = [:]
    private var cancelled: Set<String> = []

    func run(name: String, prompt: String, requestID: String, reply: @escaping (Data) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result: ShortcutReply
            do {
                result = ShortcutReply(response: try execute(name: name, prompt: prompt, requestID: requestID), error: nil)
            } catch {
                result = ShortcutReply(response: nil, error: error.localizedDescription)
            }
            reply((try? JSONEncoder().encode(result)) ?? Data())
        }
    }

    func cancel(requestID: String) {
        lock.lock()
        cancelled.insert(requestID)
        if let process = processes[requestID], process.isRunning { process.terminate() }
        lock.unlock()
    }

    private func execute(name: String, prompt: String, requestID: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RunnerError("Choose a Shortcut in Intelligence settings first.") }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts") else {
            throw RunnerError("The macOS Shortcuts command-line tool is unavailable.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Notchloom-Intelligence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("prompt.txt")
        let output = directory.appendingPathComponent("response.txt")
        let errors = directory.appendingPathComponent("errors.txt")
        try prompt.write(to: input, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: output)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed, "--input-path", input.path, "--output-type", "public.plain-text"]
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        lock.lock()
        if cancelled.contains(requestID) {
            cancelled.remove(requestID)
            lock.unlock()
            throw RunnerError("Cancelled.")
        }
        processes[requestID] = process
        lock.unlock()

        defer {
            lock.lock()
            processes.removeValue(forKey: requestID)
            cancelled.remove(requestID)
            lock.unlock()
        }

        try process.run()
        process.waitUntilExit()
        lock.lock()
        let wasCancelled = cancelled.contains(requestID)
        lock.unlock()
        if wasCancelled { throw RunnerError("Cancelled.") }
        let diagnostic = (try? String(contentsOf: errors, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw RunnerError(diagnostic.isEmpty ? "The Shortcut failed. Check its name and Use Model action." : diagnostic)
        }
        let response = (try? String(contentsOf: output, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !response.isEmpty else {
            throw RunnerError(diagnostic.isEmpty ? "The Shortcut returned no text. Make its final action output the model response." : diagnostic)
        }
        return response
    }
}

private struct RunnerError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
