# Analysis of the October 12, 2026 feature-area review

This is a second opinion on [2026-10-12-feature-area-review.md](2026-10-12-feature-area-review.md). It comments on the findings and their recommended fixes. It is not an implementation specification, and no application code was changed.

## Verification performed

Seven findings were checked directly against the code: R01, R02, R03, R04, R05, R10, and R15. All seven are accurate, including their cited locations. The remaining findings were not independently checked; their assessment below relies on the review's own evidence.

1. **R01:** confirmed. Every `SwiftDataWatchlistRepository` mutation changes the context and then calls `try context.save()`, with no rollback on failure.
2. **R02:** confirmed. `TVMazeDate.dateOnly` produces midnight UTC, while `NextSeasonStatus.headline` formats with the device time zone, so dates west of UTC appear one day early.
3. **R03:** confirmed. `WatchlistRefreshService` saves the evaluated row (including `lastNotifiedSignature`) before calling `notifications.deliver`, which returns nothing.
4. **R04:** confirmed. The `break` in `collectActionableResults` discards the rest of a page after the cursor has already advanced past it.
5. **R05:** confirmed. After awaiting, `loadMore` checks only that the state is `.results`, not that it belongs to the same query.
6. **R10:** confirmed, with a clarification. Swipe-to-delete (and the VoiceOver delete action) uses `requestImmediateRemoval`, which frees the slot immediately, so the scenario applies. Star-button removal defers the delete until the Undo window ends and is not affected.
7. **R15:** confirmed. `prepareSimulatedUpdateRunner` unconditionally builds a new runner on every call.

Overall the review is strong: findings are tied to real code paths, it says what it could not verify, and it avoids recommending a rewrite. The disagreements below concern how hard some fixes need to be and the order to do them in.

## Where the recommended fixes can be simpler

1. **R02 should be first.** It is the cheapest fix with the largest user impact, because it shows a wrong date on the app's core promise. One shared date-only format style using the UTC time zone, used by the headline, the notification body, and the CSV descriptive column, should cover it. Low-to-medium risk; it does not need to wait for a larger batch.
2. **R01 can probably be a `context.rollback()` in a catch.** The review worries that rollback might discard another operation's unsaved work. Every repository method saves immediately, so the context should normally have no other pending changes. Before relying on that, confirm that nothing else (recovery, export, diagnostics simulations) mutates this context without saving. If nothing does, this is a small change plus tests. It touches persistence, so treat it as medium risk and test carefully, but it does not obviously need the full high-risk process.
3. **R03 needs an explicit retry mechanism.** Restoring `lastNotifiedSignature` alone does not cause a retry. The refresh has already saved the new `nextSeason` and `sourceUpdatedAt`, so on the next poll `StatusChangeDetector.evaluate` sees no change, and the show may not even be fetched again. The existing debounce path offers a retry route instead. A set `pendingChangeSignature` forces a refetch (`awaitsConfirmation`), and `evaluate` notifies when the pending signature is seen again and differs from `lastNotifiedSignature`. A version built on that:
   1. Make delivery return distinct outcomes: accepted, suppressed (permission off, or delivery intentionally disabled for an interactive refresh), and failed (`center.add` threw). Today the permission check returns silently inside `scheduleNotification`, so suppression and failure are indistinguishable.
   2. On failure only, restore the previous `lastNotifiedSignature` and set `pendingChangeSignature` to the undelivered status's signature, so the next poll refetches and retries.
   3. Serialize refresh work for each show, from decision through scheduling and failure handling, so that no other refresh can make a decision for that show while its delivery is in flight. Other shows proceed in parallel. Signature equality alone is not a safe guard: an interleaved refresh could store a newer pending soft change, or a silent baseline of the same status, without changing `lastNotifiedSignature`. A timestamp is not a safe guard either, because wall-clock time is not guaranteed to be unique or increasing. User actions (removal, pausing, re-adding) are not serialized, so the restore still checks the row's identity (`dateAdded`), active state, and decision state in one repository operation. See the [behavior matrix](2026-10-12-r03-r13-behavior-matrix.md) for details.
   4. Suppression does not retry, so no arbitrary retry-count cutoff is needed. A persistent scheduling error would retry once per eligible poll, which is bounded by refresh frequency.
   5. Accept that termination after saving but before successful scheduling can lose an alert, rather than building a full pending/acknowledged state machine. This window is not necessarily brief, because scheduling awaits notification settings and `center.add`, and a background task can be suspended or expire in between. The product owner accepted this limitation (see "Product owner decisions").

   Retry must happen only after a known failure: Apple documents that adding a request whose identifier matches an already delivered notification alerts the user again ([UNNotificationRequest init](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/init(identifier:content:trigger:))).

   Design choice: reusing `pendingChangeSignature` gives one field two meanings (soft change awaiting confirmation, and delivery awaiting retry). A dedicated field is clearer but adds a property to `TrackedShowEntity`, which is a schema change. Prefer the no-migration option unless the behavior matrix finds a case it cannot handle. The planned notification history should distinguish "update recorded" from "accepted for scheduling"; system acceptance does not prove the user saw the alert. This remains high risk under `FEATURE_DEVELOPMENT.md`.

   The review's product questions still need answers: how disabled-permission suppression should behave, and whether enabling notifications later should replay missed alerts.
