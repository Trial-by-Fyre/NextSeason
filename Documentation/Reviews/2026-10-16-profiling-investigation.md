# Physical-device profiling investigation — October 16, 2026

Session: `.instruments/20261016-110454` (54 completed recordings; three Network recordings skipped after xctrace crashed in NetworkConnectionStatsModeling).

Risk: medium. The repairs below affect developer measurement tooling only. No production Swift changes or new device recordings were made. Original report files were backed up in the Codex investigation workspace before regeneration.

## Hang: observed; root cause not proven

`stressSearchEmpty.trace` contains a NextSeason main-thread hang beginning at 17.476269 s and lasting 1.128067333 s. Its CPU samples disappear across all target threads from 17.482484291 to 18.590484541 s (1.10800025 s). Adjacent samples include `liboainject.dylib` allocation instrumentation; the Instruments UI displays a completed leak-check marker aligned with the hang. Multiple other long gaps occur throughout this heavily instrumented run.

The evidence suggests profiling overhead contributed, but the absent samples do not identify the blocked call or prove that uninstrumented NextSeason cannot hang. Keep the finding unresolved. A Time Profiler-only comparison after repairing the stress driver is the appropriate targeted follow-up; no speculative production optimization was made.

Apple describes Time Profiler as timer-based sampling rather than a complete execution history: [Optimize CPU performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/308/). The classification above is an inference from this saved trace, not an Apple diagnosis.

## Confirmed measurement defects and repairs

- **Flow timing:** read `OSSignpostIntervals`, resolve shared XML values, and match raw Begin/End references correctly. The first search has a complete 3420.644125 ms full-flow interval and 619.938542 ms search phase. Full-flow durations include automation sleeps and are not user-facing latency.
- **Unfinished intervals:** Instruments synthesizes a duration to the end of a recording even without an End event. An `end-process` sentinel now prevents those intervals from counting as completed timing. The empty-search stress interval is unfinished.
- **Allocations and leaks:** export `tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]` and `tracks/track[@name="Leaks"]/details/detail[@name="Leaks"]`, as listed in the real table of contents. These results were present but the analyzer looked only for nonexistent data-table schemas. Empty readable Leaks detail nodes mean zero leak rows; absent or malformed exports remain unknown. The inspected stress trace has green completed leak checks in Instruments.
- **CPU:** resolve referenced timestamps, weights, leaf frames, and backtraces. The original parser omitted most referenced samples and could attribute a newly defined caller as if it were the leaf. The actual stress trace has 2385 usable samples / 2385 ms CPU time, consistent with Instruments' approximately 2.38 s total.
- **CPU window:** TTFF is milliseconds, so adding 15 selected 15 milliseconds rather than 15 seconds. Launch flows now use TTFF through TTFF+15000 ms. Other flow types use their whole trace. An unknown timestamp no longer proves coverage inside a bounded window.
- **Memory:** read the physical-footprint column by its schema mnemonic, including inline and referenced values. The old regex could select another memory column. In search run 1, corrected baseline/peak/idle are 57.17/96.17/60.03 MiB; its old 118.28 MB peak was unreliable.
- **Live types:** allocation counts match actual type names and persistent counts, excluding generic keypaths/wrappers. Live screen/model objects are a retention heuristic, not proof of a leak.
- **Console errors:** stop suppressing collection and archive-read errors, and print explicit failure warnings without placing error messages into the captured app log. Historical log files are empty; the exact earlier failure cannot be reconstructed because stderr was discarded. The trace's os-log tables contain no substitute general app console capture.

## Stress-driver limitation

`ProfileFlowRunner.runStressSearchEmpty()` repeatedly assigns the same query and waits for a settlement token. `SearchAutomationModifier` assigns it to `viewModel.query`; `.task(id: query)` does not rerun when that string stays unchanged. SearchViewModel also intentionally skips an already-displayed outcome. Subsequent iterations can wait the full 15-second timeout without another search. This explains why a 140-second recording can end before the supposed 20-search scenario completes. Similar repeated-query waits exist in the search/detail/back driver.

Repair the profiling harness to request observable repeated work, distinguish success from timeout, and stop cleanly on cancellation before relying on its stress-loop completion. This is developer-test behavior, not evidence that production search is broken. That Swift change was not included in this investigation.

