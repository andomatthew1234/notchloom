import Combine
import Foundation

@MainActor
final class FocusTimerManager: ObservableObject {
    enum Phase: String {
        case idle, running, paused, finished
    }

    static let shared = FocusTimerManager()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published private(set) var remaining: TimeInterval = 25 * 60

    private let prefix = "notchloom.focusTimer."
    private var deadline: Date?
    private var ticker: AnyCancellable?

    private init() {
        let defaults = UserDefaults.standard
        let savedDuration = defaults.double(forKey: prefix + "duration")
        duration = savedDuration >= 60 ? savedDuration : 25 * 60
        if let savedPhase = defaults.string(forKey: prefix + "phase"),
           let restored = Phase(rawValue: savedPhase) {
            phase = restored
            if restored == .running,
               let savedDeadline = defaults.object(forKey: prefix + "deadline") as? Date {
                deadline = savedDeadline
                remaining = max(0, savedDeadline.timeIntervalSinceNow)
                if remaining == 0 { finish(announce: false) }
            } else if restored == .paused {
                remaining = max(0, defaults.double(forKey: prefix + "remaining"))
            } else if restored == .finished {
                remaining = 0
            } else {
                phase = .idle
                remaining = duration
            }
        } else {
            remaining = duration
        }

        ticker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / duration))
    }

    var timeLabel: String {
        let seconds = Int(ceil(remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func start(minutes: Int) {
        guard minutes > 0 else { return }
        duration = TimeInterval(minutes * 60)
        remaining = duration
        deadline = Date().addingTimeInterval(duration)
        phase = .running
        persist()
    }

    func pause() {
        guard phase == .running else { return }
        remaining = max(0, deadline?.timeIntervalSinceNow ?? remaining)
        deadline = nil
        phase = .paused
        persist()
    }

    func resume() {
        guard phase == .paused, remaining > 0 else { return }
        deadline = Date().addingTimeInterval(remaining)
        phase = .running
        persist()
    }

    func reset() {
        deadline = nil
        phase = .idle
        remaining = duration
        persist()
    }

    private func tick() {
        guard phase == .running, let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        if remaining == 0 { finish(announce: true) }
    }

    private func finish(announce: Bool) {
        deadline = nil
        remaining = 0
        phase = .finished
        persist()
        if announce {
            NotificationMirror.shared.showLocal(
                title: "Focus time complete",
                body: "Nice work. Take a moment to reset."
            )
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(phase.rawValue, forKey: prefix + "phase")
        defaults.set(duration, forKey: prefix + "duration")
        defaults.set(remaining, forKey: prefix + "remaining")
        defaults.set(deadline, forKey: prefix + "deadline")
    }
}