4. **R04:** retain the whole fetched page and treat the target of ten as a soft limit. Showing 19 results instead of 10 is harmless.
5. **R13 needs per-row decoding plus a persisted repair flag.** Decode rows one at a time so one damaged snapshot no longer blocks the whole list, and use `.unknown` for the damaged status. On its own that does not repair anything:
   1. `needsCalendarOrStatusRecheck` returns false for `.unknown`, so the row is refetched only if TVMaze reports a server change inside the update window. Resetting timestamps does not help until R11 is fixed, because shows outside the window are still skipped.
   2. Even after a refetch, `evaluate` would treat `.unknown` → airing or ended as a meaningful change and send an alert about old news.

   A repaired row therefore needs a persisted signal that forces a fetch on the next refresh and records the result as a silent baseline. The existing catch-up marks already do exactly this: they are persisted in UserDefaults (`watchlistCatchUpMarks`), keyed by show ID and `dateAdded`, and survive restart. `dateAdded` is its own column, and only `nextSeasonSnapshot` is JSON-decoded, so a damaged row still has the key the mark needs. Reusing catch-up marks would avoid a schema change. The open design points are how the repository reports damaged IDs to the refresh service without depending on it, and making sure the mark is set before any refresh evaluates the row. Verification should cover a mixed valid/damaged list, repair on the next refresh with no notification, and normal notifications for later changes. This matters most before a future release changes the persisted status format.
6. **R09:** keep the episode number, and only treat the next episode as a premiere when it is episode 1. Otherwise fall back to an announced-but-undated status.

## Where the priorities should change

1. **R11 and R08 deserve more weight than their P2 labels, and should be fixed together.** Both come from a TVMaze rolling update window (`day`/`week`/`month`) aging out while the app is not running. iOS runs background refresh less often for apps that are not opened, so long absences are exactly the case notifications exist to cover. Use one approach for both: choose the request window from the current request time, and use the full update map when the gap exceeds the supported window. The mapping refresh service already does the latter for initial gaps; R08 is the resumed-sync case it misses. Share one regression scenario: resume after the original window has expired.
2. **R10 and R14 are real but rare.** R10 needs a swipe-delete, an add, and an Undo within a few seconds. R14 needs two notification taps that resolve out of order. Both can rank below R11 and R13. The R10 product decision is now made (see "Product owner decisions" below).
3. **R12 matters mainly for diagnostics.** The success value given to the background task has little effect on users. Truthful refresh outcomes are still worth having, because diagnostics output is used as testing evidence.
4. **R07 is rare** (the bundled mapping database fails to open). An honest "search unavailable" message is sufficient for now; the bounded live-lookup fallback can wait.
5. **R15–R17 are contained developer-tool fixes.** R17 is a small shell change. Fix all three before relying on the performance tooling or beta-readiness reports again.

## Suggested order