## Revised aggregate results

The session report.json/report.md were regenerated from all 54 saved recordings with the corrected analyzer. Readiness is **not established**.

- All 34 runs that recorded Leaks export zero leak rows; the 20 launch runs do not record Leaks and are excluded from this statement.
- Maximum measured physical footprint: **116.28 MiB** across the saved runs.
- Search phase: **505.03 ms average** over five cold-run search phases. The 3.32 s average full-flow duration also includes deliberate automation sleeps.
- Launch first-frame means remain approximately **864–871 ms** for the core launch variants.
- The single recorded 1.13 s hang remains in stressSearchEmpty; it has not been dismissed as harmless.
- Completed flow timing remains unavailable for seedWatchlist and all three stress scenarios. Two stress interval exports are explicitly unfinished; the seed and add/remove stress exports have no usable flow interval. These are not completed-scenario measurements.
- Every historical console log is empty, and the three Network runs remain missing. Missing evidence continues to block readiness.

The next development task is to repair and explicitly verify the stress driver, then perform one targeted Time Profiler-only comparison to test the instrumentation-overhead hypothesis. Investigate the surfaced console-capture error before another long suite; diagnose the Network recorder crash separately. No repeat full battery is needed merely to read these results.

## Verification

- 27 analyzer tests passed, including nine new real-export-shape/window cases.
- Focused fallback log-capture check passed for both scripts; explicit failed-capture visibility test passed.
- Shell syntax and diff whitespace checks passed.
- Real XML exports were cross-checked against the corrected parser and Instruments UI.
- Full app suite and a new device recording were not run.

Readiness remains pending for missing network and console evidence, unfinished stress scenarios, and the unresolved hang. The Hangs instrument in these traces records events above 250 ms; shorter stalls are not ruled out. Do not equate complete recording files or live ViewModel objects with a passed app-acceptance check.

## Follow-up: repaired stress driver and paired capture

The profiling search path now has a distinct request identity for every iteration and explicitly forces a new search even when the query is unchanged. Ordinary search retains its repeated-query shortcut. The profiling task awaits the actual search result and reports errors to its coordinator. Waits throw on timeout or cancellation; failed flows omit normal completion timing and record a failure outcome. Repository preparation errors also propagate. Each successful stress iteration records its number; paired captures include a unique run identifier to reject stale device files.

Focused verification: 26 SearchViewModel tests and six wait/coordinator tests passed, including 20 repeated empty searches against the mock service, ordinary repeated-query behavior, failure propagation, signal timing, and cancellation. Six hermetic comparison-script tests passed, including stale evidence rejection and the two instrument configurations. The final physical Profile compilation passed. The paired physical recording results are recorded below. The comparison script defaults to a fresh build, requires the explicit device identifier, and uses the bounded recorder/export paths. Changes remain uncommitted.

### Profile configuration defect found during the paired run

The first short capture (`stress-comparison-20261016-160208`) recorded a current-run start and an explicit TheTVDB authentication failure, with zero completed iterations. The second recording was correctly prevented. Inspection of the built app found an empty `TVDBApiKey`: the app target’s Profile configuration lacked the `Base.xcconfig` reference used by its other configurations. Added that reference, rebuilt successfully, and verified the bundled key matches the local configuration without displaying its value. This was a build configuration failure, not a completed empty-search measurement. The paired recording was retried only after correcting the confirmed cause.

The missing Profile key also limits interpretation of historical search timings: without success/failure outcome records, their timing intervals alone do not prove successful searches. Retain the original trace evidence, but do not present those durations as verified successful-search latency.

### Paired physical result

Session: `.instruments/stress-comparison-20261016-160451`, physical iPhone `00008160-001E1DE204C1400A`, same corrected Profile binary in both captures. Both mode files contain the matching unique run identifier, one start, exactly 20 ordered successful iterations, and one completion. App-recorded full-driver durations are 10.494 s (Time Profiler only) and 12.373 s (with Allocations, Leaks, Activity Monitor); these include automation waits and are not individual search latency. Usable CPU samples: 2005 and 3329 respectively. Both readable potential-hangs exports contain zero recorded app hangs, with the same 250 ms threshold.

