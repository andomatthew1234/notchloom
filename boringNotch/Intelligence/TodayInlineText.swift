import AppKit
import SwiftUI

/// Native text layout keeps inline links, wrapping, selection and accessibility in one paragraph.
/// All links are created locally from registered IDs; this view never opens URLs.
struct TodayInlineText: NSViewRepresentable {
    let parts: [TodayReport.Part]
    let registry: TodayWidgetRegistry
    let allowedIDs: Set<String>
    var fontSize: CGFloat = 16
    var semibold = false
    let onHover: (String?, Bool) -> Void
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> TodayParagraphTextView {
        let view = TodayParagraphTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.isAutomaticLinkDetectionEnabled = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.focusRingType = .none
        view.delegate = context.coordinator
        view.linkTextAttributes = [.foregroundColor: NSColor(TodayPalette.blue),
                                   .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .underlineColor: NSColor(TodayPalette.blue).withAlphaComponent(0.45),
                                   .cursor: NSCursor.pointingHand]
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: TodayParagraphTextView, context: Context) {
        context.coordinator.onSelect = onSelect
        view.onHoverLink = onHover
        view.onSelect = onSelect
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 5
        let font = NSFont.systemFont(ofSize: fontSize, weight: semibold ? .semibold : .regular)
        let color = NSColor(TodayPalette.ink)
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let result = NSMutableAttributedString()
        var links: [URL: String] = [:]
        for part in parts {
            switch part.type {
            case .text:
                result.append(NSAttributedString(string: part.value ?? "", attributes: base))
            case .widgetReference, .sourceReference:
                let widget = part.widgetID.flatMap(registry.widget) ?? part.sourceReference.flatMap(registry.widget(for:))
                guard let widget, allowedIDs.contains(widget.id), let url = URL(string: "notchloom-today://widget/" + widget.id) else {
                    result.append(NSAttributedString(string: part.type == .sourceReference ? "Source unavailable" : "Related item unavailable", attributes: base))
                    continue
                }
                links[url] = widget.id
                var style = base
                style[.link] = url
                style[.font] = NSFont.systemFont(ofSize: fontSize, weight: .medium)
                style[.toolTip] = "Highlight " + widget.title
                result.append(NSAttributedString(string: part.type == .sourceReference ? "Source · " + widget.title : widget.linkLabel, attributes: style))
            }
        }
        context.coordinator.links = links
        view.links = links
        if view.textStorage?.isEqual(to: result) != true {
            view.textStorage?.setAttributedString(result)
            view.invalidateIntrinsicContentSize()
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TodayParagraphTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 350)
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).height) + 2)
    }
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var links: [URL: String] = [:]
        var onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL, let id = links[url] { onSelect(id) }
            return true // Includes unknown links: never defer to NSWorkspace or a browser.
        }
    }
}

final class TodayParagraphTextView: NSTextView {
    var links: [URL: String] = [:]
    var onHoverLink: ((String?, Bool) -> Void)?
    var onSelect: ((String) -> Void)?
    private var tracking: NSTrackingArea?
    private var hovered: String?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeAlways], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let next = linkedID(at: local)
        if hovered != next {
            onHoverLink?(hovered, false)
            hovered = next
            onHoverLink?(next, true)
        }
        super.mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) {
        onHoverLink?(hovered, false); hovered = nil
        super.mouseExited(with: event)
    }
    func linkedID(at point: NSPoint) -> String? {
        guard let manager = layoutManager, let container = textContainer, manager.numberOfGlyphs > 0 else { return nil }
        let location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: location, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(location),
              let url = textStorage?.attribute(.link, at: manager.characterIndexForGlyph(at: glyph), effectiveRange: nil) as? URL else { return nil }
        return links[url]
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            let selected = selectedRange().location
            if selected < (textStorage?.length ?? 0), let url = textStorage?.attribute(.link, at: selected, effectiveRange: nil) as? URL, let id = links[url] {
                onSelect?(id); return
            }
        }
        if event.keyCode == 48 {
            var ranges: [NSRange] = []
            textStorage?.enumerateAttribute(.link, in: NSRange(location: 0, length: textStorage?.length ?? 0)) { value, range, _ in
                if value != nil { ranges.append(range) }
            }
            let backwards = event.modifierFlags.contains(.shift)
            let selected = selectedRange()
            let next = backwards ? ranges.last(where: { $0.location < selected.location })
                : ranges.first(where: { selected.length == 0 ? $0.location >= selected.location : $0.location > selected.location })
            if let next { setSelectedRange(next); scrollRangeToVisible(next); return }
            if backwards { window?.selectPreviousKeyView(self) } else { window?.selectNextKeyView(self) }
            return
        }
        super.keyDown(with: event)
    }
}
