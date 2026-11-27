# Today Phase 3 — local context and privacy

Implemented 20 November 2026. Notchloom 2.8.9 (309).

## What is implemented

Today now has an explicit five-step setup: introduction, source choices, individual permissions, privacy explanation and connection results. All optional sources start off. Continuing with every optional source declined is supported. Setup drafts do not enable collectors. City search is an explicit action after weather-provider consent. The existing sky design, notch expansion, structured renderer and linked cards are retained.

Settings → Today → Data sources provides the master collection switch, individual source switches, manual city search or approximate device location, temperature units, weather cache interval, calendar selection, bounded tomorrow lookahead, optional event locations and meeting URLs, permission status, System Settings links, refresh, a local context inspector and cache clearing. Denied permissions are not requested again automatically.

The local page displays deterministic source facts and availability labels. It generates no AI summary. Before setup, the existing fictional preview remains explicitly labelled; it is never silently substituted for unavailable real data after collection is enabled. The Dashboard date uses the real selected local date after setup. Refresh, inspect and source-settings actions are available within Today.

## Sources and permissions

- **Date and time:** Foundation date, calendar, time zone, UTC offset, locale and time-of-day period. ISO 8601 machine values. No network or permission.
- **Weather:** real Open-Meteo current/model forecasts, apparent temperature, high/low, current and daily precipitation probabilities when supplied, up to 12 near-term forecast entries, provider timestamps and attribution. Missing values stay missing. This adapter does not provide weather alerts; `alerts: null` means unsupported, not an all-clear.
- **Location:** manual city selection avoids an OS grant. Device mode requests a single Core Location fix, only after the user chooses it and presses Allow. Three-kilometre desired accuracy; coordinates rounded to two decimals before storage or transmission; no continuous tracking. A fix times out after 15 seconds and responds to cancellation. No full-precision CLLocation is retained in context.
- **Calendar:** a dedicated minimal EventKit reader, separate from Notchloom's existing calendar/reminder feature. Read operations only; no event edits, reminder reads, notes or automatic meeting links. Up to 40 upcoming occurrences from today through a configurable 0–12 hours tomorrow, default six hours. EventKit expands recurrences; occurrence IDs include the start instant. All-day, overlapping and recurring events are retained; ended, cancelled and out-of-window events are excluded. Optional locations and event URLs start off.
- **Notifications:** opt-in reuse of the existing public Accessibility visible-banner reader through its existing XPC helper. Only newly observed real banners after opt-in are eligible. Local preview notifications do not enter Today. No private APIs, system-history database or screenshots are added. Reader permission/capability failures produce an honest unavailable or permission-needed state.

On macOS 14, EventKit provides a Full Calendar Access grant rather than a read-only grant. Today requests that OS grant only from its explicit button and uses it exclusively for reads. Usage descriptions and the location entitlement are included. A Settings link handles denied/restricted grants. Outside-click dismissal pauses while Today awaits a native permission dialog; click events are still passed through normally.

## Weather provider decision

Apple WeatherKit was investigated. It requires Apple Developer Program membership, app-identifier WeatherKit configuration and the entitlement; this target's current signing setup has no WeatherKit capability. No paid service, developer-portal setting or provisioning was silently changed. See [Apple WeatherKit](https://developer.apple.com/weatherkit/) and [the entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit).

The implemented alternative is Open-Meteo's documented keyless endpoint, with visible attribution and an explicit provider-consent switch. Its free endpoint is for personal/noncommercial use. **Commercial distribution must resolve the provider licence/service arrangement or adopt an appropriately provisioned WeatherKit adapter.** See [forecast API documentation](https://open-meteo.com/en/docs), [city search documentation](https://open-meteo.com/en/docs/geocoding-api) and [terms](https://open-meteo.com/en/terms).

Only an explicit city query or rounded coordinates go to this provider. The dedicated weather transport accepts HTTPS requests to the two Open-Meteo hosts only, rejects redirects, limits responses to 512 KB and uses ephemeral sessions without persistent cache or cookies. Errors do not log response bodies or location-bearing URLs. No key or Homebrew/tool installation is needed for weather.

## Snapshot, caching and lifecycle

`TodayContextSnapshot` version 1 is Codable and includes generation time, time zone, the exact authorized source set, `externalTransmissionAllowed: false`, optional date/time and weather, bounded event/banner arrays and a status object for every source. Status is independently disabled, permission required, loading, ready, stale, unavailable or failed. Generation time/time zone remain snapshot metadata even if the separate date/time source is off.

Source payloads are validated independently; a bad or missing collector does not prevent other sources from publishing. Partial results appear while slower sources finish. The final snapshot is validated again. Native widget registrations and the existing report validator constrain linked content. The context engine has no UI or Gemini dependency.

- Weather is cached in memory for the configured 15–120 minutes, default 30. A new local forecast day also expires the fresh cache. Explicit refresh bypasses freshness; provider errors have a short retry cooldown. Failed refreshes may use clearly marked cached weather up to six hours old. Changing the city, revoking device-location access, disabling weather or clearing data removes the relevant cache.
- Events and assembled snapshots are not persisted. Closing the last Today/settings presentation releases its snapshot and calendar names. Inactive-app permission changes are rechecked before publishing. An older collection cannot republish data after an opt-out, revocation or configuration change.
- Notifications are capped at 20 items for 30 minutes, with app names limited to 64 characters, titles to 120 and bodies to 240. Original content-based IDs are replaced by hashes; timestamps mean **observed at**, not original delivery time. One-shot expiry tasks remove retained excerpts; no new polling loop is introduced. Disabling the source or losing banner-reader capability clears them. Capture and consent revision checks reject late arrivals from a previous opt-in period.
- Preferences alone are saved: source choices, selected calendar IDs, bounded refresh preferences and a selected coarse city. Clear cached data preserves these choices. Calendar/notification content and snapshots do not enter preferences, diagnostics or a history file.
- Collection refreshes on user request, stale/open presentation, relevant permission or EventKit changes, wake, time-zone/locale/clock changes and midnight. Refreshes coalesce; weather redraws do not issue requests. A one-shot midnight timer is scoped to presentation. Closing the page or leaving the app cancels in-flight presentation collection. No AI request, scheduled briefing or context history is implemented.

