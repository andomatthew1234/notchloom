# Notchloom Today — Phase 2

Notchloom 2.8.8, build 308 · 20 November 2026

## Experience

Click the Today widget in Overview → Dashboard to open a scrollable Today page inside the existing notch. The invitation has a subtle press response. Its sky background shares geometry with the full hero; the greeting and report reveal separately so text does not stretch with the surface. Back to Dashboard contracts the page. Close, Escape and outside clicks dismiss it. Opening Settings also closes Today so the expanded panel does not cover the settings window.

The surface uses the existing notch window, physical top-edge anchoring, screen centering and pointer routing. The transparent host grows before expansion and shrinks after contraction. The expanded panel fits the display and leaves room above the Dock. Display changes recalculate its bounds. Today does not create another floating window.

The standard experience is deliberately a **design preview with fictional examples**. It is clearly labeled, needs no API key and sends no requests. No real calendar, weather, notification, reminder or scheduled-insight integration was added.

## Presentation and renderer

`TodayPageView` accepts a `TodayPageDocument` containing the existing `ValidatedTodayReport`, a caller-registered `TodayWidgetRegistry`, supporting hero copy and a preview flag. A real validated Gemini report can be supplied later through the same interface. Preview data is separate from the real request/data pipeline.

`TodayReportBlockView` renders native headings, paragraphs, highlights, information cards and dividers. `TodayInlineText` uses NSTextView/TextKit for paragraph wrapping, inline links, text selection and accessibility. It renders literal text, not arbitrary Markdown or HTML. Model content controls semantics; Notchloom owns all fonts, colors, spacing, icons and layouts.

The Phase 1 Codable model remains the only report format. Its updated version 1 validator/schema adds a divider block with empty parts and an optional, exclusive source-reference part. Existing Phase 1 reports still decode. Unknown fields/types, invented references and invalid combinations continue to be rejected.

## Linked cards

The trusted registry supplies native display content and labels for calendar-event, weather, message, reminder and information cards. Reminder presentation uses the existing information widget kind. The report selects registered IDs; it cannot supply executable actions, external URLs or styling. The renderer also checks registry/type/source agreement when choosing visible cards.

Hovering an inline reference highlights its matching card. Clicking scrolls the card into view, emphasizes its border and lets the emphasis settle after 1.5 seconds. Source references use the same preview-only resolution. Return/Space activates a selected native link, and Tab navigates inline links. The corresponding card receives accessibility focus. Unknown link URLs are always handled without opening them; missing native registrations become non-actionable fallback text. Invalid preview reports show a safe unavailable state.

## Layout and motion

- Sky gradient, golden sunlight, large rounded greeting and an original sweeping white curve connect the widget and full-page designs.
- The 16-point briefing text has six points of extra line spacing, 21-point headings and native inline reference styling.
- Wide reading regions use a roughly 61–65% briefing / 35–39% card split, accounting for the gutter. Cards remain at least 222 points wide.
- Below 600 points of usable reading width, cards stack beneath the briefing. At the normal notch width, two columns fit.
- Short displays get a compact hero; long titles wrap and grow naturally. Empty reports have a designed empty state.
- Navigation remains outside the native vertical ScrollView. Trackpad momentum and text selection stay with the scrollable content.
- Native scroll-ownership exclusion and explicit Today guards prevent horizontal tab navigation or the notch's vertical close gesture from handling Today scrolling. The reusable pan modifier disables its drag recognition without changing subtree identity and resets pending recognition when disabled.
- Expansion uses a restrained spring. Text and cards reveal with small paragraph-aware offsets and capped stagger delays; there is no character-by-character animation or rewrapping effect. Reduce Motion removes the shared-geometry effect and content offsets/staggers.
- The sun's ambient change is a single entrance transition. There is no continuous animation timer, idle polling or background generation.
- Dismissal monitors and link emphasis tasks are removed/reset when the page leaves. Pointer routing still yields clicks outside the visible notch, and focus restoration is guarded so another app or Settings is not displaced.

## Source files

New files:

| File | Purpose |
| --- | --- |
| `boringNotch/Intelligence/TodayPresentation.swift` | Trusted registry, presentation document, responsive geometry and link interaction state |
| `boringNotch/Intelligence/TodayPreviewContent.swift` | Controlled standard preview and DEBUG-only scenario catalog |
| `boringNotch/Intelligence/TodayInlineText.swift` | Native paragraph layout, hover hit testing and safe link/keyboard handling |
| `boringNotch/Intelligence/TodayPageView.swift` | Hero, report blocks, adaptive columns, cards, navigation, empty/error states and Xcode preview gallery |
| `boringNotch/Intelligence/TodayNotchInteraction.swift` | Scoped keyboard focus and non-consuming dismissal observers |
| `tests/TodayPresentationTests.swift` | Report, registry, geometry, native layout/link/scroll checks and screenshots |
| `tests/TodayMotionReview.swift` | Offscreen opening/back motion study with top/center checks |
| `tests/run-today-checks.sh` | Standalone test runner |

Modified files: `TodayReport.swift`, `NotchToolsView.swift`, `TodayWidget.swift`, `BoringHeader.swift`, `BoringViewModel.swift`, `ContentView.swift`, `BoringNotchSkyLightWindow.swift`, `PanGesture.swift` and `boringNotch.xcodeproj/project.pbxproj`. This report and four saved preview images were added. Other preexisting working-tree changes were retained.

The general Intelligence provider, Gemini settings, credential management, model selection and network client were not rewritten. Background music, Focus Timer and Shelf operations are retained.

## Verification

**Signed Release and Debug builds passed.** The existing project still has unrelated media/deprecation/concurrency warnings; no new Today compilation warnings were reported.

**171 Today checks passed**, including:

- Trusted registrations, missing registrations and duplicate registration rejection.
- Existing semantic blocks, divider validation and verified source references.
- All nine DEBUG scenarios, including rejection of invented references and unsupported block types.
- Screen-fit and top-center calculations, including negative display origins and short displays.
- Column readability and width bounds across 280–920-point reading regions.
- Hover, selection, invalid selection, emphasis settling and task cleanup.
- Native text wrapping and inline glyph-to-widget hit testing.
- Real native-link delegate activation, internal ScrollView scrolling to a linked card, selected-link Return activation and rejection of external URL actions.
- Native scrolling through long/linked reports.
- Twelve opening/back samples retaining the surface's top-center position in an offscreen fixture.

**The 80 Phase 1 Gemini checks passed**, including structured validation and isolated Keychain testing. The existing notification presentation suite and twelve-transition notch layout regression passed. The existing Today widget renderer passed slot allocation, all three sizes and four dashboard compositions; the single- and three-slot outputs were visually inspected.

Nine page layouts were rendered offscreen: wide, medium, narrow, short display, long report, long title, empty report, no widgets and multiple paragraphs. Each was visually inspected, along with a linked-card highlight and opening/back motion samples. This review caught and corrected a sharp-edged sun glow, black gaps under short content, excessive hero height on short displays and transition text overlap/layout displacement.

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-today-checks.sh
```

The DEBUG-only Xcode preview gallery in `TodayPageView.swift` switches between synthetic scenarios without accounts or permissions. The normal Release page contains only the controlled standard design preview.

## Saved previews and limits

[Wide page](/Users/matthew/Documents/Coding/BoringII/dist/today-phase2/wide.png) · [Narrow page](/Users/matthew/Documents/Coding/BoringII/dist/today-phase2/narrow.png) · [Linked-card highlight](/Users/matthew/Documents/Coding/BoringII/dist/today-phase2/linked-card-highlight.png) · [Short display](/Users/matthew/Documents/Coding/BoringII/dist/today-phase2/short-display.png)

Additional generated layouts and motion samples are in `/tmp/notchloom-today-phase2-review/`.

Screenshots and native interaction checks used offscreen test windows, without activating windows or moving the user's pointer. They establish renderer/layout behavior and the tested interactions, not physical trackpad feel on the active desktop. A live desktop click-through, physical multi-display transition, VoiceOver session and outside-click focus behavior were not manually exercised. These should not be described as live-verified.

No real Today report was generated, no personal sources were connected, and no insight was scheduled. Those remain later-phase work. A future renderer caller should continue to supply a validated report plus a trusted native registry, rather than bypass validation or turn generated strings into actions.
