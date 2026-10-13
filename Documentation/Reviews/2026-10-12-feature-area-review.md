# NextSeason feature-area review — October 12, 2026

This review follows complete feature flows and their interactions: state changes, asynchronous work, failures, recovery, and responsibility boundaries. It does not propose a general rewrite or style cleanup. No application code was changed.

## Scope and evidence

- Read the 154 Swift files under `NextSeason`, the shared accessibility definitions, and the 12 Python/shell developer-tool files. Reviewed project configuration and the test coverage inventory, then inspected relevant test implementations. Historical transcripts and secret values were not treated as configuration or modified.
- Ran `NextSeasonTests` with Xcode 27 on an iPhone 16 simulator running iOS 18.6: **407 tests passed, 443 runs including parameterized cases, zero failures or skips**.
- Ran the complimentary-build boundary checks: **5 Python tests passed**.
- Used a temporary macOS Swift harness containing the current feature implementations and controlled dependencies. It reproduced 11 scenarios described below. This tests their underlying logic, not iOS UI behavior. The SwiftData save-failure fixture used a deliberately read-only store; it demonstrates dirty context state after failure, not an actual disk-full incident.
- Used isolated Python and shell fixtures to reproduce missing-trace approval and lost log-capture state. No device profiling session was started.
- UI tests, actual App Store sandbox transactions, real background launches, and device accessibility testing were **not** run in this review.

The temporary harness and outputs are under `/tmp/NextSeasonReviewHarness.swift` and `/tmp/NextSeasonReviewHarness-output.txt`. Findings and expected regression scenarios are recorded here so the review does not depend on those temporary files remaining available.

**Evidence labels:** “Reproduced” means the current implementation was exercised with a controlled fixture; “code trace” means the relevant production path was followed through its callers. Neither is a claim of exhaustive integration verification.

## Feature map

| Area | Main responsibilities and code | Review result |
|---|---|---|
| 1. Guest search and show resolution | Search views/models, TheTVDB client, canonical TVMaze resolution | Dropped page remainder, stale Load More completion, silent mutation errors |
| 2. Offline show matching and mapping refresh | SQLite mapping, bundled generator, incremental refresh | Unavailable mapping looks like no matches; delayed resume loses backlog |
| 3. Show details and next-season calculation | Detail view/model, domain mapping, calculator, date presentation | Date shifts; next episode incorrectly treated as premiere evidence |
| 4. Watchlist management | Tracking, removal/Undo, sections, filtering, paused rows | Undo can exceed free capacity; unused geometry plumbing |
| 5. Foreground/background refresh | Refresh service, update windows, scheduler, lifecycle wiring | Long absences miss updates; failures can be reported as success |
| 6. Notifications | Change detector, persisted dedupe, permission/settings, delivery | Failed scheduling consumes the notification permanently |
| 7. Plus, tips, and access reconciliation | Purchase service, StoreKit client, complimentary access, pause/resume | No new StoreKit-specific defect established; integration coverage remains limited |
| 8. Persistence, migration, and recovery | SwiftData repository/schema, launch recovery, store reset | Failed writes remain dirty; one corrupt snapshot blocks the whole list |
| 9. Watchlist export | CSV formatting, file transfer, ordinary/recovery preparation | No additional independently established defect; shares the date-presentation problem |
| 10. Navigation and first-run experience | Tab/path coordinator, notification routing, first-run preferences | Earlier notification lookup can override a later tap |
| 11. Accessibility and shared presentation | Shared rows, toast, colors, spacing, keyboard/platform adapters | Coverage gaps on purchase/About/recovery surfaces; no new device-verified defect |
| 12. Diagnostics and development tools | Simulations, reports, performance flows, capture/analyzers, build guards | Simulation never reaches step two; incomplete evidence can pass; capture state lost |

## Findings by feature area

### 1. Guest search and show resolution

**R04 — P2: Filling an actionable page permanently drops the remainder of the last fetched API page.**

Location: [SearchViewModel.swift:302](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Features/Search/SearchViewModel.swift:302>).

The cursor advances over the entire raw page, but the inner loop stops as soon as the accumulated actionable count reaches ten. Example: the first API page has nine mapped hits; the second has ten. The implementation keeps only the first hit from the second page and discards nine usable results. If that second page is final, there is no Load More button to recover them. **Reproduced: 19 actionable hits became 10, with `hasMore == false`.**

