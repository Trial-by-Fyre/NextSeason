# R08 and R11 behavior matrix

Status: design revised after independent design review (2026-10-13), including the clock-reset exception. Product decisions approved by the product owner (2026-10-13). Final design check found one issue (finding 6), resolved and confirmed by the design reviewer (2026-10-13). Approved for implementation. **Implemented 2026-10-13.** Acceptance review found findings 7–8, now resolved; **acceptance re-review pending.** Scenario 17 relies on existing paused-show tests; scenario 26 is covered by the existing capped-sync resume test with the margin applied; all other scenarios have new or updated unit tests.

Risk: **High.** Changes what background refresh fetches, adds a persisted sync watermark, depends on externally controlled TVMaze behavior, and decides whether users get notified after long absences.

## Facts

Verified in code:

1. **Watchlist refresh window (R11).** `WatchlistRefreshService.refreshAll` picks `day`/`week`/`month` from the oldest active row's `lastCheckedAt` and never requests the unfiltered map.
2. **Skipped rows never advance `lastCheckedAt`.** Rows filtered out by the updates map are not written. For a stable `.ended`/`.announcedUndated`/`.unknown` row, `lastCheckedAt` ages even when the app refreshes daily. So "oldest `lastCheckedAt`" cannot tell a long absence from a stable row, and switching to the full map on that basis would download it on almost every refresh. **R11 needs its own watermark.**
3. **The change check already works with a full map.** `serverChanged` compares the map's timestamp with the row's `sourceUpdatedAt`.
4. **Not every handled row proves coverage.**
   - A per-show fetch failure leaves the row untouched.
   - The not-found path writes the stale flag with `try?`, so a failed write is silently ignored.
   - A response older than the stored row is skipped without a write.
5. **Overlapping refreshes.** Refreshes can overlap today (both on the main actor, interleaving at `await`s). The planned R03 change serializes refresh work per show, so a pass may skip or join a show another refresh is handling.
6. **Mapping sync (R08).** `ShowIDMappingRefreshService.fetchUpdates` evaluates both `requiresUnfilteredUpdateMap` and `covering` at the frozen `horizonAt`, not at request time. `pendingUpdates` correctly filters to (`lastSync`, `horizonAt`]. Completion sets `lastSuccessfulSyncAt = horizonAt`.
7. **TVMaze timestamps are last-updated only.** A show that changed again after the horizon is excluded from the current sync and picked up by the next one.
8. **Background and forced refreshes.** Background refresh is a `BGAppRefreshTask` (~12 h cadence); foreground refresh runs on scene activation. Pull-to-refresh and catch-up (`onlyShowIDs`) are `force: true` and skip the updates map.
9. **The month threshold is shared.** `TVMazeUpdatePeriod.monthWindow` (30 days) is used by both services.

From documentation:

