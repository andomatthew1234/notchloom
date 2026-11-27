# Notchloom Today — Phase 1 implementation

Implemented 20 November 2026. Notchloom 2.8.7, build 307.

## Delivered

Settings → Intelligence → Models now includes a functional Gemini API configuration alongside the existing Apple Intelligence Shortcut and ChatGPT API's Coming Soon card. Selecting a chat provider is explicit and starts a fresh conversation so previous chat history is not silently forwarded to another provider. Configuring Gemini or choosing a Today model does not change the general Intelligence provider preference.

The existing Today dashboard widget was not changed. No weather, calendar, notification history, personal-data briefing, linked-widget rendering or scheduling was added.

## Files

New application files in `boringNotch/Intelligence/`:

| File | Responsibility |
| --- | --- |
| `GeminiCredentialStore.swift` | Injectable credential protocol and macOS Keychain implementation |
| `GeminiClient.swift` | Native URLSession transport, model discovery, generation, retries, cancellation, deduplication and usage |
| `TodayReport.swift` | Version 1 Codable report, JSON Schema, trusted-reference context and strict validation |
| `GeminiModelStore.swift` | Connection workflow, independent persisted model choices and explicit Today generation entry point |
| `GeminiSettingsView.swift` | Secure setup, model search/details, tests, disconnect confirmation and DEBUG-only playground |

Updated existing Intelligence files `AIProvider.swift`, `IntelligenceCoordinator.swift` and `IntelligenceViews.swift` to route Gemini requests through the existing provider interface and display the selected provider. Apple's Shortcut execution and connection test remain intact. Updated `boringNotch.xcodeproj/project.pbxproj` for the new source files and version.

Added `tests/GeminiPhaseOneTests.swift`, `tests/GeminiLiveConnectionTest.swift`, `tests/RenderGeminiSettings.swift`, `tests/run-gemini-checks.sh` and this report. Other preexisting working-tree changes were retained.

## API and credentials

