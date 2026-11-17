import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Reads only the banners macOS is currently drawing. It does not query the
/// Notification Center database or retain notification content in the helper.
enum NotificationBannerReader {
    private struct Banner: Encodable {
        let id: String
        let source: String
        let title: String
        let body: String
    }

    static func visibleBanners() -> Data {
        guard AXIsProcessTrusted() else { return Data("[]".utf8) }
        let hosts = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.UserNotificationCenter")
        let banners = hosts.flatMap { banners(in: $0.processIdentifier) }
        return (try? JSONEncoder().encode(banners)) ?? Data("[]".utf8)
    }

    private static func banners(in pid: pid_t) -> [Banner] {
        let application = AXUIElementCreateApplication(pid)
        guard let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] else {
            return []
        }

        return windows.prefix(12).compactMap { window in
            guard let frame = frame(of: window), isBanner(frame) else { return nil }

            var lines: [String] = []
            collectText(in: window, depth: 0, into: &lines)
            lines = lines.filter { !$0.isEmpty && $0.count < 500 }
            lines = Array(NSOrderedSet(array: lines)) as? [String] ?? lines
            guard let first = lines.first else { return nil }

            let source: String
            let title: String
            let body: String
            if lines.count >= 3 {
                source = first
                title = lines[1]
                body = lines[2]
            } else {
                source = "Notification"
                title = first
                body = lines.dropFirst().first ?? ""
            }

            // The window's position distinguishes concurrent, identical banners.
            let id = "\(pid):\(Int(frame.minX)):\(Int(frame.minY)):\(lines.joined(separator: "|"))"
            return Banner(id: id, source: source, title: title, body: body)
        }
    }

    private static func isBanner(_ frame: CGRect) -> Bool {
        guard (250...650).contains(frame.width), (50...300).contains(frame.height) else {
            return false
        }
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else {
            return false
        }
        return displays.prefix(Int(count)).contains { display in
            let screen = CGDisplayBounds(display)
            return frame.minY >= screen.minY - 2
                && frame.minY < screen.minY + 280
                && frame.maxX > screen.maxX - 800
                && frame.maxX <= screen.maxX + 8
        }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(kAXPositionAttribute, of: element),
              let sizeValue = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        let position = unsafeBitCast(positionValue, to: AXValue.self)
        let size = unsafeBitCast(sizeValue, to: AXValue.self)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private static func collectText(in element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth <= 5, lines.count < 8 else { return }
        let role = attribute(kAXRoleAttribute, of: element) as? String
        if role == kAXStaticTextRole || role == kAXTextAreaRole {
            if let value = attribute(kAXValueAttribute, of: element) as? String {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { lines.append(cleaned) }
            }
        }
        guard let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] else {
            return
        }
        for child in children.prefix(20) {
            collectText(in: child, depth: depth + 1, into: &lines)
        }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            ? value : nil
    }
}
