# TestFlight crash in RefreshScheduler

## User

We have a TestFlight crash in RefreshScheduler when a BGAppRefreshTask expires.

The crash occurs in the expirationHandler, which BackgroundTasks invokes on a non-main queue. The handler calls BackgroundRefreshCompletion.finish(success:), which ultimately calls BGAppRefreshTask.setTaskCompleted(success:). Swift 6 runtime executor checking traps because the BG task completion is being performed from the wrong executor.

Please make the smallest appropriate concurrency-safe fix.

Goals:

* Ensure handling of BGAppRefreshTask.expirationHandler hops explicitly to @MainActor before cancelling the work task and completing the BGAppRefreshTask.
* Make the main-actor requirement of BackgroundRefreshCompletion.finish(success:) explicit if appropriate, so the compiler enforces the requirement rather than relying on runtime executor checking.
* Preserve the existing Mutex-based at-most-once completion protection. Normal completion and expiration can race, and setTaskCompleted must still be called at most once.
* Do not redesign WatchlistRefreshService, SwiftDataWatchlistRepository, or the overall background-refresh architecture unless a change is genuinely required for correctness.
* Update comments so they accurately distinguish the main-queue BGTaskScheduler launch handler from the expiration handler, which may arrive on another queue.
* Add or update focused tests for expiration, cancellation, normal completion, and the race between expiration and normal completion if those behaviors can reasonably be tested.
* Review the resulting code under Swift 6 strict concurrency checking for any remaining unsafe assumptions around BGAppRefreshTask.

Also perform a narrowly scoped audit of other Apple/framework callback boundaries in production code for the same class of mistake: a callback that may arrive off-main and then directly accesses @MainActor state or another object with executor restrictions.

In particular, inspect:

* NotificationCenterDelegate
* TabBarReselectHandler
* any other delegate/handler callback supplied to an Apple framework

Do not make speculative refactors. TabBarReselectHandler already explicitly hops using Task { @MainActor in ... } and appears to be an example of the desired pattern. Only change another callback site if its current isolation is genuinely unsafe or ambiguous under Swift 6 strict concurrency checking.

Also flag, but do not automatically eliminate, any production uses of @unchecked Sendable. Currently BackgroundRefreshCompletion is the notable case; explain whether it is still necessary after the fix.

The relevant crash stack was:

BGTask _callExpirationHandlerWithReason:
→ RefreshScheduler.handleAppRefresh expiration handler
→ BackgroundRefreshCompletion.finish(success:)
→ Swift concurrency executor assertion
→ _dispatch_assert_queue_fail
→ EXC_BREAKPOINT (SIGTRAP)

Keep the fix and audit narrowly scoped to callback/executor correctness.

## Assistant

I'll start by reading the Swift concurrency and testing skills, then inspect the refresh-expiration path and related Apple callback sites.

Skills I'll use: `swift-concurrency-pro`, `swift-testing-pro`. Next I’ll load the refresh scheduler, completion helper, and related callback sites.

I'll inspect concurrency settings, existing tests, and other Apple callback sites so the fix stays narrowly scoped.

The crash matches implicit `@MainActor` isolation on `finish` being invoked from BackgroundTasks’ off-main `expirationHandler`. I’ll hop to the main actor before cancel/complete, make that requirement explicit, and add focused tests.

I'll build and run the new scheduler tests next, then finish the callback-boundary audit.

The `AsyncStream.first` predicates aren’t Sendable under Swift 6. I’ll switch those waits to continuations.

The crash was a Swift 6 executor trap: `BackgroundTasks` calls `expirationHandler` off the main queue, and that path completed the `BGAppRefreshTask` on the wrong executor.

Skills used: `swift-concurrency-pro`, `swift-testing-pro`.

## Fix

`finish(success:)` was already main-actor isolated (module default plus the runtime check). The expiration handler called it directly, which is what trapped.

Expiration now hops first, then cancels work and completes:

```89:111:NextSeason/Services/RefreshScheduler.swift
        // Expiration handler: BackgroundTasks may invoke this on a non-main
        // queue. Logging is nonisolated; cancel + `setTaskCompleted` must hop.
        refreshTask.expirationHandler = {
            AppDiagnosticsLogger.logger(for: .tasks).notice("background_task_expired")
            AppDiagnosticsLogger.breadcrumb("background_task_expired")
            handleExpiredAppRefresh(work: work, completion: completion)
        }
    }

    /// Safe to call from `BGAppRefreshTask.expirationHandler`, which
    /// BackgroundTasks may invoke on a non-main queue.
    nonisolated static func handleExpiredAppRefresh(
        work: Task<Void, Never>,
        completion: BackgroundRefreshCompletion
    ) {
        Task { @MainActor in
            work.cancel()
            completion.finish(success: false)
        }
    }
```

`BackgroundRefreshCompletion` is now explicitly `@MainActor`, and so is `finish(success:)`. The Mutex at-most-once guard is unchanged. Normal completion and expiration can still race; `setTaskCompleted` still runs at most once.

`@unchecked Sendable` is **no longer necessary** and was removed. Main-actor isolation already makes the type `Sendable`, so the `@Sendable` expiration handler can capture it. `BGAppRefreshTask` stays on the main actor and is only used from `finish`. The old annotation did not move work onto the main actor; it only silenced `Sendable` checking and helped hide this bug.

Comments now distinguish the main-queue launch handler (`using: .main`) from the expiration handler, which may arrive on another queue.

## Tests

`RefreshSchedulerTests` covers:

- Normal completion (second finish ignored)
- Expiration (second finish ignored)
- Cancellation, then a later success ignored
- Expiration vs normal completion racing (exactly one completion)
- Expiration invoked from a background queue, hopping to the main actor before complete/cancel

All 5 passed.

## Callback audit

No other production callback site was changed.

- **`NotificationCenterDelegate`** — Safe under current settings. The type is implicitly `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), and its async `UNUserNotificationCenterDelegate` methods call `@MainActor` `NotificationRouting` without `await`, which only compiles if those methods already share that isolation. No custom delegate queue is set, so the system delivers on the main queue. Isolation is implicit rather than spelled out; that is not currently unsafe.
- **`TabBarReselectHandler`** — Already hops with `Task { @MainActor in ... }`. Left as-is.
- **`StoreKitPurchaseStoreClient.observeTransactionUpdates`** — The observer `Task` is created from a `@MainActor` method. After `for await` on `Transaction.updates`, use of `self` hops back to the main actor for `checkVerified` / `deliverThenFinish`. Compiler-checked; no change.
- **`BGTaskScheduler` launch handler** — Already hopped with `Task { @MainActor in }`. Comments updated only.

Production `@unchecked Sendable` is gone. Remaining test-only uses (mocks, `NowBox`, `SleepBehavior`) were left alone. Unrelated `nonisolated(unsafe)` remains on `Aptabase.shared` and the SQLite `OpaquePointer`; those are not this callback/executor bug.

## Remaining BG task assumption

`setTaskCompleted` is treated as main-actor work because registration uses `using: .main`. The SDK does not express that as strongly as the runtime check enforces. Completing via `Task { @MainActor in }` is an async hop, so the expiration closure returns before `setTaskCompleted` runs. That is required from a sync off-main callback; the Mutex still prevents a double complete if the work task finishes first.

## What to test

- Background refresh still completes normally and schedules the next request.
- If you can expire a `BGAppRefreshTask` (debugger: `_simulateLaunchForTaskWithIdentifier`, then let the system expire it), the app should no longer trap. The new unit test already exercises the off-main hop.