Suggested change: treat the target as a soft limit and retain the whole fetched page, or retain a buffer for its unused remainder. Regression: partial first page plus full final page must preserve every unique mapped hit.

**R05 — P2: An old Load More request can append results to a different query.**

Location: [SearchViewModel.swift:204](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Features/Search/SearchViewModel.swift:204>), called by an unstructured task in `SearchView`.

Load More captures query A but, after awaiting, checks only that the current state is `.results`. Changing the search text cancels the query task, not that button-created task. If query B finishes first, A's late page is appended to B and its cursor/`hasMore` replaces B's. The old `defer` can also reset a newer request's loading flag. **Reproduced: B's ten results were followed by A's ten unrelated results.**

Suggested change: tie initial search, pagination, cursor, loading state, and completion writes to one search generation. Regression: release A's held page after B has loaded; B must remain unchanged.

**R06 — P2: Search-row persistence failures are silent to the user.**

Location: [SearchWatchlistTracking.swift:115](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Features/Search/SearchWatchlistTracking.swift:115>).

Resolution failures reach the search alert, and detail-screen save failures reach an alert, but `handleTrackButton` catches actual add/remove-lookup errors internally and only records analytics and refreshes stars. The outer `SearchView.trackResult` catch cannot see them. A failed add therefore looks like a tap that did nothing. **Evidence: code trace across the view, helper, and shared toggle.**

Suggested change: return a mutation failure or route it through the existing search error presentation. Regression: make `repository.add` and removal lookup throw after successful resolution; an actionable failure message must appear.

The shared toggle and active-ID policy are useful existing boundaries; preserve them. The two network clients have superficially similar request code, but their authentication and endpoint semantics differ enough that a generic networking framework is not justified by this review.

### 2. Offline show matching and mapping refresh

**R07 — P2: Mapping initialization failure turns healthy search results into “no matches.”**

Location: [AppCompositionRoot.swift:101](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/App/AppCompositionRoot.swift:101>), consumed by `SearchViewModel.filterActionable`.

After both database-open attempts fail, composition injects an empty map and disables mapping refresh. Every TheTVDB hit is then filtered out before the live lookup fallback can be invoked. Search presents ordinary empty-result guidance, although the problem is local infrastructure, and cannot recover during that composition's lifetime. **Evidence: code trace.**

Suggested change: represent unavailable mapping separately from “this ID has no mapping,” with retry/recovery or a deliberately bounded live-resolution fallback. Regression: fail database bootstrap while returning valid TheTVDB matches; do not mislabel the outcome as an ordinary title miss.

**R08 — P2: A resumed mapping sync chooses a rolling API window relative to its old horizon.**

Location: [ShowIDMappingRefreshService.swift:220](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/ShowIDMapping/ShowIDMappingRefreshService.swift:220>).