## Changed files

New files in `boringNotch/Intelligence/`:

- `TodayContextModels.swift` — policies, source DTOs, snapshot and validator.
- `TodayDataSources.swift` — source protocols, date/time, minimal EventKit, calendar occurrence selection, one-shot Core Location.
- `TodayWeatherSource.swift` — restricted weather transport, Open-Meteo forecast/city adapter, memory cache and WMO condition display.
- `TodayNotificationSource.swift` — bounded opt-in observed-banner buffer and expiry.
- `TodayContextService.swift` — independent concurrent collection, cancellation, validation and partial snapshots.
- `TodayContextController.swift` — preferences, consent revisions, UI state, permission/lifecycle handling.
- `TodayAppDataBridge.swift` — app composition, existing real-banner stream and event-driven lifecycle subscriptions.
- `TodayContextPresentation.swift` — deterministic facts-to-existing-renderer adapter, units and real Dashboard date.
- `TodayDataSettingsView.swift` — source controls, native aligned switches and permission routes.
- `TodaySetupView.swift` — five-step opt-in flow.
- `TodayDataPageHost.swift` — existing-notch integration and local inspector.

Modified integration files: `TodayPresentation.swift`, `TodayPageView.swift`, `TodayNotchInteraction.swift`, `components/Notch/TodayWidget.swift`, `components/Notch/NotchToolsView.swift`, `components/Settings/SettingsView.swift`, `components/Settings/SettingsWindowController.swift`, `NotificationMirror.swift` (real-arrival publisher only for this phase), `Info.plist`, app entitlements and the Xcode project/version.

New checks: `tests/TodayContextTests.swift`, `tests/run-today-context-checks.sh`, `tests/TodayWeatherLiveTest.swift`. This report is `docs/today-phase-three.md`.

A separately installed API-key hotfix is also retained: `GeminiCredentialStore.swift`, `GeminiModelStore.swift`, `GeminiClient.swift` and Gemini tests. Credentials are opaque, surrounding whitespace is trimmed and arbitrary punctuation/prefix/length assumptions no longer reject keys locally. Empty/control-containing or exceptionally large entries are still rejected. Google validates the actual credential on a connection test. No actual user key was read, printed or submitted during this work.

## Verification

- **76 new context checks passed**, using synthetic/injected sources: DST gaps and repeated hours, locale/time-zone changes, midnight, bounded event windows, weather decoding/failure/cache/forced refresh, location and calendar denials, all-day and recurring occurrences, sorting/deduplication, selected calendars, source opt-outs, late capture epochs, excerpt limits/expiry, preference-only persistence, permission revocation, closed-page callbacks, concurrent refreshes, independent source failure/missing source handling, JSON round trips and validation. A direct attempted Google URL is rejected by the restricted transport before network work.
- **83 Gemini checks passed**, all requests mocked, isolated Keychain round trip; no live Gemini credential used.
- **171 existing Today presentation checks passed**, including wrapping, trusted links, scrolling, nine layouts and offscreen opening/back animation samples.
- Existing notification reader, presentation, swipe and notch-layout regression checks passed; 12 open/close transitions retain the player identity and sizing.
- Offscreen own-window renders reviewed for all five setup steps, weather permission controls, source settings, context inspector and real-data-shaped cards at wide/narrow widths. No user desktop screenshots, pointer movements or window activation were used for this review.
- **Live Open-Meteo forecast and city search passed** using only the public Berlin documentation coordinates. Current temperature, high/low and near-term entries decoded successfully. This did not use the user's location, calendar, preferences or Gemini.
- Debug and signed Release builds passed. Version 2.8.9 (309) is installed at `/Applications/Notchloom.app`; its signature was verified and the running process was checked. Existing unrelated Swift 6 migration warnings and the existing MediaRemoteAdapter deployment-version warning remain.

Useful commands:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-today-context-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-gemini-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-today-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-notification-checks.sh
```

## Manual setup and limits

Open Today → Set up Today, or Settings → Today → Data sources. Choose weather and confirm the provider if desired; search for a city or grant approximate location. Calendar needs the user's explicit native permission. Notifications additionally need the existing banner-mirroring feature and its Accessibility permission.

**Not live-verified:** the user's actual calendar contents/recurrence expansion, their native Calendar or Location grant/deny dialogs, changing those grants in System Settings, real sleep/wake and midnight on the physical machine, or cross-app notification arrivals into this new Today buffer. Automated tests mock those boundaries; they do not establish real OS permission success. The own-window visual tests do not prove every physical-notch gesture.

Notification coverage remains incomplete. Some apps, protected text, hidden/suppressed banners, missed transient UI or reader disconnections cannot supply content. No complete notification history is claimed. Existing notification infrastructure is reused without a new capture mechanism or higher-frequency polling.

No live Gemini briefing, Google context transmission, automatic AI refresh, scheduled Today Moments, AI reminders, history or additional cloud AI provider is part of this phase.
