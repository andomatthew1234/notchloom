import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Reads only the banners macOS is currently drawing. It does not query the
/// Notification Center database or retain notification content in the helper.
enum NotificationBannerReader {
    private struct Snapshot: Encodable {
        let accessibilityAuthorized: Bool
        let banners: [Banner]
    }

    private struct Banner: Encodable {
        let id: String
        let source: String
        let title: String
        let body: String
        let deliveryID: String?
    }

    static func visibleBanners() -> Data {
        let authorized = AXIsProcessTrusted()
        let hosts = ["com.apple.UserNotificationCenter", "com.apple.notificationcenterui"]
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        let banners = authorized ? hosts.flatMap { banners(in: $0.processIdentifier) } : []
        return (try? JSONEncoder().encode(Snapshot(accessibilityAuthorized: authorized, banners: banners))) ?? Data()
    }

    private static func banners(in pid: pid_t) -> [Banner] {
        let application = AXUIElementCreateApplication(pid)
        guard let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] else {
            return []
        }

        var results: [Banner] = []
        for window in windows.prefix(24) {
            guard let windowBounds = frame(of: window), windowBounds.width >= 240,
                  windowBounds.height >= 40 else { continue }
            // Recent macOS versions draw multiple cards inside a transparent
            // display-sized window. Inspect card geometry before filtering the host.
            var candidates: [AXUIElement] = []
            var visited = 0
            collectCards(in: window, depth: 0, visited: &visited, into: &candidates)
            if candidates.isEmpty, let bounds = frame(of: window), isBanner(bounds) {
                candidates = [window]
            }
            for card in candidates {
                var lines: [String] = []
                var textVisited = 0
                collectText(in: card, depth: 0, visited: &textVisited, into: &lines)
                lines = lines.filter { !$0.isEmpty && $0.count <= 4000 }
                lines = Array(NSOrderedSet(array: lines)) as? [String] ?? lines
                guard !lines.isEmpty else { continue }
                let identifier = attribute(kAXIdentifierAttribute, of: card) as? String
                    ?? String(CFHash(card))
                let source = lines.count >= 2 ? lines[0] : "Notification"
                let title = lines.count >= 2 ? lines[1] : lines[0]
                let body = lines.dropFirst(2).joined(separator: "\n")
                let id = "\(pid):\(identifier):\(lines.joined(separator: "|"))"
                let deliveryID = UUID(uuidString: identifier) == nil ? nil : "\(pid):\(identifier)"
                results.append(Banner(id: id, source: source, title: title, body: body, deliveryID: deliveryID))
            }
        }
        return results
    }

    private static func collectCards(in element: AXUIElement, depth: Int,
                                     visited: inout Int, into cards: inout [AXUIElement]) {
        guard depth <= 10, visited < 320, cards.count < 24 else { return }
        visited += 1
        if let identifier = attribute(kAXIdentifierAttribute, of: element) as? String,
           identifier.hasPrefix("widget-local:") { return }
        let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
        let textIDs = children.compactMap { attribute(kAXIdentifierAttribute, of: $0) as? String }
        if isNotificationCard(role: attribute(kAXRoleAttribute, of: element) as? String,
                              childIdentifiers: textIDs),
           let bounds = frame(of: element), isBanner(bounds) {
            cards.append(element)
            return
        }
        for child in children.prefix(40) {
            collectCards(in: child, depth: depth + 1, visited: &visited, into: &cards)
        }
    }

    static func isNotificationCard(role: String?, childIdentifiers: [String]) -> Bool {
        role == kAXGroupRole && childIdentifiers.contains("title") && childIdentifiers.contains("body")
    }

    static func isBanner(_ frame: CGRect) -> Bool {
        guard (240...650).contains(frame.width), (40...600).contains(frame.height) else {
            return false
        }
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else {
            return false
        }
        return displays.prefix(Int(count)).contains { display in
            let screen = CGDisplayBounds(display)
            return isBanner(frame, on: screen)
        }
    }

    static func isBanner(_ frame: CGRect, on screen: CGRect) -> Bool {
        // Include stacked and expanded alerts, but exclude the full-height
        // Notification Center drawer and widgets away from the right edge.
        guard screen.height >= 64 else { return false }
        return (240...650).contains(frame.width) && (40...min(600, screen.height - 24)).contains(frame.height)
            && frame.minY >= screen.minY - 2 && frame.maxY <= screen.maxY + 8
            && frame.maxX >= screen.maxX - 80 && frame.maxX <= screen.maxX + 8
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

    private static func collectText(in element: AXUIElement, depth: Int, visited: inout Int, into lines: inout [String]) {
        guard depth <= 14, visited < 320, lines.count < 24 else { return }
        visited += 1
        let role = attribute(kAXRoleAttribute, of: element) as? String
        if role == kAXStaticTextRole || role == kAXTextAreaRole || role == "AXHeading" {
            if let value = (attribute(kAXValueAttribute, of: element) as? String)
                ?? (attribute(kAXTitleAttribute, of: element) as? String)
                ?? (attribute(kAXDescriptionAttribute, of: element) as? String) {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { lines.append(cleaned) }
            }
        }
        guard let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] else {
            return
        }
        for child in children.prefix(40) {
            collectText(in: child, depth: depth + 1, visited: &visited, into: &lines)
        }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            ? value : nil
    }
}