The heavier trace contains the completed 12373.543708 ms flow interval. The lean trace has no completed interval: its raw signpost export contains the flow End at 11.420302666 s, but no matching Begin. The analyzer correctly marks the formal comparison incomplete rather than substituting the app timing for missing trace evidence. This capture gap does not negate the run-identified 20-search completion records. No additional phone recording was made to chase it.

The previous 1.13 s hang did not recur in either saved capture. This pair does not establish its cause or prove absence of shorter stalls; retain it as unresolved. The repeated-search driver is now verified on the physical phone. Missing historical Network/console evidence and other deferred app checks still prevent beta-readiness claims. Final Profile build, scoped Swift lint, six comparison-script tests, and diff whitespace checks passed. All changes remain uncommitted.

## Four follow-up checks requested by Janine

Risk remains medium: scoped developer capture/analysis behavior; no persistence or entitlement change. Checklist: (1) both timed captures must contain a complete flow interval and 20 current-run successes; (2) preserve hang findings and investigate captured stacks/sample coverage; (3) recover valid HTTP and console artifacts without accepting empty evidence; (4) run the full test plan and exercise Diagnostics manually. Self-review applies to these bounded tooling changes.

### Timing and hang comparison completed

A timed caller now opts into `-ProfileRequireSignposts`. The driver waits up to 10 seconds for `OSSignposter.isEnabled` before opening its flow interval; timeout and cancellation retain the existing explicit failure outcomes. Uninstrumented callers do not wait for an attached recorder. The comparison and timed suite entry points pass this flag.

Physical session `.instruments/stress-comparison-20261016-162449` contains two complete 30-second captures. Both have 20 ordered current-run successful searches, a completed flow interval, usable CPU samples, and readable hang evidence with a 250 ms threshold. Time Profiler alone: 10.614498417 s full flow, 1837 CPU samples, zero recorded hangs. With Allocations, Leaks, Activity Monitor: 12.091536541 s full flow, 3002 samples, one 1.198901916 s main-thread hang starting at 6.031272500 s. These are full driver durations, including deliberate waits.

The heavy trace again loses samples across the app’s threads for 1.124000292 s (6.050172416–7.174172708 s), overlapping the hang. The original trace similarly loses all target-thread samples during its 1.13 s event. Neither trace captures the blocked app call during that gap or supplies a useful hang-detail stack. The completed comparison supports instrumentation contributing to a pause; it does not prove cause or establish that production cannot hang. No speculative production optimization or further repeated phone experiment was made.

### Network and console capture repaired

One app-filtered native collection attempt exited 77: `log: Must be root to collect logs from attached device`. Noninteractive sudo was unavailable (password required). This explains current native capture failure; historical suppressed stderr cannot be reconstructed. The suite and resume scripts now default to recording `os_log` and exporting readable app-process events from the same trace, avoiding administrator collection. Native mode remains explicit. Missing app events stay empty/missing; exporter diagnostics never enter the evidence file.

The saved xctrace crash is EXC_BREAKPOINT/SIGTRAP in Apple’s `NetworkConnectionStatsModeling.receive(row:writer:context:)`. Replacing Network Connections with HTTP Traffic under the Time Profiler template avoids that component. A 25-second physical search capture (`.instruments/http-logging-20261016-162639`) finished successfully using Time Profiler + HTTP Traffic + os_log. Its HAR export initially exposed a second bug: this Xcode requires an output directory, not a `.har` filename. The new exporter uses a temporary directory, validates/merges emitted HAR files, and writes the expected run artifact. Saved-trace verification produced 47 HTTP entries and 2299 deduplicated app-process console events (142 under the app subsystem). Both providers were present in the HAR. The console contains flagged warnings/faults, including the expected possibility of abrupt termination around recorder shutdown; it is not a clean-console pass. These artifacts are local and gitignored.

The replacement path is integrated into both suite scripts; it is not a rerun of all missing historical flows. The original suite remains incomplete. New exporter/backend tests cover XML references, preserved severity, duplicate exports, other-process filtering, omission of HAR binary payloads, directory HAR merging, malformed/empty HAR rejection, and avoiding native logging in trace mode.

