import AppKit
import SwiftUI

@main struct TodayPresentationTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label); checks += 1
        }
        let document = try TodayPreviewContent.makeStandard()
        let widgets = document.registry.widgets(for: document.report)
        check(widgets.count == 4, "Standard preview registers four widgets")
        check(document.isPreview, "Fictional content explicitly tagged")
        let ids = Set(widgets.map(\.id))
        check(document.report.report.blocks.contains { $0.type == .divider }, "Divider supported")
        check(document.report.report.blocks.contains { $0.parts.contains { $0.type == .sourceReference } }, "Source reference supported")
        let emptyRegistry = try TodayWidgetRegistry()
        check(emptyRegistry.widgets(for: document.report).isEmpty, "Missing native registrations degrade safely")
        for badBlock in [TodayReport.Block(id: "bad-divider", type: .divider, parts: [.init(type: .text, value: "not empty")]),
                         TodayReport.Block(id: "bad-source", type: .paragraph, parts: [.init(type: .sourceReference, sourceReference: .init(type: .calendarEvent, id: "invented"))])] {
            let bad = TodayReport(version: 1, title: "Test", blocks: [badBlock], widgets: [], scheduledInsights: [])
            do { _ = try TodayReportValidator.validate(JSONEncoder().encode(bad)); preconditionFailure("Unsafe extension accepted") } catch { checks += 1 }
        }
        do { _ = try TodayWidgetRegistry([widgets[0], widgets[0]]); preconditionFailure("Duplicate registration") } catch { checks += 1 }
        for scenario in TodayPreviewContent.Scenario.allCases {
            do {
                let preview = try TodayPreviewContent.make(scenario)
                check(scenario != .unsupported && scenario != .invalidReference, "Untrusted preview rejected")
                check(preview.isPreview, "Scenario labeled preview")
            } catch {
                check(scenario == .unsupported || scenario == .invalidReference, "Only intentionally invalid scenarios rejected")
            }
        }
        for (width, height, dock) in [(320.0, 400.0, 50.0), (744, 480, 75), (1440, 900, 60), (3840, 2160, 90)] {
            let frame = CGRect(x: -width, y: -100, width: width, height: height)
            let visible = CGRect(x: frame.minX, y: frame.minY + dock, width: width, height: height - dock - 32)
            let size = TodayPageGeometry.panelSize(screen: frame, visibleFrame: visible)
            check(size.width <= frame.width - 24 && size.height <= frame.maxY - visible.minY - 24, "Panel fits screen and dock")
            let host = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
            check(host.maxY == frame.maxY && host.midX == frame.midX, "Top anchored and centered including negative display origin")
        }
        for width in stride(from: CGFloat(280), through: 920, by: 20) {
            if let columns = TodayPageGeometry.columns(width: width) {
                check(columns.widgets >= 222 && columns.main >= 340 && columns.main + columns.widgets + 26 <= width + 0.5, "Readable columns without overflow")
            } else { check(width < TodayPageGeometry.twoColumnThreshold, "Narrow widths stack") }
        }
        let interactions = TodayLinkInteraction()
        interactions.hover("preview-meeting", active: true)
        check(interactions.hoveredID == "preview-meeting", "Hover highlights registered target")
        interactions.hover("other", active: false)
        check(interactions.hoveredID == "preview-meeting", "Stale exit cannot clear another hover")
        check(!interactions.select("invented", registeredIDs: ids) && interactions.emphasizedID == nil, "Invalid click does nothing")
        check(interactions.select("preview-meeting", registeredIDs: ids), "Click selects target")
        check(interactions.emphasizedID == "preview-meeting", "Target emphasized")
        try await Task.sleep(for: .milliseconds(1600))
        check(interactions.emphasizedID == nil, "Emphasis settles")
        interactions.reset()
        check(interactions.hoveredID == nil && interactions.emphasizedID == nil, "Disappear resets interaction tasks")

        // Offscreen test windows only. Never order front, activate the app or move the user's pointer.
        let folder = URL(fileURLWithPath: "/tmp/notchloom-today-phase2-review", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cases: [(String, TodayPreviewContent.Scenario, CGFloat, CGFloat)] = [
            ("wide", .linked, 682, 630), ("medium", .linked, 580, 630), ("narrow", .linked, 360, 600),
            ("short-display", .linked, 682, 300), ("long", .long, 682, 630),
            ("long-title", .longTitle, 360, 600), ("empty", .empty, 682, 460),
            ("no-widgets", .noWidgets, 682, 500), ("paragraphs", .paragraphs, 580, 600)
        ]
        for (name, scenario, width, height) in cases {
            let doc = try TodayPreviewContent.make(scenario)
            let host = NSHostingView(rootView: TodayPageView(document: doc, animationsEnabled: false)
                .frame(width: width, height: height).padding(14).background(.black).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: width + 28, height: height + 28), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(180))
            host.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let native = descendants(host).compactMap { $0 as? TodayParagraphTextView }
            for paragraph in native {
                if let manager = paragraph.layoutManager, let container = paragraph.textContainer {
                    manager.ensureLayout(for: container)
                    check(manager.usedRect(for: container).width <= paragraph.bounds.width + 2, "\(name) paragraph wraps within width")
                    if let storage = paragraph.textStorage {
                        var foundLink: (URL, NSRange)?
                        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                            if let url = value as? URL { foundLink = (url, range) }
                        }
                        if let (url, range) = foundLink {
                            let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
                            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                            let point = NSPoint(x: rect.midX + paragraph.textContainerOrigin.x, y: rect.midY + paragraph.textContainerOrigin.y)
                            check(paragraph.linkedID(at: point) == paragraph.links[url], "Native inline hover resolves correct widget")
                        }
                    }
                }
            }
            try snapshot(host, path: folder.appendingPathComponent(name + ".png"))
            let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
            if name == "wide", let paragraph = native.first(where: { $0.links.values.contains("preview-list") }),
               let url = paragraph.links.first(where: { $0.value == "preview-list" })?.key,
               let delegate = paragraph.delegate {
                check(delegate.textView?(paragraph, clickedOnLink: URL(string: "https://example.invalid")!, at: 0) == true, "Unknown links never open externally")
                check(delegate.textView?(paragraph, clickedOnLink: url, at: 0) == true, "Registered link handled inside Today")
                try await Task.sleep(for: .milliseconds(450))
                host.layoutSubtreeIfNeeded()
                let linkedScroll = scrolls.max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }
                check((linkedScroll?.contentView.bounds.origin.y ?? 0) > 0, "Click scrolls to linked card")
                try snapshot(host, path: folder.appendingPathComponent("linked-card-highlight.png"))
                if let storage = paragraph.textStorage {
                    var linkRange: NSRange?
                    storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                        if value as? URL == url { linkRange = range }
                    }
                    if let linkRange {
                        var activated: String?
                        let original = paragraph.onSelect
                        paragraph.onSelect = { activated = $0 }
                        paragraph.setSelectedRange(linkRange)
                        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                        paragraph.keyDown(with: enter)
                        check(activated == "preview-list", "Return activates selected native inline link")
                        paragraph.onSelect = original
                    }
                }
            }
            if scenario == .long || scenario == .linked {
                guard let scroll = scrolls.max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }), let content = scroll.documentView else { preconditionFailure("Missing native scroll view") }
                let distance = max(0, content.bounds.height - scroll.contentView.bounds.height)
                check(distance > 0, "Long or linked document scrolls")
                scroll.contentView.scroll(to: NSPoint(x: 0, y: distance))
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                check(scroll.contentView.bounds.origin.y > 0, "Native scrolling advances content")
                try snapshot(host, path: folder.appendingPathComponent(name + "-scrolled.png"))
            }
            window.close()
        }
        checks += try await TodayMotionReview.render(folder: folder, document: document)
        print("PASS \(checks) Today presentation checks; 9 layouts, scrolled states and opening/back motion samples rendered offscreen at \(folder.path). No real data or network used.")
    }
    @MainActor static func snapshot(_ host: NSView, path: URL) throws {
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    }
}