1. TVMaze `/updates/shows`: `since` accepts only `day`, `week`, `month`. The unfiltered endpoint lists every show with its last-updated timestamp. Updating any child marks the show updated. ([TVMaze API](https://www.tvmaze.com/api#show-updates))
2. TVMaze: all API output is cached up to 60 minutes; allow up to an hour for changes to propagate. ([TVMaze API](https://www.tvmaze.com/api))
3. TVMaze: at least 20 calls per 10 s per IP; back off on 429. ([TVMaze API](https://www.tvmaze.com/api))
4. Apple: a `BGAppRefreshTask` gets up to 30 s of runtime. ([Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app))

Measurements and assumptions:

1. **Exact length of `since=month`: not documented.** The 28-day threshold is a conservative assumption, not a verified fact.
2. **Unfiltered map size** (design reviewer's live measurement, 2026-10-13): 711,747 bytes compressed, 1,708,965 bytes decoded, 1.46 s. This supports feasibility within the background budget but does not guarantee completion time.
3. **`show(id:bypassCache: true)`** bypasses the local cache only, as far as the code shows; TVMaze's CDN cache may still apply.

## Design

### R11: watchlist coverage watermark

Persist `watchlistUpdatesCoveredThrough` (UserDefaults, like catch-up marks). Meaning: every TVMaze change up to this time is reflected in every active saved row.

**Window choice** (non-forced passes). Let gap = request time − watermark:

- ≤ 1 day → `day`
- ≤ 7 days → `week`
- ≤ 28 days → `month`
- otherwise → full map

Use the full map also when there is no watermark or the watermark is in the future.

**Coverage rule.** A non-forced pass with request time T and map M may advance the watermark only if, when it is about to write, every active row (re-read from the repository at that point) is covered. A row is covered when any of these holds:

1. M has no entry for it.
2. Its persisted `sourceUpdatedAt` ≥ M[id] (the stored data is at least as new as the change the map reported). This covers rows updated by this pass, by an overlapping pass, or by a catch-up baseline.
3. It is persisted as stale (`isStale`) **and this pass itself successfully saved that stale flag**. A stale flag from an earlier pass is never evidence; its `lastCheckedAt` cannot be trusted, since after a clock reset it may be in the future (acceptance finding 7).

Consequences:

- Failed fetches, failed or ignored writes, skipped older responses, and shows another refresh is still handling all leave a row uncovered. The pass then leaves the watermark unchanged.
- A skipped busy show is never counted as covered. The pass doesn't wait for the other refresh; it simply doesn't advance unless the persisted row already proves coverage.

**Writing the watermark:**

- Check cancellation after the verification read and immediately before the write. The read is the last suspension point, and the write follows synchronously on the main actor with no `await` in between.
- New value = max(current, T − 1 hour). Normally it never moves backward, so an older pass finishing late cannot regress it, and the hour allows for the CDN cache.
- **Clock-reset exception.** The test is "later than the current clock", not "later than this pass's request time".
  - At window choice, a saved watermark later than the request time is untrustworthy (for example, the device clock moved backwards), so the pass uses the full map.
  - At write time, the pass compares the saved watermark with the clock at that moment. If the watermark is later than the current clock, it is genuinely in the future: replace it with T − 1 hour instead of taking the max. Otherwise keep the max rule.
  - A watermark written by a newer, overlapping pass is that pass's T − 1 hour, so it is never later than the current clock. An older pass finishing later therefore keeps it (scenario 16) rather than mistaking it for a clock reset.
  - If a pass that started before a reset finishes afterwards, it may write a future value again. That is self-correcting: the next pass sees a watermark later than its request time, uses the full map and replaces it. A future watermark therefore always triggers a full map rather than narrowing the window, so it cannot cause a missed change.
- Only non-forced passes advance it. Forced passes (pull-to-refresh, catch-up) never do. Foreground refreshes are frequent enough to advance it.

### R08: mapping sync window

- In `fetchUpdates`, choose `requiresUnfilteredUpdateMap`/`covering` from request time (`now()`) against `lastSync`. Keep `horizonAt` for `pendingUpdates` filtering, resume cursors, and completion.
- **One-hour margin, applied at completion.** Set `lastSuccessfulSyncAt = horizonAt − 1 hour` instead of `horizonAt`. The next sync then re-checks the final hour before the horizon, catching changes the CDN had not yet published. `applyMapping` is idempotent, so re-checking only costs requests.
- Because the margin is applied at completion, **in-progress syncs saved by an older build need no transition rule.** Their saved horizon, cursor, and pending set are unchanged, and they gain the margin when they complete.

Shared: change the month threshold to 28 days for both services (assumption 1).

## Behavior matrix

Each scenario is verified by a unit test with fake TVMaze and repository doubles unless noted.

R11, watchlist refresh:

1. **Regular use** (refreshes every few hours): `day` window; watermark advances to T − 1 h. Source: design.
2. **Stable row, app used daily**: an `.ended` row unchanged for 90 days still gets the `day` window; no full map. Source: fact 2.
3. **Review R11 regression**: a 90-day-old undated row whose show changed 40 days ago, on the first launch since. Full map requested; the row is fetched and updated; watermark advances. Source: review R11.
4. **Window boundaries**: gap exactly 1 day → `day`; 1 day + 1 s → `week`; exactly 7 days → `week`; 7 days + 1 s → `month`; exactly 28 days → `month`; 28 days + 1 s → full map. Source: design, assumption 1.
5. **First run after upgrade** (no watermark): full map once; watermark set if every row is covered. Source: design.
6. **One show fetch fails**: other shows are updated; watermark unchanged; the next pass's gap, and so its window, grows. Source: coverage rule.
7. **Not-found show, stale write fails**: the ignored write leaves the row uncovered; watermark unchanged. Source: fact 4, design review finding 2.
8. **Not-found show, stale write succeeds**: row covered (this pass saved the stale flag); watermark advances. Source: coverage rule.
8b. **Earlier pass's stale flag, dated in the future after a clock reset**, with a newer map entry and a failed fetch: row uncovered; watermark unchanged. Source: acceptance finding 7.
9. **Older response skipped**: the row is covered only if its persisted `sourceUpdatedAt` already reaches M[id]; otherwise the watermark is unchanged. Source: fact 4.
10. **Overlapping refresh owns a show and then fails**: this pass skips or joins the show, sees it uncovered at verification, and leaves the watermark unchanged. The owning refresh's failure also leaves it unchanged. Source: design review finding 1. Verify: test with a gated TVMaze double that fails the owning fetch.
11. **Overlapping refresh owns a show and succeeds first**: the persisted `sourceUpdatedAt` reaches M[id], so the row is covered. Source: coverage rule.
12. **Cancelled immediately before the watermark write**, in a pass that skipped every unchanged row: watermark unchanged. Source: design review finding 2. Verify: repository double that cancels during the verification read.
13. **Background task expires mid-pass**: the pass is cancelled during a held show fetch; it reports no outcome and the watermark is unchanged; the next foreground refresh retries. Source: fact 8, Apple doc 4, acceptance finding 8. Verify: test cancelling during a held fetch.
14. **Full-map request fails** (network, 429): refresh reports failure as today; watermark unchanged. Source: existing behavior.
15. **Pull-to-refresh and catch-up** (forced): watermark never advances. Source: design.
16. **Older pass finishes after a newer one**: pass A starts; pass B starts more than an hour later, covers every row and saves T_B − 1 h; then A finishes. B's watermark is later than A's request time but not later than the current clock, so A keeps it (max) rather than resetting it backwards. Source: design, design review finding 6. Verify: test with a gated TVMaze double and an injected clock, with the passes finishing in reverse order.
17. **Paused shows**: excluded from window and coverage, as today; when resumed they get catch-up baselines. Source: existing behavior. Verify: existing tests.
18. **Change found after a long absence**: evaluated normally, with existing debounce and deduplication. Source: product decision 1.
19. **Change in the last hour before a refresh** (CDN cache): not seen this pass; the watermark is set an hour back, so the next pass's window includes it. Source: TVMaze doc 2.
20. **Device clock moved backwards** (watermark later than request time): full map; if every row is covered, the watermark is replaced with T − 1 h, an exception to the max rule. Source: design, design review finding 5.
21. **Clock moved backwards while a pass was running**: the clock moves back three days during a held fetch; the pass writes a value later than the reset clock; the next pass uses the full map and replaces it. No change is missed. Source: design, acceptance finding 8. Verify: test resetting the clock during a held fetch.

R08, mapping sync:

22. **Review R08 regression**: a capped sync started with a 1-hour gap and resumed 2 days later. The resume requests `week`, and all three mappings are written before completion. Source: review R08.
23. **Resumed more than 28 days after `lastSync`**: full map on resume. Source: design.
24. **Show updated again after the horizon**: skipped now, processed by the next sync. Source: fact 7.
25. **Change in the final hour before the horizon** (CDN cache): completion stores horizon − 1 h, so the next sync re-checks that hour and applies the change. Source: product decision 2, TVMaze doc 2.
26. **In-progress sync saved by an older build**: resumes with its saved horizon and cursor unchanged; completion applies the margin. Source: design review (transition rule).
27. **Window boundaries**: same day/week/28-day cases as scenario 4, evaluated at request time. Source: assumption 1.

## Product decisions (approved by the product owner, 2026-10-13; design reviewer concurred)

1. **Notify normally after a long absence**, keeping existing debounce and deduplication.
2. **Include the one-hour mapping margin**, applied at completion as above.
3. **Allow the full map in background runs.** If the 30 s budget runs out, the watermark stays put and foreground retries.

## Design review findings and resolutions

1. **High: a skipped or unfinished show must not count as covered.** Resolved by the coverage rule: verify persisted rows at write time, so a pass never advances on another refresh's unfinished work. Pull-to-refresh no longer advances the watermark. Scenarios 10–11.
2. **High: "no per-show failures" needs a definition.** Resolved by the three-way coverage definition, which ignores in-memory success flags. Scenarios 7–9 and 12.
3. **Mapping margin transition for in-progress horizons.** Resolved by applying the margin at completion. Scenario 26.
4. **28-day month is an assumption.** Recorded as such; boundaries tested in scenarios 4 and 27.
5. **Watermark that only moves forward conflicts with clock-reset recovery** (re-review note). Resolved by the clock-reset exception: a watermark later than the request time is replaced, not kept. Scenarios 20–21.
6. **Medium: an older pass could mistake a newer pass's watermark for a clock reset** (final check). Resolved by comparing the saved watermark with the current clock at write time; the max rule applies otherwise. Scenario 16.
7. **P2: an earlier pass's future-dated stale flag could prove coverage** (acceptance review). Resolved: a stale row counts only when this pass saved its stale flag. Scenario 8b.
8. **P2: scenarios 13 and 21 were not exercised as described** (acceptance review). Resolved by tests that cancel during a held fetch and reset the clock while a pass is running.

## Out of scope

- "Updated …" on watchlist rows shows `lastCheckedAt`, which skipped stable rows never advance, so it can look stale. Separate follow-up.
- R03/R13 (notification retry, snapshot repair) and R12 (refresh outcome reporting). The coverage rule is designed to stay correct once R03 adds per-show serialization.
