# Power usage — 2.8.18

Overview → Power usage opens a compact page inside the existing notch window. Its height follows the content and remains bounded to the screen. Bottom navigation adapts to text-only labels when needed; Intelligence stays on the right. Transitions respect Reduce Motion.

## Telemetry and meaning

`PowerMonitorService` reads AppleSmartBattery through native IOKit on an actor, once per second only while a Power page is visible. Multiple display windows share one sampler. A five-sample average resets on source/direction/charging changes. Sleep cancels sampling and clears the displayed reading; wake requests a fresh sample. The last disappearing consumer removes workspace observers and stops polling. No shell, network, elevated access, SMC helper or background installation is used.

- **System only:** unavailable. No implemented sensor can reliably exclude both the built-in display and accessories. CPU package power is never substituted.
- **Battery draw / charging:** measured battery voltage × signed current, in watts. Positive current means charging; negative means discharge. uint32 and uint64 two's-complement currents are decoded. On external power without discharge the draw card says External power.
- **Runtime:** an estimate using remaining absolute mAh divided by the averaged discharge current. It is hidden unless the battery is discharging. Raw effective full-charge capacity is preferred over factory design capacity. Legacy absolute-capacity and nested BatteryData fields are supported; 0–100 percentage fields are never used as mAh.
- **Charger contract:** AdapterDetails.Watts, a negotiated rating, never a measurement of actual input.
- **Incoming:** PowerTelemetryData.SystemPowerIn / 1000, measured at the Mac when exposed. Missing or invalid readings stay unavailable.
- **Distribution:** SystemLoad and BatteryPower from the same telemetry tuple divided by actual SystemPowerIn. System load includes display/accessories. The sum must agree with measured input within a small tolerance; zero system load, stale charging readings during a hold, and a battery supplementing external power do not produce a bar. The matching battery sensor can differ from the instantaneous battery V × I reading because hardware updates them at different times.
- **Losses:** AdapterEfficiencyLoss is labelled a hardware estimate upstream of the Mac. It is not silently subtracted from the measured incoming power or counted twice. No inferred display/accessory deductions are made.
- **Charging milestones:** effective capacity and current give estimates for unreached 25/50/75/100% targets. The macOS time-to-full estimate is used for 100% when available, but never shortens the current-rate estimate. Without it, 100% is shown as a lower bound because taper above 80% can extend the time. Holds and near-zero current have no ETA. No synthetic taper curve is presented as measured.