1. R02, R01, and R04: small, high-value, independent fixes.
2. R11 and R08 together.
3. R03 and R13, designed together using the behavior matrix in [2026-10-12-r03-r13-behavior-matrix.md](2026-10-12-r03-r13-behavior-matrix.md). First compare the no-migration options (conditional `pendingChangeSignature` retry; catch-up marks for repair) against small schema additions. If any migration turns out to be warranted, design both changes before introducing V2 so there is only one.
4. R05 and R09.
5. R15–R17, before the next profiling or beta-readiness pass.
6. R10 (decided; see below), R14, R12, R07, and R06, plus the structural cleanups in separate small diffs: the unused `toastAnchor` geometry code, the leftover `WatchlistViewModel.State.loading`, the unused `watchlistCount` parameter on `PurchaseService.start`, and the in-memory repository's `updateAfterRefresh` behaving differently from the SwiftData implementation.

## Concept worth retaining

The review's cross-cutting point about actors is the most useful idea to keep: an actor (or `@MainActor`) runs one piece of code at a time, but not one whole operation across `await`s. Code after an `await` can find that another task changed the state, so stale results need their own check, such as a request ID or generation counter. R05 and R14 are both this bug. This is useful interview knowledge: it is the Swift actor reentrancy question.

## Product owner decisions

Recorded October 12, 2026:

1. **R03, notifications off:** The next development round adds an update history that records qualifying updates whether or not a system notification was scheduled. That covers the case where notifications are turned off. Turning notifications on later must not replay old history. Until the history exists, a change found while notifications are off is consumed without an alert, as today.
2. **R03, transient scheduling failures:** The fix must be verified to actually retry. Restoring the previous signature alone is insufficient, because the new status is already stored. The conditional `pendingChangeSignature` retry above addresses this, and R03 scenarios 2 and 11 in the behavior matrix are the required verification.
3. **R10, Undo over capacity:** If restoring the original row would exceed current free capacity, restore it as paused. Preserve its metadata (next-season and refresh fields, original `dateAdded`), and leave existing active shows unchanged. Plus users and restores within capacity are unaffected, and a row that was already paused stays paused. This avoids the outcome the review reproduced, where the normal pause policy later paused the show the user had just added.
4. **Regression tests:** Turn the review harness's reproduced scenarios into permanent tests in `NextSeasonTests`, added with each corresponding fix rather than as a separate batch. The harness is at `/tmp/NextSeasonReviewHarness.swift`, and its output is at `/tmp/NextSeasonReviewHarness-output.txt`. Both still existed on October 12, but `/tmp` is not durable.

5. **R03 and R13 behavior-matrix decisions:** All remaining product decisions in the [behavior matrix](2026-10-12-r03-r13-behavior-matrix.md) were accepted as recommended. Notably: "We accept that termination after saving but before successful scheduling can lose an alert," to be revisited when designing update history, which may provide a natural place to persist notification intent.

## Revisions

A second review of this analysis (ChatGPT) raised three corrections, all confirmed against the code and incorporated above:

1. The original R03 fix (restore the previous signature) would not retry, because the saved status no longer differs on the next poll. Replaced with an explicit retry through `pendingChangeSignature` or a dedicated field.
2. The original R13 fix ("marked for refresh") had no mechanism behind it, because `.unknown` rows are excluded from rechecks. Replaced with a persisted repair flag. This analysis also found that refetching a repaired row would send an alert about old news unless the result is recorded as a silent baseline.
3. The original order omitted R08. It now sits with R11, since both involve update windows aging out.

A second round raised further refinements, also confirmed against the code and incorporated above:

1. The first revision described catch-up marks as in-memory. They are persisted in UserDefaults, which makes them a candidate for R13 repair without a schema change.
2. The R03 retry restore must be conditional so it cannot overwrite a newer successful decision from an overlapping refresh.
3. Distinct accepted/suppressed/failed outcomes replace the earlier retry-cutoff idea.
4. The migration recommendation was premature. Compare no-migration options first, then design any V2 changes together.

The design review of the behavior matrix (ChatGPT, revision 1) found two blocking gaps: the signature-only restore guard, and repair marking that waited for a refresh. Matrix revision 2 resolved the repair-marking gap (marking in the repository before a fallback row is returned), which the reviewer confirmed. Its timestamp-based restore guard was rejected. Revision 3 replaces it with per-show serialization of refresh work, and the reviewer approved revision 3 on October 12, 2026. Details are in the matrix's "Design review findings and resolutions" section.

## Note on evidence

The review's reproduction harness lives in `/tmp` and will not persist. The regression scenarios it lists should become tests as each fix is implemented, so that the evidence lasts.
