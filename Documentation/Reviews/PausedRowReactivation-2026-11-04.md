# Paused Watchlist Row Reactivation — November 4, 2026

## Goal

A free user can tap a paused Watchlist row to track that saved show again when
one of the three active slots is open. At capacity, the tap opens the existing
Plus paywall and changes nothing.

## Risk classification

**High.** The change is small and reuses existing paths, but it crosses the
free-tier cap (access), persisted pause state, and notification catch-up, with
asynchronous races (network fetch, entitlement resolution, undoable removal).
A mistake could exceed the free cap, resurrect a deleted show, or announce
months-old changes.

## Product decisions (owner, in the task)

1. Free users track up to three active shows.
2. Deleting an active show leaves the slot empty; no automatic promotion.
3. A slot is filled by adding a different show or tapping a paused row.
4. Other paused shows stay saved and paused.
5. Tapping a paused row reactivates it; it never opens Show Details.
6. The star keeps its existing removal behavior.
7. At capacity, the tap uses the existing Plus paywall without changing the row.
8. An uncommitted (deferred) removal does not free a slot.

## Platform/code facts verified in the repository

- `WatchlistTracking.add` is the shared admission path: initial capacity check
  (waits for the first entitlement read), detail fetch, then a final,
  non-suspending capacity check before `repository.add`.
- `repository.add` reactivates a paused row in place (`TrackedShow(reactivating:)`):
  fresh show data, original `dateAdded`, original `lastNotifiedSignature`,
  pending debounce cleared. No duplicate.
- `TVMazeService.show(id:)` uses `bypassCache: false`; `TVMazeClient` can serve an
  hour-old cached body, and `TrackedShow(reactivating:)` keeps the pre-pause
  `lastNotifiedSignature`. A reactivated row can therefore hold stale status
  that the next refresh would announce as new. This is why `repository.add`
  alone is not sufficient protection; catch-up re-fetches with `bypassCache: true`.
- The reconciler's resume path calls `WatchlistRefreshService.markForCatchUp`
  before persisting, then `catchUp(showIDs:)` without awaiting it. Marks are
  keyed by `dateAdded`, so reactivation (same `dateAdded`) keeps a mark valid and
  a delete-and-re-add (new `dateAdded`) makes it inert and pruned.
- Existing Search/Detail reactivation of a paused show does **not** mark for
  catch-up. Out of scope here; reported as a follow-up.

## Design (as implemented, after design review)

- `WatchlistTracking.add` gains an opt-in reactivation mode
  (`reactivating: pausedRow`, `willReactivate:`). At the final admission check it
  re-reads the stored row and writes only if that row is still saved, paused,
  and has the same `dateAdded`; otherwise it returns `.ignored`. Then the cap is
  checked, `willReactivate` runs, and `repository.add` writes, with no
  suspension between check and write. Defaults leave Search and Detail unchanged.
- `WatchlistViewModel.reactivate(_:…)` first re-reads the stored row (skipping
  the fetch if it was deleted or resumed), then runs the shared `add` with
  `willReactivate: markForCatchUp([row])`. Only `.added` from that mode reloads
  (the row moves into its status section) and starts `catchUp(showIDs: [id])`
  unawaited, followed by another reload. `.paywallRequired` calls the view's
  paywall closure; `.ignored` reloads; a thrown error (not cancellation)
  records a retryable failure alert.
- Per-show in-flight set, held until the post-write reload finishes: repeat
  taps are ignored; the star shows progress (disabled); swipe-delete
  (`.deleteDisabled`), star removal, and the rotor delete are ignored.
- Paywall unlock retries the reactivation; the stored-row pre-check makes it a
  no-op without a fetch once the reconciler has resumed everything.
- Paused row is a plain `Button` with full-width content shape (no
  `NavigationLink`); the star stays a separate borderless button. A paused row
  with its own pending star removal keeps the existing Undo-only branch.
- VoiceOver: hint explains reactivation and the at-capacity paywall; the
  "Remove from watchlist" action remains; success is announced because the row
  moves to another section.
- Copy: header "Paused"; description names both options (open free slot or
  renew Plus); paused row label "Not being tracked" replaces "NextSeason Plus
  required". The Watchlist now attaches the shared post-add notification prompt.

## Behavior matrix

