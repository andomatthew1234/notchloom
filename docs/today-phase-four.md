# Today Phase 4 — live Gemini briefing implementation

20 November 2026 · Notchloom 2.8.10 (310)

The signed Release build is installed at `/Applications/Notchloom.app`. Its signature and running process were verified.

The live generation path is implemented and tested with injected Gemini and context providers. **No live Gemini request was made during implementation:** explicit test credentials, model and test consent were not configured. The user's stored credential and personal sources were not used for integration testing. Actual provider success remains a manual verification boundary.

## User workflow

Open Today from Overview. If local collection has not been set up, Today offers the existing individual-source setup. If Gemini needs configuration, Today links directly to Settings → Intelligence → Models. Choose a Today model. Connection tests are optional; every generated report is validated on its normal request.

Before the first personal briefing, Today explains Google processing, selected sources, cost, local caching and revocation. It provides source controls through Data sources and an inspector for the exact minimized outgoing JSON. The user explicitly presses **Allow selected sources & prepare Today**. Having an API key alone does not authorize personal-data transmission.

After that consent, opening Today reuses a suitable briefing or collects a current authorized snapshot and requests a new one. Refresh explicitly renews the context and report. Navigation and Cancel remain available. A small gradient status strip shows collection/generation; it never invents token streaming or percentages. A previous authorized report remains visible during refresh and after errors, with an earlier-briefing label when appropriate. New validated reports use the existing title, paragraph, linked-card and scroll animations; Reduce Motion is respected.

Before local setup, the Dashboard tile uses neutral content instead of a fictional sample date. The actual app no longer routes Today to a fictional AI report. The explicit developer preview/gallery remains available for design tests.

## Architecture

- `TodayBriefingService` is an actor receiving injected context, Gemini and cache interfaces. It owns context collection, consent/authorization checks, prompt preparation, one generation request, validation, persistence and concurrent-call deduplication.
- `TodayBriefingCoordinator` owns observable UI state and durable explicit consent, refresh/cancel/open/close behavior, local outgoing previews, stale-state presentation and cache/consent controls.
- `TodayPromptBuilder` minimizes the Phase 3 snapshot, constructs the trusted native reference registry, supplies separate system instructions, computes stable context/scope hashes and verifies generated reference bindings.
- `TodayBriefingCache` stores one encrypted validated report. It is not a context or history store.
- `TodayLiveContextAccess` reuses Phase 3 collectors and OS permission checks. The underlying context engine remains independent of AI and UI.
- `TodayLiveGeminiAccess` reuses the selected Gemini model and Phase 1 client. SwiftUI constructs no HTTP requests.
- `TodayGenerationState` distinguishes setup, missing model configuration, consent, empty context, collection, generation, ready and failure states.

The existing `TodayReport`, JSON Schema, strict validator, renderer, native linked cards and notch positioning/animation architecture are retained. There is no disconnected floating briefing window.

## Outgoing data and grounding

The prompt is bounded to 32 KB and includes only available information from explicitly selected sources:

- Local date/time/time zone/locale when enabled.
- City-level weather and up to six near-term entries, with provider timestamps, unavailable alerts and stale-state information kept explicit.
- Up to six upcoming calendar events with title, times, all-day flag, calendar display name and an optional location when separately enabled.
- Up to three short legitimately observed banner excerpts, with capture timestamps and incomplete-coverage disclosure.
- Exact permitted widget IDs, types and source references.

Native calendar identifiers, calendar notes, reminders, meeting URLs, precise coordinates, full notification histories and unrelated personal information are not sent to Gemini. The outgoing inspector shows the minimized JSON payload, separately from the broader local source snapshot. Preparing that preview makes no Gemini request.

Calendar titles, names, locations and notification text are encoded as untrusted JSON facts. Separate system instructions explicitly deny authority to embedded instructions and forbid invented facts, tools, code, URLs, custom views and unsupported actions. No tool execution is configured. The model is asked for concise natural prose and to omit unsupported subjects rather than fabricate interesting content.