`GeminiClient` is an actor with an injectable Sendable transport and credential store. It uses Google's documented `GET /v1beta/models` with pagination and `POST /v1beta/models/{id}:generateContent`. Structured requests use `generationConfig.responseMimeType` and `responseJsonSchema`. See Google's [model API](https://ai.google.dev/api/models) and [generation API](https://ai.google.dev/api/generate-content).

Keys are sent through the `x-goog-api-key` header, never URL query parameters. The production transport uses an ephemeral URLSession, disables caches/cookies and refuses redirects. Raw provider error bodies and arbitrary system error descriptions are never displayed or copied. Diagnostics contain only the model ID, elapsed time and optional token counts.

The generic-password Keychain item uses service `Notchloom.Gemini`, account `api-key`, non-synchronizing storage and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Save updates an existing item before adding one; missing-item deletion succeeds. Keychain failures produce a useful status without exposing the value. The SecureField is cleared after successful save and on leaving the panel. Disconnect requires confirmation and removes the credential, connection verification and response state while retaining model preferences.

There is no startup model discovery, generation or background polling. Credential presence is checked when the Gemini settings panel appears. Requests need an explicit user action or a future caller's explicitly supplied prompt. No personal sources are read by this infrastructure.

## Discovery and model selection

Models are discovered from the user's key, filtered by `generateContent`, validated by resource ID, deduplicated and shown with supplied descriptions, supported operations and token limits. No production model names are hardcoded. The listing API alone is not treated as proof that a model supports the Today schema; a real structured request must pass local validation.

Preferences are separate:

- General provider: existing `intelligence.provider`.
- Gemini chat model: `intelligence.gemini.model`.
- Today model: `today.gemini.model`.

A missing saved model stays selected as unavailable until the user explicitly chooses another. There is no silent fallback. No chat model is automatically selected from the list. The first model that passes both connection tests becomes Today's initial default only if no Today model preference exists. Today can then be changed and tested independently.

Connection testing loads the credential, refreshes discovery, confirms the exact selected model, requests a short synthetic text response, then independently requests and validates a version 1 Today report. Text success with failed structured validation permits chat but not Today. Connected and structured verification are intentionally session-local; after restarting, the user refreshes and tests again. A saved key alone never marks a connection successful.

**Live models discovered during implementation: none. Selected live default: none. No real Gemini credential was supplied or used.** Synthetic model IDs in tests and layout fixtures are not advertised as Google models.

## Structured report and Phase 2 interface

Version 1 contains required `version`, `title`, `blocks`, `widgets` and `scheduledInsights` fields. Blocks support heading, paragraph, highlight and informationCard. Parts contain text or a widget reference. Widget kinds include information, calendarEvent, weather and notificationSummary. Scheduled-insight proposals contain a stable ID, timestamp, title, body, source reference and quiet/standard delivery preference; they are data only.

The validator rejects unknown properties, unknown enum cases, missing/malformed values, unsupported versions, invalid identifiers, duplicate IDs across report entities, invalid calendar dates/timestamps, unverified source/widget references and excessive content. Limits: 128 KB response JSON, 120-character titles, 24 blocks, 24 parts per block, 12 widgets, 12 insight proposals, 4,000 characters per text part, 2,000 per insight body and 32,000 characters of total report content. References must match the explicit `TodayValidationContext`; inline references must also point to a declared report widget. No commands, URLs, executable code or styling language are supported.

Phase 2 should call `GeminiModelStore.generateToday(prompt:context:)` after its own consent/setup flow. It requires the separately configured, connected, structured-verified Gemini model and returns `ValidatedTodayReport`. It never calls Apple Intelligence. Only the validator can construct the validated wrapper. Future renderers should accept this wrapper and resolve references against their own trusted registry. A later schema extension should deliberately version both decoding and validation.

## Reliability and usage

The client supports cancellation, a configurable request timeout (45 seconds by default), two retries by default with a hard cap of three retries, bounded exponential backoff and numeric/HTTP-date Retry-After. Delays over 60 seconds return a rate-limit/server error instead of retrying early. Invalid credentials, missing models, unsupported requests, network failures, timeouts, safety blocks, empty text, malformed JSON and incomplete outputs have distinct safe messages.

Requests are limited to 128 KB of prompt text and streamed responses to 2 MB; oversized streams are canceled. Model discovery is bounded to 20 pages. Identical concurrent generation requests share an in-memory SHA-256 fingerprint and one Task; canceling a shared request cancels all its identical callers. Completion removes the fingerprint. Repeated settings clicks are also guarded. Replacing/disconnecting configuration prevents stale chat responses from being published; disconnecting during generation returns a recoverable setup error rather than leaving chat on Thinking.

Each successful generation returns selected model, measured elapsed time and optional input/output/total/thinking/cache token metadata. Settings shows the last request. Missing counts remain unknown. No cost estimate, account balance or billing claim is displayed.

## Verification results

- **80 new automated checks passed.** Mock responses cover discovery/pagination, filtering, unavailable models, separate preference persistence, successful text/schema generation, usage, missing/invalid credentials, Keychain errors, invalid reports and references, timestamps/limits, safety/empty/truncated responses, network timeouts, Retry-After/backoff/bounds, cancellation, duplicate requests, disconnect during chat, sanitized diagnostics and no idle requests.
- **Real isolated Keychain roundtrip passed:** initial missing item, save/load, replacement and deletion. The test uses a unique synthetic service and never reads the app's credential.
- **Signed Release and Debug builds passed.** The playground compiles only under DEBUG. Existing unrelated media/concurrency/deprecation warnings remain.
- **Existing notification reader checks passed** (9 cases), notification presentation checks passed, and the layout regression test passed all 12 open/close transitions.
- **Apple backend check passed:** the configured `Notchloom Intelligence` Shortcut returned a real nonempty response to a synthetic prompt. This verifies the existing Shortcut backend, not a live click through the notch editor.
- **Settings rendered and visually inspected:** actual native Gemini Settings view at 610-point width, empty and selected synthetic-model states. Review PNGs are in `/tmp/notchloom-gemini-review/`. These images contain no real key and make no live model-discovery claim.
- **Desktop interaction unverified:** computer-use inspection returned no accessible app windows, so a live Settings click-through could not be completed.
- **Existing conversion suite incomplete:** it timed out after 75 seconds after reporting its advertised-image checks; its isolated test process group was stopped. No converter code was changed in this phase and no overall converter-suite success is claimed.
- **Live Gemini unverified:** no key was supplied; no successful real Google request or real model list is claimed.

Run the isolated suite with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer zsh tests/run-gemini-checks.sh`. The optional live runner runs only with `--live` plus explicitly configured `NOTCHLOOM_GEMINI_TEST_KEY` and `NOTCHLOOM_GEMINI_TEST_MODEL`; it never searches ordinary environment variables or the app's Keychain for a credential. Never put a real key in source control or this report.

For the normal app workflow: open Settings → Intelligence → Models, save a key from [Google's setup page](https://ai.google.dev/gemini-api/docs/api-key), refresh models, choose a chat model and press Test connection. Choose/test a separate Today model if desired. The Today page and future data-source consent remain later-phase work.