| # | Scenario | Expected result | Source | Verification |
| --- | --- | --- | --- | --- |
| 1 | Free, 2 active, 2 paused; tap paused A | A active in its status section; B still paused; 4 saved rows; A keeps `dateAdded` | Owner | Unit |
| 2 | Free, 3 active; tap paused A | Paywall callback; no detail fetch; A paused; no catch-up mark | Owner | Unit |
| 3 | Delete active show (swipe) | Slot empty; no paused show promoted on reload/reconcile | Owner | Unit (existing + VM) |
| 4 | Tap A twice quickly | One fetch, one write; second tap ignored | Task | Unit |
| 5 | Tap A and B with one slot, both fetching | First to persist wins; other gets paywall; active ≤ 3 | Task | Unit |
| 6 | Tap A; during fetch a Search add fills the slot | Reactivation returns paywall; A paused; no mark | Task | Unit |
| 7 | Deferred (star) removal pending on active show; tap A | Paywall; A paused | Owner #8 | Unit |
| 8 | Swipe-delete active X; tap A (fills slot); Undo X | X restored **paused**; active stays 3 | Existing restore | Unit |
| 9 | Detail fetch fails (offline) | A stays paused; retryable failure alert; retry succeeds | Task | Unit |
| 10 | `repository.add` throws | A stays paused; failure alert; no duplicate | Task | Unit (throwing repo) |
| 11 | Entitlement still loading at tap | Waits for first read, then decides | Existing admission | Unit |
| 12 | Plus confirmed during operation | Reconciler resumes all; reactivation is an idempotent no-op | Existing | Unit (Plus restore) |
| 13 | Status changed while paused; reactivate; catch-up | Catch-up baselines silently: no notification; a later genuine change notifies | Task | Unit |
| 14 | Refresh reaches A before catch-up | Mark makes it a silent baseline | Existing mark | Covered by mark semantics + #13 |
| 15 | Continuously active show changes during the same period | Still notifies normally (catch-up limited to A) | Task | Unit |
| 16 | Plus restored afterwards | Remaining paused shows resume and are marked | Existing | Unit |
| 17 | User swipes A while its reactivation is in flight | Delete disabled for that row; no resurrection | Design | Manual (UI) + VM guard unit |
| 18 | Tap paused row | No Show Details push | Owner #5 | UI test |
| 19 | Tap star on paused row | Existing deferred removal; row not reactivated | Owner #6 | UI test |
| 20 | VoiceOver | Row is a button with a reactivation hint; "Remove from watchlist" action remains | Task | Manual VoiceOver check; UI test for button |
| 21 | Copy | Header/description describe free slot or Plus; no "Plus required" only | Task | UI test (header text) |
| 22 | Mark left if the write throws after `willReactivate` | Mark stays on a paused row: inert while paused; a later reactivation gets a silent baseline, which is desirable | Design | Reasoned |
| 23 | Row deleted elsewhere (e.g. Search) during the fetch | `.ignored`; no re-created row; no mark | Design review #1 | Unit |
| 24 | Row resumed elsewhere during the fetch | `.ignored`; no unmarked catch-up | Design review #2 | Unit |
| 25 | Paywall retry after Plus resumed the row | No-op without a fetch | Design review #3 | Unit |

## Verification (November 4, 2026)

Environment: Xcode, `SKTesting` scheme, `SerialTesting` plan, simulator.
Focused runs only; full suite pending (owner).

- `WatchlistPausedReactivationTests`: 16/16 passed (matrix rows 1–13, 15, 16,
  23–25; 17 via the view model guard). Rows 13–16 use a stub that serves a stale
  cached body to the add path and fresh data to refreshes.
- `PausedWatchlistUITests`: 3/3 passed (rows 18, 19, 21, row-is-a-button part of 20).
- Related existing suites (`WatchlistAdmissionTests`, `SubscriptionDowngradeTests`,
  `WatchlistTrackingTests`, `WatchlistViewModelTests`,
  `SubscriptionDowngradeRefreshTests`): all passed except
  `WatchlistTrackingTests/deferredRemovalStillCountsForAdmission`, which failed
  with `.added`. That test built `PurchaseService` with the default
  `PlusEntitlementStore()` (`UserDefaults.standard` + Keychain complimentary
  persistence). Resolved: the test now injects isolated defaults and
  `MemoryComplimentaryPlusPersistence`, with a free-access precondition, and
  passes. Only the entitlement storage changed, confirming shared simulator
  state made it unlimited. `WatchlistPendingRemovalTests` still uses the
  default store in two places (not failing; follow-up).
- Manual, pending: VoiceOver reading and announcement (row 20), swipe disabled
  while in flight (row 17), paywall at capacity in a non-UI-test build (row 2;
  `presentPlusStore` is nil under UI tests).

## Independent reviews

Design review (before implementation): 2 blocking, 3 should-fix, 4 minor.
- Blocking 1 (resurrection of a row deleted elsewhere) and 2 (unmarked catch-up
  after an idempotent `.added`): fixed by reactivation mode; rows 23–24.
- Should-fix: paywall retry guard (fixed, row 25); catch-up rationale (corrected
  above); List button styling, `.deleteDisabled`, Undo-only pending branch,
  VoiceOver announcement (implemented).
- Minor: busy until reload (implemented); cancellation silent (implemented);
  analytics counts reactivation as `watchlistAdded(source: .watchlist)` (kept,
  same as Search/Detail; owner to confirm); Search/Detail catch-up gap (follow-up).

Acceptance review (after implementation): no blocking findings.
- Fixed: entitlement-wait test now holds the StoreKit read and asserts the tap
  waits; star UI test now confirms the row is still paused after a delay; Plus
  restore test now asserts the remaining show is marked; this record updated.
- Testing documents (done in this change): the beta regression test and
  checklist, StoreKit manual test script and checklist (SK-13),
  `FreeTierSimulation.md`, and the developer QA acceptance doc now use the
  "Paused" heading and describe the tap (reactivate into an open slot, or Plus
  at capacity). The generated `NextSeason Beta Regression Checklist.pdf` needs
  regenerating. The Roadmap's historical styling report is unchanged.
- Owner decisions (November 4): reactivations count as adds in analytics
  (`watchlistAdded(source: .watchlist)`); a removal still in its Undo window
  has not freed a slot, so the tap opens Plus.
- Follow-up (separate change): Search and Show Details reactivation of a paused
  show does not mark it for catch-up, so notification protection differs by
  entry point. Reactivating the same show should be protected the same way
  everywhere (the `reactivating:`/`willReactivate:` mode is available to reuse).
- Remaining accepted-limitation candidates (owner): failure copy mentions connection even for a persistence failure; no
  announcement when a purchase resumes everything; lapse alert copy unchanged;
  a pending star removal makes the tap open the paywall during the undo window;
  the row stays busy while the first entitlement read is pending.

## Out of scope

- Catch-up marking for Search/Detail reactivation (follow-up).
- The "Some Shows Are Paused" alert text ("Renew Plus to reactivate them"):
  shown when all free slots are full, so it is accurate at that moment.
- Changing how deferred removals count toward the cap.