Responses use the existing version 1 JSON Schema and pass the existing strict decoder/validator. Additional grounding requires each declared widget to match its registered ID **and exact source binding**. An inline source must have its corresponding declared native card. Unknown IDs, swapped sources, unsupported blocks/actions/properties, arbitrary URL-bearing prose, blank prose and excessive prose are rejected. No invalid response is silently shown as successful or repaired with another paid request.

The model selects relevant cards; Notchloom supplies their actual values and views from trusted collected data. Inline clicks retain Phase 2 highlighting and scrolling. The report footer identifies Gemini, generation time, possible AI mistakes and weather attribution.

**Limit:** reference validation constrains links and actions; it does not mathematically prove the truth of every natural-language sentence or eliminate every model hallucination. The prompt restricts prose to supplied facts and the UI asks users to check native source details.

## Consent and permission changes

Consent is a separate versioned record, bound to the selected source scope. Adding/removing a source, broadening calendar fields/selection or changing the selected location requires a matching consent scope. Presentation units and weather refresh intervals do not broaden Google consent.

Settings → Today → Data sources includes the Gemini consent state, Revoke Gemini consent, Clear cached briefings, source controls and the context inspector. Clearing source context also invalidates derived briefings. Because prose may combine several sources, source-specific invalidation conservatively purges the entire mixed report and its cards rather than guessing which sentences to retain.

Current OS permissions are checked before restoring a report, before sending, after generation and before publication. Source/permission revisions cancel stale work; an old save cannot resurrect a cleared cache. Closing the last Today presentation releases displayed prose and reloads only after fresh permission checks next time, preventing a stale private-content flash. Multiple Today presentations share one generation; closing one does not cancel another.

Ordinary new banners mark an existing briefing stale without continually canceling a running request. Calendar changes, scope changes and expired/revoked sources invalidate in-flight context as appropriate. Sleep/deactivation cancels preparation. None of these events automatically starts an AI background briefing.

The global Gemini status panel keeps request usage metadata without retaining a second copy of personal Today prose. Outgoing previews are memory-only, cleared on closure/privacy changes and expired at the same retention deadline even when generation failed and no report was cached. Clearing local data cannot retract information already processed by Google.

## Protected cache and freshness

One file lives under Application Support/Notchloom/Today. AES-GCM encrypts the report, selected native card display details and metadata. A separate random 256-bit key uses local, non-synchronizing, device-only Keychain storage. The folder is mode 0700; staged/final files are mode 0600, atomically replaced and excluded from backup.

The cache contains report/schema version, generation time, model, a credential identity digest, context and scope hashes, permission-access hash, source freshness metadata, local day/time zone, validity/retention deadlines, usage metadata and validated report content. It contains **no raw source snapshot or complete prompt**. Only selected native display cards are retained; proposals retain verified source IDs without persisting unrelated source contents.

A 13-byte version/expiry header is authenticated with the ciphertext. Expired encrypted files can be removed at startup without reading credentials or decrypting personal content. While the app runs, one-shot retention tasks expire displayed data. When the app is stopped, expired ciphertext is rejected and removed on the next startup/load; it is never restored as valid content. Clear invalidates pending writes, deletes the file and removes its encryption key.

Suitability uses model, credential identity, scope, current access, semantic context hash, local day/time zone, meaningful source changes and freshness deadlines—not the date alone. Ordinary seconds do not invalidate an otherwise identical date-only briefing. New days, upcoming event starts and fresh-weather deadlines can mark a report stale. A newly written report that truthfully describes stale weather can be reused briefly instead of regenerating on every open while the provider is down.

Reports are retained at most 24 hours. Reports generated from observed-banner context expire by the earliest included observation's 30-minute limit, even if no banner card was selected. No briefing history is created. A failed refresh preserves the prior report only while it remains authorized and inside its privacy retention deadline.

## Cost and reliability

Each new briefing action makes at most one structured `generateContent` request using the explicitly selected model. Today opts out of the generic client's automatic retries, uses a 4096-token output cap and never silently substitutes models or makes paid repair calls. Network failures, refusals, malformed JSON, invalid credentials/models, rate limits, incomplete responses and cancellation use safe error messages without provider bodies, keys or private prompt logs.

