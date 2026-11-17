# Notification presentation

Notifications use the existing top-aligned `BoringNotchSkyLightWindow` and the original animatable `NotchShape`. No additional window is created. `NotificationNotchSurface` wraps the ordinary notch layout and owns its black fill and clipping shape in both modes. Notification content has no background, border, shadow, or detached stem.

The surface is 360 points wide for short messages and 390 for longer ones, clamped to the available display width. Its content sits below the physical camera area. On displays without a notch, the same silhouette is attached to the top edge without the camera inset. Body text is limited to two lines.

## Sequence and interaction

`NotificationPresentation` owns four phases: idle, expanding, displaying, and collapsing. A 0.42-second spring expands the existing surface; content begins its fade 0.10 seconds later. Dismissal fades content for 0.14 seconds before a critically damped 0.46-second contraction. Reduce Motion uses brief easing and omits the content scale/offset.

The bounded FIFO queue presents one item at a time. An open notch, a system HUD, a battery expansion, or fullscreen hiding defers presentation. The original close animation is allowed to settle before a queued alert begins. The original music view stays mounted and is restored after contraction.

Hovering pauses the reading timeout across all displayed notches. Clicking outside dismisses the notch presentation without consuming the click. The existing nonactivating panel remains unable to become key or main; incoming alerts never activate an app. Clicking a recognized source opens that app. The reader does not expose a notification deep link, reply, stop, or snooze action; those remain on the original macOS notification. Dismissing the notch presentation does not dismiss the system notification.

The existing visible-banner capture and preferences remain in place. This redesign does not bypass Focus, hidden previews, or notification permissions. Local focus-timer completion still works when mirroring is disabled.

## Verification

Run `tests/run-notification-checks.sh` on macOS. It compiles the production presentation code directly and checks:

- Expansion/content ordering and fade/contraction ordering.
- Hover pausing, bounded FIFO delivery, interrupted alerts, and cancellation.
- Deferral during other notch interactions and multi-display coordination.
- Preference handling for mirrored versus local notifications.
- Geometry for 320–3840 point screen widths and 0–38 point camera insets.

The runner also renders the production SwiftUI surface at 1× and 2× into `dist/notification-redesign` for short, long, and no-notch layouts. These are component renders, not desktop captures.

The release build and signature were checked. Live previews on the built-in display showed a continuous black silhouette, compact short content, collapse, and return to the music live activity. Expanded music controls and the Tools page were also visually checked after fixing an initial measurement regression. Other display sizes and scales were checked through geometry and component renders; no external monitor was physically connected for this check. Actual iMessage and Clock banner ingestion remains a separate integration check and is not established by preview tests. Refresh-rate performance was not instrumented.

API references: [SwiftUI spring animations](https://developer.apple.com/documentation/SwiftUI/Animation) and [AppKit event monitoring](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html).
