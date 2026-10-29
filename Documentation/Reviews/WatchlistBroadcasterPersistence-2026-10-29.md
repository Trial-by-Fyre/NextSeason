# Watchlist broadcaster names — acceptance record (2026-10-29)

**Status:** implemented; focused tests pass; independent design and acceptance reviews done. Full suite and on-device checks pending.

## Behavior

Watchlist rows name the stored TVMaze broadcaster, without country: "Season 20 airing on CBC Gem" and "Season 21 premieres Jan 1, 2027 on CBC". Without a broadcaster they read "Season 20 currently airing" and "Season 21 premieres Jan 1, 2027". Other statuses, paused rows, CSV export, notifications, status calculation and Show Detail are unchanged.

`broadcasterName` (optional) was added in place to the V1 SwiftData model, by product-owner decision (pre-release exception, no V2 or migration plan). It is set from `Show.network` on add and reactivation (`TrackedShow.init(from:)`) and on every refresh that applies a fetched show. It is preserved by pause, undo and undelivered-notification restore. It is display-only and not part of change detection.

## Key invariants

1. A store must never open empty or with rows missing.
2. A change to the broadcaster alone never notifies or blocks a notification.
3. A failed, skipped or out-of-order refresh leaves the stored broadcaster unchanged.

## Platform evidence

SwiftData does not document inferred migration when the version identifier is unchanged. On the simulator, both directions opened with every row and field intact, with no entity-conflict warnings:

1. A store written by the pre-change model, opened by the new model, keeps every row with `broadcasterName` nil.
2. A store written by the new model, opened by the old model, keeps every row.

`PreBroadcasterStoreCompatibilityTests` pins this. It fails if either direction stops opening, so a platform change gets noticed. It has not been verified against a store written by a shipped TestFlight binary on a device. The supported path remains delete and reinstall, documented in the beta regression guide, its checklist, and Developer QA AM-04.

## Verification

All of these passed on the simulator:

1. `WatchlistBroadcasterPersistenceTests` covers add, add without a broadcaster, pause/resume, reactivation, undo, refresh write including nil, and undelivered restore, each against both SwiftData and in-memory repositories.
2. The refresh tests appended to `WatchlistRefreshServiceTests` cover a silent update and its removal, a failed fetch, a skipped unchanged show, and returning → scheduled filling the broadcaster.
3. `WatchlistStatusWordingTests` covers airing and scheduled rows with and without a broadcaster, blank names, other statuses, paused rows and CSV.
4. `PreBroadcasterStoreCompatibilityTests` covers the old store opening under the new model, recovery export reading a store without the new column, and the downgrade direction.
5. `NextSeasonSchemaTests` was updated for the new attribute.
6. The existing repository, rollback, recovery-export, pending-removal, delivery-retry, status-change, CSV and Show Detail wording suites still pass.

## Reviews

The independent design review found no blocking gaps. These suggestions were adopted:

1. full-fidelity legacy and downgrade tests
2. tester-doc reconciliation
3. setting the field in `TrackedShow.init(from:)`
4. a shared display helper
5. removing the obsolete string

The independent acceptance review found nothing blocking. These follow-ups were fixed:

1. walkthrough test 1 and Developer QA AM-04 notes
2. the compatibility tests now record a failed open as an issue

## Limitations and assumptions

1. The broadcaster is show-level (`network`, falling back to `webChannel`), not season-specific. A season that moves to another service may name the old broadcaster until TVMaze updates the show. Show Detail behaves the same way.
2. If an old store does open in place, existing rows show generic wording until their next fetch. Airing and scheduled rows are re-fetched on every refresh. Other statuses don't display a broadcaster.
3. A broadcaster-only change updates the row text without the list animation, which is keyed on `headline`.
4. The tester note's build number still needs to be filled in. `NextSeason-Beta-Regression-Fillable.pdf` was not updated.