Concurrent calls share a generation; duplicate Refresh actions are disabled. Rapid close/reopen after cancellation has a short automatic-request guard; explicit Refresh can retry. The provider may still bill a request already accepted before cancellation. Usage metadata is retained when supplied, labelled as usage rather than a bill.

A successful structured model test may be restored for seven days, bound to the same exact model and credential digest. This avoids making users perform two synthetic tests on every app restart. Restoring a test does not perform a network request or claim current provider availability. Permanent credential/model/schema errors invalidate the remembered verification; Google availability can change and the user can explicitly refresh/test models again.

## Files created

Under `boringNotch/Intelligence/`:

- `TodayBriefingModels.swift`
- `TodayPromptBuilder.swift`
- `TodayBriefingCache.swift`
- `TodayBriefingService.swift`
- `TodayBriefingCoordinator.swift`
- `TodayBriefingAdapters.swift`
- `TodayBriefingPage.swift`

Tests/support: `tests/TodayBriefingTests.swift`, `tests/TodayBriefingLiveTest.swift`, `tests/run-today-briefing-checks.sh`, `tests/today-test-sources.sh`.

## Files modified for this phase

- `GeminiClient.swift`: separate system instructions, bounded output configuration and per-call retry control, included in request deduplication identity.
- `GeminiModelStore.swift`: verified Today request adapter, metadata-only global response state, key-bound verification restoration and permanent-error invalidation.
- `TodayContextController.swift`: reusable briefing collection/authorization checks, change revisions and privacy expiry.
- `TodayAppDataBridge.swift`: app composition and existing lifecycle events.
- `TodayDataPageHost.swift`, `TodayDataSettingsView.swift`, `TodaySetupView.swift`: real briefing integration, outgoing inspector, source/consent controls and current privacy copy.
- `TodayPresentation.swift`, `TodayPageView.swift`: Codable native display descriptors and briefing section label.
- `components/Notch/NotchToolsView.swift`, `TodayWidget.swift`: existing-notch host, model settings route and neutral pre-setup tile.
- `components/Settings/SettingsView.swift`, `SettingsWindowController.swift`: exact Models/Data sources routing.
- Xcode project/version, README, Gemini tests and shared context-test build script.

Earlier unrelated working-tree changes were preserved. No commit, push, public release, notarization or installer publication was performed.

## Verification

