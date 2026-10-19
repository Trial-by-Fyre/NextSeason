# Search retry ownership — review record

**Feature:** An older Search operation (notably the Try Again button's uncancelled task) can no longer overwrite a newer query's results, failure, cursor, loading state, or mapping cache.

**Risk:** Medium (async ownership within Search; no persistence). Independent acceptance review performed.

**Status:** Implemented. Independent behavioral acceptance review: no blocking findings. Pending: full suite (owner-controlled).

## Ownership rule

1. Every `search()` call claims `searchRequestID` at entry. That includes typing, Try Again, clearing and profiling, and it happens before the empty-query path and before the debounce.
2. After the debounce, after the page fill, and on failure, the call changes nothing unless it is still the newest request. The post-debounce check matters: without it, an older call that wakes up sets `.loading` and is then rejected, leaving Search stuck loading.
3. `searchGeneration` still changes only when an outcome is replaced or cleared. `loadMore()` keeps using it, so the already-displayed shortcut does not discard an in-flight Load More.
4. Filtering no longer writes `resolvedTVMazeIDsByTVDBID` while suspended. The fill returns the mapped ids, and `search()`/`loadMore()` merge them only after their ownership check.

The debounce sleep is injectable (`sleep:`, defaulting to `Task.sleep`) so tests can hold a call inside it.

## Verification (2026-10-19, iOS 27 simulator)

- `SearchViewModelTests`: 36 pass, 8 of them new. The new tests cover:
  - a stale retry that succeeds, or fails, after a newer query;
  - clearing the field during a held retry;
  - stale mapping work and the cache;
  - a newer Load More while an older retry finishes;
  - retry after a failure;
  - a search still in its debounce being retired by clearing, or by a newer query.
- Focused UI tests: 7 pass. Six are in `SearchAndTrackUITests` (detail, Try Example, empty, retry state, tracked state, row star); the seventh is `NavigationUITests.testSearchTabReturnsToResultsAfterViewingDetailFromAnotherTab`, which covers the return-from-detail shortcut.
- Revert checks:
  - Removing the request checks failed all 5 stale-retry and Load More tests.
  - Restoring in-fill cache writes failed the two cache assertions.
  - Removing only the post-debounce check failed both debounce tests, leaving Search stuck on `.loading`.

**Verification gap:** the view-model tests start `Task { await viewModel.search() }`, the same code the Try Again button runs. No UI test covers Try Again followed by typing, or SwiftUI `.task(id:)` restart timing; the UI-test stubs cannot hold a retry.

## Review findings and disposition

1. Post-debounce check untested: **fixed** (debounce tests added).
2. A superseded Try Again still fetches pages and mapping rows before its result is discarded. **Accepted-limitation candidate:** it costs resources but does not affect correctness. Cancelling the retry task would be a separate design change.
3. If profiling's forced search is superseded, `runProfilingSearch` reports the newer call's outcome. This needs a Try Again tap during a profiling run. **Follow-up, low.**
4. A resolve failure from an older query can still raise the alert (`SearchView` open/track paths). This existed before and is outside this change. **Follow-up** if wanted.
