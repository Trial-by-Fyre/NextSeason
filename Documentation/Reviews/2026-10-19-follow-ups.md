# Follow-ups from the 2026-10-19 review fixes

These are open items from the notification-navigation and Search-retry fixes that are worth addressing later. Neither fix depends on them. Details and evidence are in the linked review records. Each item has a recommended priority; the owner decides scheduling.

The entitlement-ordering follow-ups are already recorded in [EntitlementCheckOrderingReview-2026-10-19.md](EntitlementCheckOrderingReview-2026-10-19.md#review-findings-and-disposition) and are not repeated here.

## Needs a product decision

1. **A notification can cancel a removal started on a Search detail.** Scenario: the user un-stars a show on a Search detail (deferred removal with Undo), then taps a notification for another unsaved show. Opening the new Search detail runs the existing "opening a detail cancels a pending removal" rule, so the first show stays saved. Decide whether notification-driven pushes should commit, or keep, a pending removal instead.
   Source: [NotificationSearchNavigationReview](NotificationSearchNavigationReview-2026-10-19.md), finding 4.

## Verification gaps

2. **Real-tap UI test: switching to Search with a pending removal (medium).** Scenario: leave a Search detail open, start a deferred removal on Watchlist, then tap the Search tab. Check that the show ends up removed rather than cancelled. The mounted tests pass, but they call the TabView binding's setter rather than tapping, and UIKit tap timing may differ. Note: the removal commit still runs in a task scheduled from `onChange`, as before the fix.
   Source: [NotificationSearchNavigationReview](NotificationSearchNavigationReview-2026-10-19.md), finding 1.
3. **Device check of notification taps for an unsaved show (medium).** On a physical device, while on Watchlist, check both a foreground tap and a background-return tap, with and without the Undo toast showing. Search detail should stay visible and any pending removal should be saved. This is separate from the deferred physical-device investigation.
4. **UI test for Try Again followed by typing (low).** The view-model tests cover this ordering, but no UI test does, and the UI-test search stubs can't hold a retry. Add one only if the stubs gain a way to hold a retry.
   Source: [SearchRetryOwnershipReview](SearchRetryOwnershipReview-2026-10-19.md), verification gap.

## Code follow-ups

5. **Resolve failures from an older Search query can still show an alert (low–medium).** The open/track paths in `SearchView` present resolve errors without checking that the query is still current, so a slow failure for an earlier query can raise "Something Went Wrong" over newer results. This predates the retry fix; use the same ownership approach if it is fixed.
   Source: [SearchRetryOwnershipReview](SearchRetryOwnershipReview-2026-10-19.md), finding 4.
6. **Profiling can report the wrong outcome when superseded (low).** If any newer search (for example Try Again) supersedes `runProfilingSearch`'s forced search, it returns the newer call's state or "did not reach a settled outcome". This only matters for profiling runs with manual interaction.
   Source: [SearchRetryOwnershipReview](SearchRetryOwnershipReview-2026-10-19.md), finding 3.

## Deferred from the October 21 Prompt 2 review

7. **Dynamic Type guidance visibility assertions (P3 — low priority, deferred).** `NextSeasonUITests/DynamicTypeUITests.swift`, `isFullyVisible` (lines 128–130 at review), checks hittability and the bottom edge against the tab bar but does not check the top edge. The no-results test targets the entire container, so a visible lower portion can satisfy the assertion while earlier guidance is above the viewport. Verify the beginning and end of the guidance separately, scrolling as needed, and check viewport containment for individual text or controls that fit. Do not require a taller-than-screen container to fit all at once. This is a confirmed test-coverage weakness, not a confirmed clipping defect in the current app. Deferred at Janine's request on October 21, 2026; no application or test changes made.

## Considered and not recommended

- **Superseded Try Again keeps using the network.** It still fetches its pages before the result is discarded. This costs resources but does not affect correctness. Cancelling the retry task would be a separate design change.
- **Stale Search detail can flash during a slow removal save.** The return-to-root waits for the save to finish, so with a slow repository the old detail can briefly show. The local SwiftData repository saves quickly; revisit only with remote or slower persistence.
