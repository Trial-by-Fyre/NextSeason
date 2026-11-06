# Launch-time registration after persistence recovery — November 5, 2026

Status: **implemented, pending verification** (simulator and physical-device checks
below; independent acceptance review pending).

## Problem

`RefreshScheduler.registerBackgroundTask()` and `NotificationRouting.installDelegate()`
ran from `AppCompositionRoot.configureNonUITestRuntime()`, which runs only when
composition succeeds. On a normal launch that is inside `NextSeasonApp.init` (via
`AppLaunchState.bootstrap()`). When launch fell into recovery and a later recovery
action succeeded in the same process, composition — and registration — ran after
launch had finished, which Apple documents as a crash.

Risk classification: **high** — launch lifecycle, background tasks, notification
delivery, and a crash on the recovery path that also feeds the crash-loop counter.

Owner decision (November 5): keep Try Again for V1 and keep the fix narrow. Reset
Local Data also recomposes in the same process, so removing Try Again would not
remove the problem.

## Platform documentation

1. [`BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)):
   every permitted identifier requires a handler; "Registration of all launch
   handlers must be complete before the end of `applicationDidFinishLaunching(_:)`."
   "Register each task identifier only once. The system kills the app on the second
   registration of the same task identifier." Returns `false` when the identifier is
   not in the built app's `BGTaskSchedulerPermittedIdentifiers`. (verified)
2. [`UNUserNotificationCenter.delegate`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate):
   set before the app finishes launching; assigning later "might cause you to miss
   incoming notifications." (verified)
3. [`BGTaskScheduler.submit(_:)`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:)):
   submits a *previously registered* task; submitting again for an unexecuted
   identifier replaces the pending request; one refresh task may be pending. (verified)
4. [Starting and terminating tasks during development](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development):
   debugger commands simulate a task launch and its expiration in a running app on
   a physical device. (verified)
5. **Unverified assumption:** SwiftUI `App.init` runs before
   `applicationDidFinishLaunching` ends. Not documented. Supporting evidence: the
   normal launch has always registered from inside `App.init`, and the unit-test
   host launches with the new order without crashing. Closing evidence: both
   P4a and P4b below, covering separate system-initiated cold launches.

## Decisions (owner, November 5)

- **D1:** register in `NextSeasonApp.init`, first, before `bootstrap()`; no UIKit
  app delegate. The cold-launch timing check stays pending until there is evidence.
- **D2:** a tap buffered during recovery is dropped once Reset Local Data wipes the
  store, even if reopening then fails. Try Again keeps it.
- **D3:** a background task delivered with no handler completes with failure and is
  not rescheduled; the next successful composition schedules again.
- **D4:** DEBUG-only recovery fixture (below). Run it in an isolated installation.

## Implementation

1. `NextSeasonApp.init` installs the notification delegate and calls
   `RefreshScheduler.registerBackgroundTask()` before `bootstrap()` (skipped under
   `-UITesting`, as before).
2. `BackgroundTaskRegistration` (in `RefreshScheduler.swift`) makes registration
   one-time per process; a repeat call is ignored, a `false` result is logged as a
   fault and the breadcrumb `background_task_register_failed`, and not retried.
3. `configureNonUITestRuntime()` no longer registers or installs the delegate. It
   still attaches analytics and the review prompt, configures the refresh handler,
   schedules the next refresh, and tracks `appLaunched` — on every successful
   composition, including after recovery.
4. `RefreshScheduler.startRefresh` (extracted from `handleAppRefresh`): with no
   handler, finishes once with `false`, starts no work, and does not reschedule
   (breadcrumb `background_task_unconfigured`). With a handler, unchanged: schedule
   next, then run.
5. `NotificationRouting.discardBufferedNavigation()`; `resetLocalData` calls it right
   after a successful wipe (breadcrumb `notification_tap_discarded_after_reset`).
6. `RecoveryFixture` (DEBUG only; release compiles it out):
   - `-RecoveryFixtureOpenFailures N`: the first `N` compositions in the process
     throw, then they succeed, so the failure clears in the same process.
   - `-RecoveryFixtureCrashLoop`: launch shows crash-loop recovery.
   - Either argument switches to a disposable store at
     `Application Support/RecoveryFixture/default.store` (Reset removes only that),
     an isolated defaults suite for store-tied state (refresh watermark, catch-up
     marks, pause state), and skips clearing notifications on Reset
     (breadcrumb `recovery_fixture_notification_clear_skipped`).
   - `-RecoveryFixtureOpenFailures 0` opens the disposable store with no failure,
     for preparing fixture data.

## Recovery transitions (from `AppLaunchState`)

1. Initial persistence-open failure → `.persistenceFailure`: offers **Reset Local
   Data** only.
2. Crash-loop skip → `.crashLoop`: offers **Try Again** only.
3. Try Again (from crash loop) fails → `.persistenceFailure` (Reset offered).
4. Reset succeeds in removing the store, but composition fails →
   `.persistenceFailureAfterReset`: offers **Try Again** only.
5. Try Again (after reset) fails → stays `.persistenceFailureAfterReset`.
6. Reset fails to remove the store → stays in its previous kind with `resetError`;
   notifications and the buffered tap are kept.
7. Any successful retry or reset → `.ready`; `configureNonUITestRuntime()` runs once.

## Behavior matrix

| # | Scenario | Expected result | Source / owner | Verification |
| --- | --- | --- | --- | --- |
| 1 | Normal launch, store opens | Registered once in `init`; delegate installed there; handler configured; next refresh submission attempted after registration | Docs 1–3 | Simulator S1 (pending) |
| 2 | Crash loop → Try Again succeeds | No registration after launch; no crash; runtime configured once | Docs 1 | Simulator S4 (pending) |
| 3 | Persistence failure → Reset succeeds → store opens | Same as 2 | Docs 1 | Simulator S2 (pending) |
| 4 | Reset wipes, reopening fails → Try Again succeeds | Same as 2 | Docs 1 | Simulator S3 (pending) |
| 5 | Retry or reset fails again | Stays in recovery per transitions 3–6; nothing registered again | Existing | Automated, passed (`AppLaunchStateTests`) |
| 6 | Second registration call in one process | Ignored | Docs 1 | Automated, passed |
| 7 | Registration returns `false` | Fault + breadcrumb; not retried; no crash | Docs 1 | Automated, passed |
| 8 | Built app permits the identifier | Info.plist has the identifier and `fetch` | Docs 1 | Automated, passed |
| 9 | Task delivered with no handler (recovery) | Completes once with `false`; no work; not rescheduled (D3) | Docs 3; D3 | Automated, passed; device P1 (pending) |
| 10 | Same as 9, then the task expires | Still exactly one `false` completion | Docs 4 | Automated, passed; device P2 (pending) |
| 11 | Recovery succeeds, then a task is delivered | Configured handler runs the refresh | Docs 1, 3 | Device P3 (pending) |
| 12 | Notification tap cold-launches into recovery | Delegate installed in time; tap buffered; not tracked by analytics | Docs 2 | Simulator S5 and physical-device P4a (pending) |
| 13 | Tap buffered → Try Again succeeds | Opens the show once the coordinator attaches | Existing routing | Automated (failed retry keeps tap), passed; simulator S5 (pending) |
| 14 | Tap buffered → Reset wipes the store | Tap dropped, even if reopening fails (D2) | D2 | Automated, passed; simulator S6 (pending) |
| 15 | Tap buffered → Reset fails | Tap kept | Existing + D2 | Automated, passed |
| 16 | Two taps before the coordinator attaches | Latest kept; one slot, this process only | Existing routing | Automated, passed |
| 17 | Foreground notification while in recovery | Banner; review experience saved to the unattached store | Existing delegate | Code review |
| 18 | UI tests (`-UITesting`) | No registration or delegate, as before | Existing | UI suite (owner, pending) |
| 19 | Unit-test host launch | Registers once at host launch | Docs 1 | Unit tests ran (host launched, no crash) |
| 20 | Background refresh cold-launches into recovery | Registration succeeds; iOS delivers the task; it completes with failure and is not rescheduled | Docs 1, 3; D3 | Physical-device P4b (pending) |

## Automated results

November 5, iPhone simulator (Xcode `SKTesting` scheme, `SerialTesting` plan):
`LaunchRegistrationRecoveryTests` (9 new), `RefreshSchedulerTests`,
`AppLaunchStateTests`, `AppNavigationCoordinatorTests` — 43 passed, 0 failed. A
Release simulator build compiled. Full suite: pending (owner).

## Test installation

Use a dedicated simulator and, for device checks, a separate test installation
or a spare device without live NextSeason data. The fixture isolates the watchlist
store and store-related settings, and Reset skips notification cleanup. The
fixture still shares the installed app's notification center, pending background
refresh request, and launch-failure tracker. A fixture run can replace the
pending refresh request or clear the crash-loop streak for that installation.

For system-initiated launches in S5, S6, P4a, and P4b, confirm the newly started
process actually enters the requested fixture recovery state. Xcode's
wait-to-attach setting alone is insufficient evidence that the process received
the scheme arguments. If the fixture is inactive, leave the check pending until
a DEBUG fixture that survives an OS launch is available in the test installation.

## Simulator checks (owner)

Use the dedicated test simulator described above. In Xcode, choose **Product →
Scheme → Edit Scheme**, select **Run**, and open **Arguments**. Under
**Arguments Passed On Launch**, enable only the entries listed for the current
run. Stop the app before changing arguments. For S1–S4, leave **Run → Info →
Launch** set to **Automatically**. Open the Xcode console with **View → Debug
Area → Activate Console** and read the lines from the current run.

For S1 and S2, look for these messages in this order:

1. `breadcrumb background_task_registered`
2. `breadcrumb refresh_scheduler_configure`
3. Either `breadcrumb background_task_scheduled` or
   `background_task_schedule_failed` with the message **BGTaskScheduler is not
   available on this platform**. That error means the app asked to schedule a
   refresh and the simulator declined. The simulator check passes with either
   result. Successful scheduling is checked separately on a physical device.
   [Apple’s explanation of the scheduling error](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/error/unavailable)

Whenever a step says to reset, tap **Reset Local Data** on the recovery screen
and confirm in the pop-up. If offered **Reset Without Exporting**, choose it
for these tests.

### S1 — Normal launch

1. Enable only `-RecoveryFixtureOpenFailures 0` and run.
2. Confirm NextSeason opens normally and the console shows the three messages
   above in order.

### S2 — Reset succeeds

1. Enable only `-RecoveryFixtureOpenFailures 1` and run. The recovery screen
   should offer **Reset Local Data**.
2. Confirm the reset. NextSeason should open normally.
3. In the console, look for `recovery_fixture_notification_clear_skipped`,
   followed by `refresh_scheduler_configure` and either scheduling result above.
   `background_task_registered` should appear only once, before recovery.

### S3 — Reset succeeds, reopening fails, then Try Again succeeds

1. Enable only `-RecoveryFixtureOpenFailures 2` and run. The first recovery
   screen should offer **Reset Local Data**.
2. Confirm the reset. The next recovery screen should offer **Try Again**.
3. Tap **Try Again**. NextSeason should open normally, with only one
   `background_task_registered` message for the entire run.

### S4 — Crash-loop recovery

1. Disable `-RecoveryFixtureOpenFailures 2`. Enable only
   `-RecoveryFixtureCrashLoop` and run.
2. Tap **Try Again**. NextSeason should open normally.
3. Stop the app. Keep `-RecoveryFixtureCrashLoop` enabled and add
   `-RecoveryFixtureOpenFailures 1` as a second enabled entry. Run again.
4. Tap **Try Again**. This time the next screen should offer **Reset Local Data**.
   Confirm the reset and verify NextSeason opens normally.
5. Check that registration appears once per run.

### S5 — A notification tap survives Try Again

1. Set **Launch** to **Automatically**, enable only
   `-RecoveryFixtureOpenFailures 0`, and run. Add one show to the test watchlist
   and allow notifications if prompted.
2. In NextSeason’s **Diagnostics**, choose **Send Test Notification**. Stop the
   app in Xcode and leave the test notification available to tap.
3. Enable only `-RecoveryFixtureCrashLoop`. In Xcode, set **Run → Info → Launch**
   to **Wait for the executable to be launched**. Press **Run**, then tap the
   test notification in the simulator.
4. Confirm the notification opens the crash-loop recovery screen. Tap
   **Try Again** and verify NextSeason opens the show. If the notification
   opens the normal app directly, the recovery fixture did not take effect
   for this launch. Leave S5 pending.

### S6 — Reset discards a notification tap

1. Prepare a fresh test notification using S5 steps 1–2.
2. Repeat S5 step 3 with only `-RecoveryFixtureOpenFailures 1` enabled.
3. Confirm the notification opens the recovery screen with **Reset Local Data**.
   Confirm the reset. NextSeason should open without navigating to the show, and
   the console should show `notification_tap_discarded_after_reset`. If the
   fixture did not take effect, leave S6 pending.

After testing, disable the fixture arguments and restore **Launch** to
**Automatically**.

## Physical-device checks (owner)

The background-task debugger commands work only on a physical device, and
simulate delivery inside an already-running process, so they do not prove
cold-launch registration timing.

- **P1 — Task with no handler.** In the isolated installation, run once with
  `-RecoveryFixtureOpenFailures 0` and confirm `background_task_scheduled`.
  Then run with `-RecoveryFixtureOpenFailures 1` and stay on the
  recovery screen. Pause in the debugger and run:
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.TrialByFyre.NextSeason.watchlist-refresh"]`,
  then continue. Expect `background_task_started`, `background_task_unconfigured`,
  and no `background_task_scheduled`.
- **P2 — Expiration after P1.** Pause and run
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.TrialByFyre.NextSeason.watchlist-refresh"]`.
  Expect `background_task_expired` and no system error about completing twice.
  (If the system has already discarded the completed task, nothing happens; record
  that.)
- **P3 — Handler after recovery.** Continue from P1: Reset → the app opens
  (`background_task_scheduled`). Simulate a launch again. Expect `bg_app_refresh`
  start and complete.
- **P4a — Notification cold launch.** On a physical device, repeat S5 with the
  process stopped before tapping the test notification. Confirm that the tap
  starts a new process in crash-loop recovery and that Try Again opens the
  buffered show. Record registration and successful routing for that process.
- **P4b — Background-refresh cold launch.** On a physical device, start with a
  successfully submitted request in the isolated installation. With the app
  process no longer running and the recovery fixture ready for a system launch,
  wait for iOS to deliver the request. Confirm a new process enters recovery and
  logs `background_task_registered` before `background_task_started`, then
  `background_task_unconfigured` without a new submission. Record this result
  separately from P4a. If iOS has yet to deliver a task, keep P4b pending.

## Out of scope

- Crash-loop counter semantics (whether the old late-registration crash was counted).
- Switching to SwiftUI's `.backgroundTask(.appRefresh(_:))` scene modifier.
- Recovery-screen UI QA beyond these lifecycle checks (AM-04).

## Review status

- Independent design review: ChatGPT, November 5; findings 1–4 incorporated
  (deadline evidence → D1/P4a–P4b; taps after reset → D2, rows 13–16; rescheduling → D3,
  rows 9–11; corrected transitions and the `false` result → rows 7–8).
- Independent code review of the implementation completed. Acceptance remains
  pending simulator and physical-device verification.
recut 