The IORegistry fields are hardware-dependent and not a stable public telemetry contract. Capability checks fail closed. Independent field interpretation reference: [macwatt](https://github.com/ytomasch/macwatt). The implementation additionally verifies units/ranges, signed current, external-power state and power-budget consistency against local hardware.

## Validation

Run `tests/run-power-checks.sh --render`. Tests cover formulas, signed current encodings, worn/nested/legacy capacities, all dynamic states, missing and invalid data, inconsistent power budgets, charging milestones, taper fallback, formatting, rolling averages, shared sampling, sleep/wake, idle shutdown and service deallocation. Rendered native SwiftUI fixtures are written to `/tmp/notchloom-power-review`.

The development Mac was physically connected and charging. Native IOKit reads exposed voltage/current, nested effective capacity, a 96 W charger contract, input power, system load, battery-rail power and estimated adapter losses. Some samples exposed a zero system load; these were deliberately rejected for distribution. The excluding-display-and-accessories metric remains unavailable. Battery-only, full, hold and insufficient-supply states are automated fixtures, not claimed as physically tested charger states. Hardware readings have not been calibrated against an external power meter.

## Files

- `boringNotch/Power/PowerReading.swift`: validated telemetry values and calculations.
- `boringNotch/Power/PowerMonitorService.swift`: native reader and visibility-bound lifecycle.
- `boringNotch/Power/PowerUsageView.swift`: native cards, distribution, estimates and natural-height reporting.
- `boringNotch/components/Notch/NotchToolsView.swift`: Overview tab and adaptive navigation.
- `boringNotch/models/BoringViewModel.swift`: bounded expansion and delayed host contraction.
- `boringNotch/ContentView.swift`: main-tab changes and display resize handling.
- Xcode project: source membership and version 2.8.18 (318).
- `tests/PowerUsageTests.swift`, `tests/run-power-checks.sh`: calculations, lifecycle and rendering checks.

Final validation: 82 power/calculation/lifecycle/display-layout checks passed, including eight native state renders and five fitted layouts. Display bounds were exercised at 1024×640, 1280×800, 1470×956 and 1728×1117, including offset screens and Dock reservations. The existing 12-transition notch/notification identity regression also passed after mounting its fixtures in offscreen native windows; without a window, current macOS never registered its notification surface. No notification production code changed. Signed Release builds and strict code-signature verification passed. Live UI click-through was unavailable because the computer-use service returned `cgWindowNotFound`, including for Finder; live native telemetry and own-window top-edge metadata were checked separately.

## V2 — 2.8.19

The main page now uses an animated battery ring, a large state-dependent wattage reading and a native Swift Charts history. Diagnostic cards and explanatory paragraphs have been removed. Unsupported readings are omitted. The information button opens the measured voltages/currents, effective capacity, negotiated adapter ceiling, estimated losses and provenance/accuracy notes. Its popover keeps the notch open and releases that hold when dismissed or when the page disappears.

The existing reader, averaging, power-budget checks and charging calculations are preserved. Only negotiated adapter voltage/current were added to the parsed values. One existing visible-page sample now also feeds a bounded 60-second history (at most 61 timestamped points). It uses monotonic uptime, contains no backfilled data, resets on source/direction/series changes and preserves gaps. It clears on hide/sleep; there is no extra timer. Blue is Mac load, battery discharge or incoming power according to the visible legend; green is actual battery charging. Area/line marks use monotone interpolation and short native transitions; Reduce Motion disables animations. Distribution wattages use the matching battery-rail sample when a percentage is shown, preventing mismatched percentages and wattages. The graph uses battery V×I; the details explain different sensor timing.

Charging shows incoming watts first, then the Mac/battery split and remaining milestones. Battery mode prioritises discharge and runtime. Full/held states prioritise Mac load (input if no load sensor), with compact incoming/contract readings. No main-page scrolling is used, and natural-height fitting keeps shorter states compact. The initial expansion is smaller than V1.

Additional sensor investigation: the [Stats sensor implementation](https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift) identifies PSTR as system total, not a verified excluding-display-and-accessories measurement. The current native battery telemetry likewise does not expose a validated combined reading for that narrower scope. No speculative sensor subtraction, privileged IOReport/powermetrics process or unvalidated SMC reader was added; the unsupported metric is omitted and documented in the popover.

V2 validation: all 82 existing checks remain, with 24 additional checks for adaptive headline selection, negotiated electrical fields, bounded/real history, clock rollback, sampling gaps, source/direction changes, missing sensors and clearing history when hidden (106 total). Eight state fixtures, five fitted layouts and the details popover were rendered and reviewed. Production native reads on this Mac also verified the plugged-in/charging-paused state, including actual input and the separate 96 W contract. Other physical charger states remain subject to the V1 verification limits above.

V2 installed UI verification succeeded after the computer-use session reset: opened Overview → Power usage, observed the 80% charging-on-hold ring and actual Mac/input watts, watched the sample count advance from 1 to 7 to 12, opened the information popover (20 V / 4.8 A negotiated, 96 W ceiling, battery measurements and source notes), dismissed it, and reopened Power usage with a fresh one-sample history. The compact page and all Overview tabs, including the rainbow Intelligence action, were visible without scrolling. Notchloom 2.8.19 (319) is installed and running; strict signature verification passed.
