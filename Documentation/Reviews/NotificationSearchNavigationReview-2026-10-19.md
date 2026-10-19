# Notification → Search detail navigation — review record

**Feature:** With Watchlist selected, a notification for an untracked show switches to Search and leaves that show's detail visible; manual selection of Search still returns it to root.

**Risk:** Medium, with independent acceptance review (async tab side effects interact with pending-removal persistence).

**Status:** Implemented. Independent behavioral acceptance review: no blocking findings. Pending: full suite (owner-controlled), device check.

## Root causes (mounted reproduction)

`ContentView` was hosted in a window in the app-hosted unit test target (not XCUITest):

1. The tab-change task popped Search whenever the tab became Search, clearing the detail notification routing had just pushed (path 1 → 0).
2. With a deferred Watchlist removal pending, the pushed Search detail's `onAppear` (`dismissPendingRemovalForNavigation()`) **cancelled** the removal before the tab-change commit ran.

## Ordering rule

1. `TabView` writes through a custom binding whose setter (`selectTabFromTabBar`) records a manual Search selection. Programmatic routing assigns `selectedTab` directly.
2. The tab-change task still commits the pending removal first, then calls `finishManualSearchSelection()`. That pops only for a recorded manual selection, and only if notification routing has not pushed a Search detail since (`searchRoutingGeneration`).
3. Before the Search fallback leaves Watchlist, it calls `willLeaveWatchlist` synchronously. Production passes `confirmPendingRemoval()`, so the commit begins before the pushed detail can cancel it.

**Rejected:** popping synchronously in the setter. The mounted test showed the stale Search detail then re-appeared and cancelled a pending removal; the original pop-after-commit timing did not.

**Assumption:** `TabView` calls the selection binding's setter only for user selection. `NavigationUITests.testSearchTabReturnsToResultsAfterViewingDetailFromAnotherTab` (real tab taps) covers it.

## Verification (2026-10-19, iOS 27 simulator)

- `ContentViewNotificationNavigationTests` (8, mounted): passing. They cover foreground and background-return taps, the pending-removal commit (checked through SwiftData), manual return to root, a suspended commit with a newer notification, superseded lookups, and tracked/paused targets.
- Four new `AppNavigationCoordinatorTests`, plus the existing `AppNavigationCoordinatorTests`, `WatchlistPendingRemovalTests`, `SubscriptionDowngradeTests` and `NavigationUITests`: passing.
- Revert checks: restoring the original pop failed both primary tests and the suspended-commit test (path 0). Removing `willLeaveWatchlist` failed the removal test.

## Review findings and disposition

1. Manual real-tap timing with a stale Search detail and a pending removal: the commit still runs in a task scheduled from `onChange`, the same as before this change. It passed in the mounted test, but a real tap was not tested with a removal pending. **Follow-up** (UI test).
2. A slow repository could briefly show the stale Search detail before the pop, as before. **Follow-up.**
3. The superseded-lookup test could pass vacuously: **fixed** (it now waits for the held lookup to return).
4. A notification that pushes Search detail cancels a deferred removal started from a Search detail (existing push-cancels rule). Notification routing out of Watchlist now ends the undo window. **Product decision for owner.**
5. `ProfileFlowRunner` programmatic `selectedTab = .search` no longer pops Search, which removes a race with its own pushes. **Not applicable.**

## Remaining manual checks

On a device: foreground and background-return notification taps for an untracked show while on Watchlist, with and without the undo toast showing.