### Full-suite result

The explicitly authorized SerialTesting plan ran on iPhone 18 Pro Max simulator, iOS 27.0, Xcode 27.0. Unit result: 511 tests in 71 suites, one failure. UI result: all 38 tests passed. Failure: `WatchlistRecoveryExportReaderTests.corruptSnapshotFallsBackToSQLiteIdentity()`, line 137, fixture precondition `sqliteResult.foundWatchlistTable == true`. The later corruption and final recovery assertions in that test did not fail. This does not establish a cause or justify calling the failure pre-existing. One focused reproduction is being recorded separately. No production persistence behavior was changed to silence it.

### Focused reproduction and manual Diagnostics

The recovery-export fixture failure reproduced in one focused run of its six tests, alongside all six passing ProfileFlowWait tests. This confirms the full-suite failure was not resolved by isolation; the cause remains undiagnosed. No unrelated persistence change was made. The next bounded diagnostic is to expose SQLite error/return codes and check SwiftData fixture store/sidecar lifetime before choosing a fix.

Manual check used the normal Debug app on the iOS 27 simulator because `-UITesting` intentionally hides About/Diagnostics. Opened About → Diagnostics, confirmed Debug channel and notifications enabled, and used the existing simulator watchlist template (Call the Midwife). Button path: Step 1 baseline/pending debounce → Schedule Pipeline Test Notification (9-second delay, scheduled) → Run Simulated Update Scenario (Step 2 updated/notification scheduled) → next tap returns to Step 1. The delayed notification banner appeared. The delayed runner did not reset the step runner. Force Refresh Now displayed its loading state and then `Refreshed 1 show(s) (forced)`, with no notification for no meaningful change. These UI checks do not establish real-device background notification delivery or exhaustive accessibility acceptance.

Final focused tooling verification: six comparison tests, six exporter/backend tests, seven native capture lifecycle tests, three recovery/watchdog tests, physical Profile build, scoped Swift lint, shell syntax, and diff whitespace checks passed. The exporter was also run against the saved physical trace to produce actual HAR and console artifacts. A seed trace-path integration error caught by the lifecycle tests was fixed before their passing rerun. Changes remain uncommitted. Full-suite acceptance remains blocked by the reproduced recovery-export test; the earlier suite still lacks historical evidence.

Diagnostics Help opened with readable explanatory text and returned to Diagnostics successfully.

## Recovery-export fixture failure resolved

Janine authorized fixing the remaining setup failure. Diagnostic reproduction exposed SQLite result 5 (`SQLITE_BUSY`, `database is locked`) when the direct read-only scanner prepared its schema query. Merely moving that read before the fixture’s write connection still failed. Draining an explicit `autoreleasepool` around fixture creation released retained SwiftData/Objective-C storage resources before direct SQLite access; all six recovery-reader tests then passed on the same iOS 27 simulator. The exact internal retained object was not identified; the observed resource lifetime and successful pool boundary support a fixture-lifetime diagnosis.

Only `NextSeasonTests/WatchlistRecoveryExportReaderTests.swift` changed for this repair. The fixture now saves inside `autoreleasepool`, validates readability and the target identity before opening its corruption connection, requires exactly one updated row, and verifies that the damaged row recovers with unknown season status while the healthy row retains its original status. No sleeps, retries, skipped assertions, or production persistence changes were added. Temporary diagnostic prints were removed and the production reader restored byte-for-byte. Final scope is a low-risk fixture correction; self-review found the original corruption/recovery coverage preserved and strengthened.

Verification: all six reader tests passed, scoped Swift lint and whitespace checks passed. The previous full-suite failure remains part of its historical run; the full 511-unit/38-UI plan was not rerun for this fixture-only change. The prior passing UI and unrelated test results are not represented as a new full-suite result. All changes remain uncommitted.

References: [SQLite result-code meanings](https://www.sqlite.org/rescode.html#busy) describes BUSY as conflicting connection activity; [Apple’s autorelease-pool guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html) explains release of autoreleased objects at the pool boundary. The diagnosis of this fixture is based on the local reproductions, not a documented SwiftData guarantee.