- **105 Today briefing checks passed:** first generation, reuse, manual refresh, deduplication, context minimization, injected instructions as data, no-consent/no-context/no-config paths, missing/invalid model handling, refusals/network/timeouts/rate limits, strict reports, invented/swapped references, prose limits, stale weather, changed events, source/permission invalidation, cancellation, late saves, authenticated encrypted round trips, file permissions, corruption, startup expiry, failure fallback, consent revocation, outgoing-preview expiry, multi-presentation behavior and rapid reopening.
- **86 Gemini checks passed:** existing client/Keychain/configuration behavior plus key-bound verification restoration and metadata-only status storage. All network calls mocked; isolated test Keychain items only.
- **76 context checks passed.**
- **171 existing Today presentation checks passed**, including wrapping, trusted links, scrolling, responsive geometry and offscreen motion samples.
- Existing notification reader/presentation/gesture and notch-layout regressions passed, including 12 repeated open/close transitions retaining player identity.
- Offscreen own-window renders reviewed for consent, initial generation, ready report, failed refresh, consent revocation, native linked weather and refresh retaining a cached report. No user desktop screenshots, app activation or pointer movement was used for visual review.
- Debug and signed Release builds passed. Existing unrelated warnings about Swift 6 migration and MediaRemoteAdapter's deployment version remain.
- **Live Gemini test: skipped.** The explicit test key/model/consent were absent. No saved application credential was inspected or submitted. No live Gemini success is claimed.

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-today-briefing-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-gemini-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-today-context-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-today-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-notification-checks.sh
```

The optional `run-today-briefing-checks.sh --live` path requires deliberately configured `NOTCHLOOM_GEMINI_TEST_KEY`, `NOTCHLOOM_GEMINI_TEST_MODEL` and `NOTCHLOOM_TODAY_LIVE_CONSENT=yes`. It makes at most one generation request using public UTC date/time, never the app's stored key or personal calendar/weather/banner context. It validates the real returned report. Do not put a real key in tracked files or shell history.

## Manual verification and limitations

In the installed app, save your key and select the Today model, open Today, inspect outgoing information and choose whether to allow generation. The first real response, prose quality, current model compatibility, actual personal Calendar/Location grants, sleep/wake on the physical machine and full physical-notch interactions remain manual checks. Mock success is not live API success or a frame-rate measurement.

Notification availability remains limited to what the existing public Accessibility banner reader can observe. No complete notification history or new capture mechanism is added. Weather provider/permission limitations from Phase 3 remain. A stale cached briefing is a prior snapshot, not continuously live source truth; Refresh updates it.

Gemini API compatibility was checked against Google's [generation reference](https://aistudio.google.com/api-reference/generate-content) and [structured-output guide](https://aistudio.google.com/docs/structured-output). The existing supported `generateContent` JSON-schema path is reused, rather than introducing a second API stack.

## Phase 5 boundary

Scheduled insight proposals are decoded, source/timestamp validated and preserved in the encrypted report where valid. They are not displayed as delivered messages, registered with timers, posted as notifications or used to animate a bell. There is no scheduled Today Moment, AI reminder delivery, history or Phase 6 work.

Phase 5 needs an explicit delivery/permission policy, current-source revalidation, expiry/deduplication, a scheduling lifecycle and user controls before any proposal can become an actual notification. A validated proposal alone does not authorize delivery.

## Follow-up: location handoff and optional tests

Version 2.8.11 (311): signed Release build installed. 47 handoff checks, 89 Gemini checks, 105 briefing checks and 76 context checks passed. Native Location grant/deny was mocked, not exercised on the user’s real permissions.

The setup now contracts into a compact, click-through “Select Allow to continue” hint before requesting native Location access. The setup remains mounted so its draft and step survive; after either Allow or denial it expands back. Keyboard focus is released while the real macOS alert is active. The flow is driven by the request and animation completion, never by polling system windows. Native grant/deny remains a manual verification boundary.

Gemini connection tests are now optional for both Today and notch chat. A saved key and a selected model permit an ordinary request immediately; that request still validates provider errors and the structured report. Prior test results remain diagnostics and do not gate use. No preliminary paid test requests are sent automatically.

## Follow-up: real structured-report rejection

Version 2.8.12 (312) fixes a confirmed HTTP 400 schema-complexity rejection. The same selected Today model accepted the repaired schema (HTTP 200), and its synthetic report passed the strict local report validator. This diagnostic used a synthetic prompt only; no personal Today sources were transmitted. A second, more extensive synthetic pipeline diagnostic was stopped during its CLI-only credential lookup, before any request, so live native-reference grounding remains unverified.

The wire schema retains typed objects, required fields and allowed variants, while removing nested array bounds and identifier/string constraints that expand Google's decoding grammar. All existing size, identifier, source-reference and action restrictions remain mandatory in local validation. See Google's [schema complexity guidance](https://aistudio.google.com/docs/structured-output#simplifying-complex-schemas). The model was not changed, and connection tests remain optional.

Provider errors now distinguish an overly complex schema from explicitly unsupported structured output without displaying raw provider responses. Today displays the failure once and uses a clear failure heading.

Verification: 94 Gemini checks and 105 briefing checks passed, along with a signed Release build and signature validation. The real synthetic report check above is additional to those mocked suites; it does not establish personal-source permissions, live grounding or physical-notch interaction.

## Follow-up: Today presentation polish

Version 2.8.13 (313) replaces the oversized introduction banner with a restrained dark card, a date heading, a clear primary action and adaptive source tiles. Welcome, generation, initial failure and cached-report views share a compact toolbar with labeled accessible controls. Errors appear once, wrap naturally and remain separate from an earlier valid briefing. Completed briefings no longer carry an unnecessary ready banner. Consent disclosures remain before the allow action; generation, permissions, caching and model selection are unchanged.

Verification: 106 briefing checks and 171 presentation checks passed. Reviewed offscreen synthetic renders of initial failure, consent, progress, successful reports and failed refreshes, including narrow and short panels; the presentation suite also checks scrolling and opening/back motion. Signed Release build passed. No live provider requests or personal-source inspection were needed for this visual change. Physical-notch interaction remains a manual verification boundary.

## Follow-up: cohesive dark briefing design

Version 2.8.14 (314) extends the dark design to the report itself and the setup header. A smaller cyan/violet header replaces the large sky-and-paper composition. Briefing text and linked source cards use separate quiet surfaces, with brighter native inline links, restrained highlights and readable card accents. The header artwork is static and fades further on narrow layouts. Existing matched-geometry expansion, keyboard link activation and scrolling remain in place.

The welcome screen shows selected sources as small chips rather than four large selected/off tiles. Successful reports show the generation date and update time; cached reports still identify themselves as earlier briefings. Source choices, consent, credentials, API requests, validation and caching behavior are unchanged.

Verification: the 106 briefing and 171 presentation checks passed, including native wrapping, link activation, scroll-to-card behavior, nine report layouts and opening/back samples. Offscreen synthetic previews reviewed for wide/narrow reports, long content, initial failure and consent. Signed Release build passed. No live Google request or personal-data collection was performed for this design change; physical-notch interaction is not established by these checks.

## Follow-up: motion throughout Today

Version 2.8.15 (315) adds spring entrances, staggered briefing blocks and source chips, header-ring unfurling, responsive toolbar symbols, hover lifts and glows, button press/release feedback, source-card emphasis, loading halos and pulses, and animated setup steps with a progress track. The Dashboard Today tile also lifts on hover. Page, inspector, notice and report changes use short coordinated transitions; the existing top-anchored notch expansion remains in place.

Reduce Motion disables spatial effects, symbol effects and continuous loading artwork. A shared presentation flag also disables motion for deterministic previews. Entrances and interactions settle; the only repeating effects are visible loading indicators. Closing the corresponding view removes them. No display timer, background polling, network request or fabricated progress percentage was added.

Verification: 174 presentation checks include offscreen opening/back and loading/highlight sequences, plus pixel stability checks for the effective reduced-motion policy, disabled motion and idle state. The policy is injected locally because the native Accessibility preference is read-only; the user's system settings were not changed. Those checks caught and fixed an SF Symbol effect that otherwise finished its cycle after motion was disabled. The existing 106 briefing and 47 mocked location-handoff checks also passed. Synthetic UI renders only; live physical-notch interaction and device frame rate remain unmeasured.

## Follow-up: top alignment and content fitting

Version 2.8.16 (316) explicitly top-aligns the normal notch surface within its animation host. Today now reports the natural height of its scroll content, including its toolbar and any notice, and fits the visible surface to that height. Long content remains capped by the available screen height and scrolls. The shared chrome calculation accounts for the main tab header, its gap and bottom padding, removing the earlier unused vertical allowance. Setup, inspection and model-recovery layouts retain their full scrollable viewport. Header artwork also fits its actual bounds on short pages.

The transparent host remains large until the existing contraction completes, preserving the established clipping and click-through behavior. Height feedback is bounded and rounded; permission handoff suppresses resizing while the native prompt owns interaction. Source collection, consent and Gemini behavior are unchanged.

Verification: 130 briefing checks include five fitting regressions for consent, short reports, initial failures, failed refreshes and short displays with a left-side Dock. These verify natural-height reporting, top centering, exact chrome/content sizing, stable measurement and reclaimed empty space. Offscreen native panels use the same borderless/nonactivating/utility/HUD style as the app. The 174 presentation checks, 47 mocked location-handoff checks and notification reader/presentation/layout regression suite also passed. No live Gemini request, personal-source access or native permission prompt was used for verification. Full physical-notch interaction remains a separate manual check.
