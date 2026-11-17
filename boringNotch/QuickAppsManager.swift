import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class QuickAppsManager: ObservableObject {
    static let shared = QuickAppsManager()
    static let limit = 4

    @Published private(set) var favorites: [String]
    @Published var message: String?

    private let storageKey = "notchloom.quickApps"
    private let starterApps = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.Music",
        "com.apple.calculator"
    ]

    private init() {
        favorites = UserDefaults.standard.stringArray(forKey: storageKey) ?? starterApps
    }

    func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func name(for bundleID: String) -> String {
        guard let url = appURL(for: bundleID) else { return "Unavailable app" }
        let bundle = Bundle(url: url)
        return (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    func icon(for bundleID: String) -> NSImage? {
        guard let url = appURL(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func launch(_ bundleID: String) {
        guard let url = appURL(for: bundleID) else {
            message = "That app is no longer installed."
            return
        }
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: url, configuration: NSWorkspace.OpenConfiguration())
                message = nil
            } catch {
                message = "Could not open \(name(for: bundleID))."
            }
        }
    }

    func chooseApps() {
        guard favorites.count < Self.limit else {
            message = "Remove an app before adding another."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose apps for the notch"
        panel.prompt = "Add Apps"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in
                self?.add(panel.urls)
            }
        }
    }

    func remove(_ bundleID: String) {
        favorites.removeAll { $0 == bundleID }
        save()
    }

    func restoreDefaults() {
        favorites = starterApps
        message = nil
        save()
    }

    func move(_ bundleID: String, by offset: Int) {
        guard let index = favorites.firstIndex(of: bundleID),
              favorites.indices.contains(index + offset) else { return }
        favorites.swapAt(index, index + offset)
        save()
    }

    private func add(_ urls: [URL]) {
        var ignored = false
        for url in urls {
            guard favorites.count < Self.limit else { ignored = true; break }
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                ignored = true
                continue
            }
            if !favorites.contains(bundleID) { favorites.append(bundleID) }
        }
        save()
        message = ignored ? "Some apps could not be added. The notch holds four favorites." : nil
    }

    private func save() {
        UserDefaults.standard.set(favorites, forKey: storageKey)
    }
}