The fixed horizon is appropriate for deciding which updates belong to a sync. It is not appropriate for deciding how far back a request made today must reach. `since=day/week/month` is a rolling server window. A sync that started with a one-hour gap keeps requesting `day` even if its capped backlog resumes two days later. The old backlog disappears from that response, the service declares completion, and advances its watermark past unprocessed mappings. **Reproduced: only the first of three mappings was written; after a two-day delay the sync completed with the other two absent.** TVMaze documents the filtered and unfiltered endpoints in its [API reference](https://www.tvmaze.com/api#show-updates).

Suggested change: choose the request window against current request time, while retaining the original horizon for local upper-bound filtering and completion. Regression: capped sync resumed after its original day/week/month window has aged out.

The bundle-recovery path and persisted resume cursor are worth retaining. Separately, `applyMapping` deletes then upserts without a SQLite transaction, and cursor components are stored in separate writes. Those are follow-up durability concerns: interruption or a write failure can leave partial logical state. They were not separately fault-injected in this review.

### 3. Show details and next-season calculation

**R02 — P1: Premiere dates display one day early in time zones west of UTC.**

Locations: [NextSeasonStatus+Display.swift:19](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Features/ShowDetail/NextSeasonStatus+Display.swift:19>) and [StatusChangeDetector.swift:154](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/StatusChangeDetector.swift:154>).

The parser represents a provider calendar date at midnight UTC, but headlines and notification bodies use default local-time formatting. **Reproduced: provider date `2027-01-01` displayed as `Dec 31, 2026` in America/Los_Angeles.** This affects detail, watchlist, alerts, and the descriptive Next Season CSV column. The dedicated CSV premiere-date column already preserves the UTC day, making the same export internally inconsistent.

Suggested change: one localized date-only formatter that preserves the stored calendar day, shared by every presentation surface. Regression: the same provider date must remain January 1 in Los Angeles, UTC, and a positive-offset time zone. Keep separate treatment for actual instants such as `dateAdded` and `lastCheckedAt`.

**R09 — P2: A later episode can be reported as a season premiere when season metadata is incomplete.**

Locations: [ShowData+Domain.swift:41](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Models/Mapping/ShowData+Domain.swift:41>) and [NextSeasonCalculator.swift:56](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/NextSeasonCalculator.swift:56>).

The DTO receives the next episode's number, but the domain model discards it. If season 2 lacks a premiere date, it is excluded from `latestAired`; any dated next episode in season 2 can then become `.scheduled(season: 2, premiere: episode.airdate)`. **Reproduced with a supported payload: season 2 episode 8 on February 1 became “Season 2 premieres February 1.”** The fixture establishes the wrong inference; the frequency of such incomplete live records was not measured.

Suggested change: retain episode number and distinguish evidence of a premiere from an upcoming episode. Define the incomplete-data fallback explicitly rather than calling an arbitrary episode date the premiere. Regression: undated season row with next episode 1, 8, or an unknown number.

The pure, date-injectable calculator is a good structure. These fixes belong in its inputs and shared presentation, not separate patches to every view.

### 4. Watchlist management

**R10 — P2: Undo can restore a fourth active show after the freed slot has been filled.**

Location: [WatchlistPendingRemoval.swift:321](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Features/Watchlist/WatchlistPendingRemoval.swift:321>).

Start with three active free-tier shows, swipe-delete A, add D into the freed slot, then Undo A. Restore bypasses admission entirely. **Reproduced: four active rows; the normal pause policy subsequently selects D for pausing.** Adds already recheck when Undo wins the race before an add completes; the opposite order is missing. Until reconciliation, all four can be treated as active.

Suggested change: make restoration and capacity enforcement one coordinated operation. **Product decision needed:** when Undo competes with an already-completed replacement, preserve the restored row as paused, reserve the slot during Undo, or explain a replacement policy. Do not silently choose which user's action loses. Regression: both event orders, free/Plus changes during the window, and paused-row Undo.

Structural follow-ups:

- `toastAnchor`, row-frame dictionaries, button-frame observation, and CGRect parameters are still maintained throughout the tracking flow, but the current toast is fixed above the tab bar and never reads the anchor. Removing this unused path would reduce layout observation and simplify APIs without redesigning the watchlist.
- Restore performs add, refresh-field restoration, and optional pausing as separate saved writes. A dedicated repository restoration operation would preserve the row atomically and centralize the capacity decision.
- `WatchlistViewModel.State.loading` has no assignment in its current implementation; it is a leftover state rather than a live part of its flow.

Existing grouping, pending-removal exclusion, and active/paused distinction are coherent; they do not warrant a general refactor.

### 5. Foreground/background refresh

**R11 — P2: Long absences can leave stable-status rows indefinitely out of date.**

Location: [WatchlistRefreshService.swift:248](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/WatchlistRefreshService.swift:248>).

Ordinary refresh always uses the filtered update endpoint, capped at `month`. Unlike mapping refresh, it never uses `requiresUnfilteredUpdateMap`/`allUpdatedShows`. A saved `.announcedUndated`, `.ended`, or `.unknown` row whose last server change fell outside that window is skipped because it does not receive a calendar recheck. For example, a date added while the user was absent may never appear until a forced refresh or another server edit. **Reproduced: a 90-day-old undated row requested `month`, made no full-map request, and fetched no show detail.** The rolling-window behavior is documented by [TVMaze](https://www.tvmaze.com/api#show-updates).

Suggested change: choose an unfiltered map or a bounded full-detail catch-up when the gap exceeds the supported window. Regression: a show changed after its saved check, but more than a month before the next launch.

**R12 — P2: Refresh failures are erased before the background scheduler reports success.**

Locations: [WatchlistRefreshService.swift:354](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/WatchlistRefreshService.swift:354>), [RefreshScheduler.swift:85](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/RefreshScheduler.swift:85>), and background composition wiring.

Per-show failures are logged and skipped without a failure count. An updates-map failure returns an outcome containing failure text. The background handler discards both and returns `Void`; the scheduler reports success whenever the task was not cancelled. Thus an offline or completely failed refresh can be marked successful, and a forced pass can describe itself as “Refreshed 0 show(s)” without stating that every fetch failed. **Evidence: code trace; actual BGTask execution was not run.**

Suggested change: propagate a typed result with successful, skipped, failed, and cancelled work; format text at the diagnostics boundary. Define how partial success maps to BGTask completion. Regression: total network failure, repository-load failure, mixed success, empty list, and cancellation.

Retain the existing stale-response timestamp check, post-fetch active-row reread, persisted catch-up marks, and expiration completion guard. They solve real interactions. Future tests should also distinguish duplicate overlapping polls from genuinely later confirmation polls.

### 6. Notifications

**R03 — P1: A notification is persisted as already announced before scheduling succeeds.**

Locations: [WatchlistRefreshService.swift:330](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/WatchlistRefreshService.swift:330>), [StatusChangeDetector.swift:126](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/StatusChangeDetector.swift:126>), and `NotificationService.scheduleNotification`.

Evaluation sets `lastNotifiedSignature`, then refresh saves it before calling the delivery service. Delivery returns no result and swallows scheduling errors. If `center.add` fails—or the process ends between persistence and delivery—the next poll sees an unchanged, already-announced state and does not retry. **Reproduced at the state boundary: first evaluation requested an alert; reevaluating its persisted state requested none, even though no scheduling acknowledgement had occurred.** Apple exposes scheduling failure through the [notification add API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)).

Suggested change: distinguish observed status, pending notification, and system-accepted scheduling. Persist retryable intent and acknowledge acceptance explicitly. This requires a lifecycle design, not simply reversing two statements: reversing them introduces interruption/deduplication problems of its own.

Regression: schedule rejection followed by recovery, termination before/after acceptance, and duplicate refreshes. **Product decision:** intentional suppression during interactive refresh and disabled permission should be distinguished from transient failure; decide whether enabling notifications should replay missed history.

The permission/settings entry points and shared notification status presentation are sensibly centralized. Notification navigation is reviewed separately below.

### 7. Plus, tips, and access reconciliation

No additional StoreKit-specific correctness defect was established in this pass. Reviewed initial loading versus unverified versus confirmed access, transaction observation/finishing, pending purchases, tips, restore, complimentary Keychain persistence, beta build eligibility, simulation sessions, and watchlist pause/resume/catch-up interactions.

The current entitlement scan appropriately uses StoreKit's current entitlements rather than treating a passed transaction expiration date as automatic loss of access. Apple documents subscribed and grace-period subscriptions in [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements). Existing unknown-access protection and silently baselining resumed shows are useful safeguards.

Two small structural follow-ups:

- `PurchaseService.start(watchlistCount:)` no longer uses the count, but launch still fetches it and tests still pass it. Remove the obsolete parameter/read when making a scoped cleanup.
- Product loading can be requested by startup, the tip section, and the paywall concurrently. `isLoadingProducts` is a Boolean without a shared in-flight operation; one completion can clear it while another load remains pending. Coalescing catalog loads would make that state truthful and avoid redundant requests.

The passing tests primarily exercise purchase doubles. Actual grace-period, revocation/refund, delayed approval across restart, and device/account restore behavior remain integration-verification work; this review does not establish those scenarios as newly passed.

### 8. Persistence, migration, and recovery

**R01 — P1: Failed SwiftData writes leave mutations in the shared context.**

Location: [SwiftDataWatchlistRepository.swift:75](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Persistence/SwiftDataWatchlistRepository.swift:75>), with the same pattern in remove, pause, and refresh updates.

Repository methods mutate the long-lived context and then call `save`, but do not roll back when saving throws. The UI can report failure while subsequent reads see the failed insert/delete/update; a later successful unrelated save can commit those pending mutations. This undermines retry, Undo, notification acknowledgement, and access reconciliation together. **Reproduced with the actual repository and a read-only SwiftData store: add threw, `contains(showID:)` still returned true, and `context.hasChanges` remained true.** Apple describes discarding pending inserts, deletes, and changes using [ModelContext rollback](https://developer.apple.com/documentation/swiftdata/modelcontext).

Suggested change: provide an explicit failure rollback boundary for each logical repository operation, ensuring it cannot discard another operation's legitimate unsaved work. Regression: failed insert, delete, pause, and refresh write; verify same-context reads, retry, and an unrelated subsequent save.

**R13 — P2: One corrupt next-season snapshot blocks the entire watchlist without reaching recovery.**

Location: [SwiftDataWatchlistRepository.swift:29](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Persistence/SwiftDataWatchlistRepository.swift:29>).

`all()` throws if any row's JSON snapshot cannot decode. The ModelContainer can still open, so launch enters the ready state rather than the recovery/export flow. The watchlist, ordinary export, refresh, and access reconciliation all use `all()` and fail. Retrying does not repair the snapshot. **Reproduced: container opened successfully; `all()` threw while identity reads still returned the saved ID.** The SQLite fallback can recover this row, but is offered only in launch recovery.

Suggested change: make row-level decode damage recoverable without dropping saved identities. Define repair/quarantine and user messaging, preserving valid rows and export. Regression: mixed valid/corrupt snapshots must not make every saved show inaccessible.

Schema/versioning and reset guards are thoughtfully separated. The existing schema test explicitly does not prove an upgrade from a previously compiled TestFlight binary; retain that manual upgrade check. Also consider a non-destructive retry for first store-open failures caused by transient availability. This is a recovery design question, not a claim that every open failure implies corruption.

### 9. Watchlist export

Reviewed ordinary and recovery export preparation, complete saved-list inclusion, CSV escaping, basic formula-leading title handling, UTC date column, file naming/BOM, transfer representation, and best-effort SwiftData/SQLite reads.

No additional independently established export defect is recorded. R02 makes the descriptive Next Season column disagree with the canonical premiere-date column. R13 prevents ordinary export after a row-level decode failure. Preserve export of paused rows and missing mapping IDs as empty cells.

Verification still needed on real Numbers/Excel sharing and recovery from a genuinely damaged store. Recovery's multi-write state and temporary files deserve interruption checks; the current tests cover controlled malformed snapshots and fallback files, not every corruption pattern.

### 10. Navigation and first-run experience

**R14 — P2: A slow earlier notification tap can override a later tap.**

Location: [AppNavigationCoordinator.swift:202](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Services/AppNavigationCoordinator.swift:202>).

The queue is consumed before asynchronous preparation/lookup. A second tap can begin another resolution while the first is suspended; the first completion has no generation guard and still changes the tab/path. Animation intent is also read from shared mutable state after awaiting. **Reproduced: tap A waited on an unsaved show's network lookup; tap B resolved a saved show and selected Watchlist; A completed and switched back to Search while B's detail was still pending.**

Suggested change: capture navigation intent per request and allow only the latest valid request to apply its result, including deferred Watchlist detail. Regression: reverse completion order across network lookup and entitlement preparation, plus a manual tab change while resolution is pending.

The buffered cold-launch tap, deferred Watchlist push, and one-time landing-tab decision are useful. First-search/hint preferences are small and coherent; no broader onboarding redesign is suggested.

### 11. Accessibility and shared presentation

Reviewed shared row labels/actions, 44-point track controls, accessibility-aware Undo duration, section headers, status wording, platform toast chrome, and keyboard/tab adapters. No new device-verified accessibility defect is claimed.

Coverage gap: UI-test composition suppresses About entirely and substitutes simplified dependencies. Existing accessibility audits cover search/detail/watchlist states, but do not exercise About, the Plus paywall, tips, recovery, or the complete permission/restore flows. Add those surfaces to the verification plan, particularly large Dynamic Type, VoiceOver focus after alerts/sheets, and Reduce Motion behavior. Existing iOS 18 audit exceptions also limit what a passing audit proves; their documented limitations should remain visible.

Avoid splitting views merely to satisfy a line count. The strongest simplification is removing obsolete geometry plumbing and consolidating genuine state ownership, rather than extracting every small presentation helper.

### 12. Diagnostics and development tools

**R15 — P2: The two-step simulated update resets on every button tap.**

Location: [DiagnosticsView.swift:489](</Users/janine/Documents/TbF Projects/NextSeason/NextSeason/Features/Debug/DiagnosticsView.swift:489>), through `prepareSimulatedUpdateRunner`.

The runner is designed to retain its seeded repository and advance baseline → updated between calls. The view creates a new runner immediately before every `runNextStep`, so each button tap starts over at step one. The normal scenario cannot exercise the update/notification branch. **Evidence: code trace through the view and runner; runner-only tests do not exercise this ownership mistake.**

Suggested change: reuse a runner for the scenario/template until explicit reset or completion; keep one-shot delayed tests separate. Regression: invoke the view's action twice and observe step one then step two, followed by reset.

**R16 — P2: Missing profiling evidence can produce a successful beta-readiness report.**

Locations: [analyze-performance-traces.py:537](</Users/janine/Documents/TbF Projects/NextSeason/Scripts/analyze-performance-traces.py:537>) and [analyze-performance-traces.py:503](</Users/janine/Documents/TbF Projects/NextSeason/Scripts/analyze-performance-traces.py:503>).

Missing traces are warned about and skipped; failed exports become empty strings; empty metric collections do not count as failure. With no resulting warning/failure flows, the report emits “Safe for beta.” **Reproduced: a manifest with an absent search trace returned exit code zero and that readiness conclusion.** The uninstrumented comparison likewise labels missing timing measurements “No” under “Feels slow?” rather than unknown.

Suggested change: validate evidence completeness and represent unavailable/incomplete measurements explicitly. Regression: missing traces, failed exports, missing required tables, incomplete run counts, and absent logs must never establish readiness.

**R17 — P2: Log-capture setup loses its state in a command-substitution subshell.**

Locations: [profile-performance-suite.sh:191](</Users/janine/Documents/TbF Projects/NextSeason/Scripts/profile-performance-suite.sh:191>), [resume-performance-suite.sh:115](</Users/janine/Documents/TbF Projects/NextSeason/Scripts/resume-performance-suite.sh:115>), and `Scripts/lib/device-log-capture.sh`.

`LPID="$(start_log_stream ...)"` runs setup in a subshell. The helper's device/file/predicate/PID globals therefore never reach the parent. The stop wrapper ignores its supplied marker and instead reads the parent's empty globals. Fallback collection never runs; a streaming process cannot be stopped through this path. **Reproduced with a fake log command: the marker was `capture`, parent device/file state was empty, and the only command was `help stream`; no collection occurred.**

Suggested change: call stateful setup in the parent shell, or pass a complete explicit capture handle to cleanup. Add error/exit cleanup. Regression: both streaming and fallback modes must collect/stop exactly once, including an interrupted trace run.

Other tooling limitations worth retaining in the report: profiling flows perform direct repository operations rather than the production tracking orchestration, repeated identical search queries may hit the “already displayed” shortcut, and timing waits silently time out. These measurements should not be presented as verification of purchase limits, notification prompts, or full user-visible add/remove behavior. The crash-reporting helper also still claims MetricKit crash summaries exist, although the retained hook intentionally only records a breadcrumb.

## Cross-feature structure and recommended order

Three recurring responsibility problems explain most of the findings:

1. **Observation and acknowledgement are conflated.** A refreshed status, a saved write, and an accepted notification are distinct events. Failure/recovery boundaries must preserve that distinction.
2. **Asynchronous results lack ownership of the state they update.** Search pagination and notification routing need request identity/generation checks; actor isolation alone does not prevent stale completions. This is useful Swift concurrency interview knowledge: an actor serializes execution segments, not a whole operation across suspension points.
3. **Validation infrastructure treats missing evidence as benign.** In-memory repositories and simplified UI composition are useful, but they conceal persistence transaction behavior and production-only surfaces. The in-memory repository's `updateAfterRefresh` also recreates an absent row while the production implementation is a no-op; align that contract so tests cannot verify a different persistence policy.

Recommended sequence:

- First: **R01, R02, R03** — write rollback, calendar-date correctness, and notification acknowledgement/retry.
- Next: **R04/R05, R08/R11, R13/R14** — complete search pages, stale completions, delayed refresh, row-level recovery, and navigation ordering.
- Resolve the **R10 Undo/capacity product choice** before changing that behavior. Address R06/R07 and refresh outcome reporting alongside the relevant feature fixes.
- Repair **R15–R17** before relying on Diagnostics/performance tooling as acceptance evidence.
- Make the identified structural cleanups in separate small diffs with targeted verification.

Persistence and notification lifecycle fixes are high-risk behavior changes under `FEATURE_DEVELOPMENT.md`; they need discovery, a behavior matrix, and independent design/acceptance review before being called complete. This document is a review, not an approved implementation specification or acceptance of the remaining limitations.

## Files changed

Only this review document was added, to retain the feature map, findings, reproduction evidence, and verification gaps. Application code, tests, project configuration, planning documents, and historical records were unchanged. Nothing was committed.
