# R03 / R13 behavior matrix — revision 4, design review approved

This is the high-risk discovery step from `FEATURE_DEVELOPMENT.md` for two findings in [2026-10-12-feature-area-review.md](2026-10-12-feature-area-review.md), as refined in [2026-10-12-feature-area-review-analysis.md](2026-10-12-feature-area-review-analysis.md):

1. **R03:** a notification is recorded as announced before the system accepts it, so a scheduling failure loses it permanently.
2. **R13:** one undecodable next-season snapshot makes the whole watchlist unreadable.

The product owner resolved all product decisions on October 12, 2026 (see "Product decisions"). An independent design review (ChatGPT) of revision 1 found two blocking gaps and three medium corrections. Its review of revision 2 confirmed the R13 resolution and asked for two R03 corrections: replace the timestamp-based ownership, and preserve the retry after an unchanged overlapping observation. This revision incorporates both (see "Design review findings and resolutions"). The reviewer approved revision 3 on October 12, 2026, which completes the high-risk design review stage. Implementation may proceed against this matrix. Independent acceptance review of the implemented behavior is still required before R03 and R13 are called complete. No application code was changed.

## Candidate designs

Both candidates avoid a SwiftData schema change. If a scenario turns out to need a new persisted field, design both changes together before introducing `NextSeasonSchemaV2`.

1. **R03 — per-show serialized refresh work, plus a guarded retry through `pendingChangeSignature`.**
   1. Delivery returns one of four outcomes: accepted, suppressed (alerts not permitted, or delivery disabled for this refresh), failed (a definite scheduling rejection), or unknown (submitted, but acceptance cannot be established).
   2. Refresh work for one show is serialized from decision through scheduling and failure handling. While a show's work is in flight, another refresh skips that show or waits for it to finish (joins); it never makes its own decision for that show concurrently. Other shows proceed in parallel. The whole watchlist is not serialized. This is in-process state only (no schema change), held by the single production `WatchlistRefreshService`.
   3. Because no other refresh decision can interleave, ownership only has to guard against user actions that can happen while scheduling awaits: removal, pausing, and re-adding. On failure, one repository operation restores the previous `lastNotifiedSignature` and sets `pendingChangeSignature` to the undelivered signature, but only if the stored row is still the same row (`dateAdded`), still active, and still holds the decision state this attempt wrote (status signature and both notification signatures).
   4. No timestamp is used for ownership. A wall-clock value is not guaranteed to be unique or increasing (design review, revision 2).
   5. A set `pendingChangeSignature` already forces a refetch (`awaitsConfirmation`), and `StatusChangeDetector.evaluate` notifies when it sees that signature again and it differs from `lastNotifiedSignature`.
   6. Delivery retry and soft-change confirmation share the field, but their expected results are specified separately below.
2. **R13 — detect damage in the repository, mark before exposing.**
   1. A small shared catch-up-mark store (extracted from `WatchlistRefreshService`'s existing UserDefaults-backed `catchUpMarks`) is used by both the repository and the refresh service. The repository then does not depend on the refresh service.
   2. When `toDomain` cannot decode `nextSeasonSnapshot`, the repository records a catch-up mark for that row (show ID plus `dateAdded`) before returning a fallback row with `.unknown`. Every decoding path goes through one shared helper: `all()`, `trackedShow(showID:)`, and the paused-row reactivation path inside `repository.add`, which currently calls `existing.toDomain()` directly.
   3. Reads and failed repairs never rewrite the damaged snapshot. It stays in place until a successful repair write. User actions that rewrite the row (Undo restore, reactivation) are covered by the mark recorded first.
   4. Damage is identified only by a decode failure, never by `nextSeason == .unknown`. Valid `.unknown` statuses keep their ordinary behavior.
   5. Networking and the silent-baseline repair stay in the refresh service through the existing `needsCatchUp` path. Because the mark exists before any caller sees the fallback row, operations that rewrite the row (Undo restore, reactivation) cannot erase the repair requirement (design review finding 2).

## Facts this matrix relies on

Verified in code:

1. `StatusChangeDetector.evaluate` compares against the saved `nextSeason`. Restoring only `lastNotifiedSignature` would not cause a retry.
2. `evaluate` runs regardless of `deliverNotifications`. A soft change seen for the first time sets `pendingChangeSignature` even when delivery is disabled. Only the `deliver` call is gated.
3. `isDateBacked` is true only for `.scheduled` and `.airing`. `.ended` is a meaningful change but not date-backed, so it waits for confirmation.
4. `NotificationService.scheduleNotification` returns silently when alerts are not permitted. A `center.add` error is caught, sent to analytics, and in DEBUG triggers `assertionFailure`. `deliver` returns nothing. Retry tests in DEBUG must not hit that assertion for expected, recoverable failures.
5. The default request identifier is `show-<id>-<signature>`.
6. `TrackedShowEntity` stores `dateAdded`, `lastCheckedAt`, `lastNotifiedSignature`, and `pendingChangeSignature` as ordinary columns. Only `nextSeasonSnapshot` is JSON-decoded.
7. Both `all()` and `trackedShow(showID:)` decode the snapshot and throw on failure. The refresh reads rows through `trackedShow(showID:)` (via `activeRow`) before and after each fetch.
8. `needsCatchUp` bypasses per-row eligibility and leads to `StatusChangeDetector.baseline`, which clears the mark after a successful write. However, a non-forced refresh fetches the updates map first and returns early if that request fails, so a catch-up row is not fetched in that pass either.
9. Production creates one `WatchlistRefreshService`, in `AppCompositionRoot`. The Diagnostics runner creates its own instances, but over a `SimulatedWatchlistRepository`, so they never touch the user's rows. Per-show serialization inside the production instance therefore covers every production refresh path. A future second production instance would have to share that state.
10. The paused-row reactivation path in `SwiftDataWatchlistRepository.add` decodes with `existing.toDomain()` directly.
11. Delivery is also called from `DiagnosticsDelayedNotificationDelivering` and `DiagnosticsSimulatedUpdateRunner`, and the direct Diagnostics "Send Test Notification" action schedules through `NotificationService`.

From Apple documentation:

1. `UNUserNotificationCenter.add` reports scheduling failure by throwing ([documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:))).
2. A request whose identifier matches an already delivered notification alerts the user again; one matching a pending request replaces it ([documentation](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/init(identifier:content:trigger:))). A retry must therefore happen only after a known failure.

Unverified assumptions:

1. What makes `center.add` fail in practice is not documented in detail. Real failures cannot be forced on a device, so `NotificationService` needs an injectable scheduling seam to test its outcome mapping.
2. How `center.add` behaves when the calling task is cancelled is not documented. The design does not let cancellation alone manufacture an unknown outcome. While the process is alive and the result can still be awaited, the real result is used (R03 scenario 15).
3. Exactly how the snapshot gets damaged in the field is unknown. Tests will use a hand-written invalid snapshot.

## R03 scenarios — notification delivery

1. **Normal acceptance.**
   - Trigger: a meaningful change is found, and the system accepts the request.
   - Expected: notification scheduled. The signature stays recorded, and later polls do not re-alert.
   - Source: current behavior, unchanged.
   - Verify: unit test with a delivery double that returns accepted.

2. **Scheduling fails, then succeeds on the next poll.**
   - Trigger: `center.add` throws. The next poll returns the same status.
   - Expected: the guarded restore applies. The next poll refetches even with no TVMaze change, sends the notification, and records it.
   - Source: the R03 fix. Required verification (product owner).
   - Verify: unit test with a double that fails once, then accepts. Assert exactly one accepted request and the final row state.

3. **Scheduling keeps failing.**
   - Trigger: `center.add` throws on every attempt.
   - Expected: each eligible poll retries once, with no cutoff. Analytics records each failure.
   - Source: product owner decision — unlimited retries; rate-limit analytics only if noisy.
   - Verify: unit test across three polls.

4. **Notification permission off.**
   - Trigger: alerts are not permitted when the change is found.
   - Expected: outcome is suppressed. The signature is consumed, and no delivery retry is set up. Enabling notifications later does not replay it.
   - Source: product owner decision. The planned update history records qualifying updates regardless of scheduling.
   - Verify: unit test with a double that returns suppressed.

5. **Delivery disabled for a refresh the user started.**
   - Trigger: a refresh runs with `deliverNotifications == false`.
   - Expected: a date-backed change is consumed, with no delivery retry. A soft change seen for the first time still sets its confirmation signature, exactly as today. Suppression adds no delivery retry, but it does not remove existing confirmation behavior.
   - Source: existing behavior, corrected per design review finding 3.
   - Verify: unit tests for a date-backed change (no pending signature afterwards) and a first-seen soft change (confirmation signature present, no delivery attempted).

6. **The show changes again before the retry.**
   - Trigger: delivery of B fails, then TVMaze changes to C before the next poll.
   - Expected: C follows the normal rules relative to B. If C is a date-backed meaningful change, it notifies on first sight. If C is a soft meaningful change, it becomes pending and notifies only on confirmation; B's failure does not make it immediate. If B → C is not meaningful, B's pending retry is cleared and nothing is sent. In every case B is superseded.
   - Source: product owner decision (superseded alerts may be dropped). Soft C wording corrected per design review finding 3.
   - Verify: unit tests for date-backed C, soft C, and non-meaningful C.

7. **The show reverts to the last announced state before the retry.**
   - Trigger: delivery of B fails, then TVMaze returns to A, which was already announced.
   - Expected: no alert. A matches the restored `lastNotifiedSignature`, and the pending B is cleared.
   - Source: invariant 1.
   - Verify: unit test.

8. **A second refresh reaches the show while B's work is in flight.**
   - Trigger: refresh 1 records B, and its delivery is in flight. Refresh 2 (foreground, background, or catch-up) reaches the same show.
   - Expected: refresh 2 skips or joins that show's in-flight work and makes no decision for it until refresh 1 finishes, including failure handling. Refresh 2 continues with other shows.
   - Source: invariant 8 (design review, revision 2).
   - Verify: unit test with a delivery double that suspends until released. Assert that refresh 2 makes no decision for the show while it is suspended, and that other shows are processed.

9. **A newer soft change arrives after B's failure.** (Design review finding 1.)
   - Trigger: delivery of B fails, and the retry is set up. The next refresh sees soft change C.
   - Expected: C follows normal confirmation rules relative to B (scenario 6) and is announced on confirmation. B's failure handler has already finished, so it cannot overwrite pending C. That was the reviewer's reproduced loss with interleaved refreshes.
   - Source: invariants 3 and 8.
   - Verify: unit test that attempts the reviewer's interleaving. Assert that refresh 2 is held back and that C is announced on the confirming poll.

10. **A silent baseline of the same B, decided at the same instant.** (Design review finding 1, revision 2.)
    - Trigger: refresh 1 records B, and its delivery is in flight. The show is paused and resumed (catch-up mark), and a catch-up refresh reaches it. Both decisions use the same injected time.
    - Expected: the catch-up refresh waits for B's work to finish. If B failed, the retry is set up first; the catch-up baseline then records B silently and clears the retry. B is never announced, matching the resume policy. No timestamp is involved, so identical times cannot cause a wrong result.
    - Source: invariants 3 and 8, and the existing resume policy.
    - Verify: unit test with a fixed clock (no advancing) for both decisions. Assert no alert for B and no retry remaining.

11. **The show is removed and added again while B is in flight.**
    - Trigger: refresh 1 records B, and its delivery is in flight. The user removes the show and tracks it again (new `dateAdded`). Then B's delivery fails.
    - Expected: the row identity differs, so the restore does nothing. The new row behaves as a newly tracked show.
    - Source: invariant 3. User actions are not serialized with refresh work, so the row check stays.
    - Verify: unit test against the SwiftData repository, or an in-memory repository aligned with production semantics.

12. **A second refresh observes the same unchanged status while B's work is in flight.**
    - Trigger: refresh 2 reaches the show while refresh 1's delivery of B is in flight, and TVMaze still reports B. Then B's delivery fails.
    - Expected: refresh 2 skips or joins and writes nothing for the show. The failure is still known, so the retry is set up, and the next poll delivers B. An unchanged observation neither supersedes B nor establishes a deliberate silent baseline.
    - Source: invariants 2 and 8 (design review, revision 2).
    - Verify: suspended-double test. Assert that B is delivered on the next poll.

13. **Permission is turned off after a failed attempt.** (New, design review finding 4.)
    - Trigger: delivery of B fails and a retry is pending. The user then turns notifications off, and the next poll's delivery is suppressed. Later the user turns notifications back on.
    - Expected: the suppressed attempt consumes the retry. Turning notifications back on does not replay B.
    - Source: product owner decision (no replay).
    - Verify: unit test across three polls.

14. **App terminated after saving, before successful scheduling.**
    - Trigger: the process ends after the row is saved and before `center.add` succeeds. The window is not necessarily brief.
    - Expected: the alert is lost, and the next poll does not retry.
    - Source: product owner decision: "We accept that termination after saving but before successful scheduling can lose an alert." Revisit when designing update history.
    - Verify: deterministic boundary test (design review finding 4). Save the pre-scheduling state to an on-disk store, reopen it with a fresh context, and assert that no retry occurs. Precisely timed termination is not needed.

15. **Refresh cancelled or background task expires while the process stays alive.** (New, design review finding 4.)
    - Trigger: the refresh task is cancelled, or the background task expires, after the row is saved.
    - Expected: cancellation alone never manufactures an unknown outcome.
      1. Cancellation observed before submission to `center.add`: run the guarded restore, so the alert is retried.
      2. `add` returns successfully: accepted, even if the task was cancelled meanwhile.
      3. `add` reports a definite scheduling rejection: failed, with the guarded restore.
      4. Submission occurred, but acceptance cannot be established: unknown, with no retry, because Apple re-alerts on a reused delivered identifier. If the process is alive and the result can still be awaited, await it rather than classifying it early as unknown.
    - Source: invariant 2 and the accepted termination decision (scenario 14). Confirmed by the design review, revision 2.
    - Verify: unit tests for each of the four cases using a scheduling seam, including a task cancelled while `add` is suspended and then succeeding.

16. **App restarts after a recorded failure.**
    - Trigger: delivery fails, then the app is terminated and relaunched before the next poll.
    - Expected: the pending signature was saved, so the first eligible poll after launch retries.
    - Source: the R03 fix. Required verification (product owner).
    - Verify: on-disk SwiftData store, reopened with a fresh container and context (design review finding 4). Recreating a service over the same in-memory repository does not prove persistence.

17. **The restore write itself fails.**
    - Trigger: delivery fails, and saving the guarded restore also throws.
    - Expected: the retry is lost and the failure is logged. With the R01 rollback in place, the failed write does not linger in the context.
    - Source: accepted limitation; depends on R01.
    - Verify: unit test with a repository double whose restore throws.

18. **The show is paused or removed before the failure is handled.**
    - Trigger: the show is removed or paused while delivery is in flight, then delivery fails.
    - Expected: removed — nothing is restored. Paused — paused rows are not refreshed, and a later resume records a silent baseline, so the alert is dropped.
    - Source: product owner decision (dropping is acceptable).
    - Verify: unit tests for both.

19. **The failed change was a soft change that needed confirmation.**
    - Trigger: a soft change is confirmed on its second poll, and delivery fails.
    - Expected: the guarded restore sets it pending again. The next poll that sees it delivers it.
    - Source: the R03 fix.
    - Verify: unit test.

20. **A resumed or catch-up row.**
    - Trigger: the row has a catch-up mark.
    - Expected: silent baseline, no delivery attempt (unchanged).
    - Source: existing behavior.
    - Verify: existing tests.

21. **`NotificationService` outcome mapping.** (New, design review finding 5.)
    - Trigger: scheduling with alerts permitted and `add` succeeding; with alerts not permitted; with `add` throwing.
    - Expected: returns accepted, suppressed, and failed respectively (unknown is covered by scenario 15). An expected scheduling failure does not trigger `assertionFailure` in the configuration used for tests.
    - Source: the R03 fix.
    - Verify: unit tests through an injectable scheduling seam. Delivery doubles in refresh tests cannot verify this mapping.

22. **Other delivery paths.** (New, design review answer 3.)
    - Trigger: the Diagnostics simulated pipeline (`DiagnosticsDelayedNotificationDelivering`, `DiagnosticsSimulatedUpdateRunner`) or the direct "Send Test Notification" action.
    - Expected: the simulated pipeline passes the real outcome on, so simulations exercise the same retry behavior. The test-notification action reports the real outcome but creates no watchlist retry state. All delivery protocol variants and their test doubles are updated consistently.
    - Source: design review.
    - Verify: unit tests for the simulated pipeline's outcome handling. Manual check of the Diagnostics test-notification report.

23. **Diagnostics wording.**
    - Trigger: any outcome above.
    - Expected: refresh diagnostics distinguish accepted, suppressed, and failed, and never claim the user received or saw the alert.
    - Source: R12 and the notification-history product goal.
    - Verify: unit test on outcome text. Manual review in Diagnostics.

## R13 scenarios — damaged snapshot repair

1. **A mixed list.**
   - Trigger: one row's snapshot cannot be decoded; the others are valid.
   - Expected: `all()` returns every row. The damaged row shows "Next season status unknown." The watchlist, ordinary export, refresh, and access reconciliation all work.
   - Source: the R13 fix.
   - Verify: SwiftData repository test with an invalid `nextSeasonSnapshot` written directly.

2. **Every decoding path marks first.**
   - Trigger: `all()`, `trackedShow(showID:)`, or the paused-row reactivation path in `repository.add` encounters the damaged row.
   - Expected: the shared helper records the catch-up mark before the fallback row is returned or used. Single-row reads also return the fallback instead of throwing; otherwise the refresh's per-show catch would skip the row forever. No read rewrites the damaged snapshot.
   - Source: the R13 fix; design review finding 2 and its revision 2 note on reactivation.
   - Verify: repository tests that assert the mark exists immediately after each path, including reactivating a paused damaged row, and that the stored snapshot bytes are unchanged after reads.

3. **A valid `.unknown` status is not treated as damage.**
   - Trigger: a row whose snapshot decodes successfully to `.unknown`.
   - Expected: no catch-up mark, and ordinary refresh and notification behavior.
   - Source: design review finding 2.
   - Verify: repository and refresh unit tests.

4. **Repair on the next refresh.**
   - Trigger: a damaged, marked row is active, and a refresh runs.
   - Expected: the refresh fetches it even with no server change, records a silent baseline, rewrites a valid snapshot, and clears the mark.
   - Source: the R13 fix, reusing catch-up marks.
   - Verify: unit test asserting a fetch, no notification, a decodable snapshot afterwards, and no mark remaining.

5. **No alert about old news.**
   - Trigger: the repaired row's real status is scheduled, airing (date-backed), or ended (meaningful but not date-backed).
   - Expected: no notification for any of them, because the repair goes through the silent baseline and not `evaluate`.
   - Source: invariant 6. Status classification corrected per design review finding 3.
   - Verify: unit test for each of the three statuses.

6. **A real change happened while the row was damaged.**
   - Trigger: the fetched status would have been news compared with the last notified state.
   - Expected: silently absorbed by the baseline.
   - Source: product owner decision.
   - Verify: unit test.

7. **Repair blocked by a network failure.**
   - Trigger: offline, the updates-map request fails (a non-forced refresh returns early before any row is fetched), or the per-row repair fetch fails.
   - Expected: the row stays `.unknown` and the mark persists. A later refresh retries. No alert.
   - Source: existing catch-up and updates-map behavior (fact 8).
   - Verify: unit tests for both the updates-map failure and the per-row failure.

8. **Repair fetch returns 404.** (New, design review finding 4.)
   - Trigger: TVMaze reports the show as not found during repair.
   - Expected: the saved identity is kept, and the existing stale-row policy applies: the row is marked stale, with no alert. Decide during implementation whether the stale-path write clears the mark, so the mark does not stay forever.
   - Source: existing stale-row policy.
   - Verify: unit test.

9. **The repair baseline save fails.** (New, design review finding 4.)
   - Trigger: the baseline write throws.
   - Expected: R01 rollback leaves the previous stored state, including the damaged snapshot. The mark remains, and a later refresh retries.
   - Source: depends on R01.
   - Verify: unit test with a throwing repository double, plus a SwiftData test once R01 lands.

10. **App restarts before repair.**
    - Trigger: the app is terminated after the mark is recorded and before a successful refresh.
    - Expected: the mark persists in UserDefaults. On relaunch, the row is still repaired silently.
    - Source: catch-up mark persistence.
    - Verify: unit test with a fresh mark store over the same UserDefaults suite, and an on-disk SwiftData store reopened with a fresh context.

11. **Delete and Undo before the first refresh, then restart.** (New, design review finding 2.)
    - Trigger: the watchlist shows the damaged row as `.unknown`, which records the mark. The user swipe-deletes it and taps Undo before any refresh, then the app restarts.
    - Expected: Undo writes `.unknown` as valid JSON, but the mark (same `dateAdded`) already exists, so the first refresh after the restart still records a silent baseline. No alert.
    - Source: design review finding 2.
    - Verify: on-disk store test: read (mark), delete, restore, reopen the store and mark store, refresh, assert no notification and a repaired snapshot.

12. **Damaged row is paused.**
    - Trigger: the damaged row is paused.
    - Expected: it shows `.unknown`, and the mark persists until it is resumed. Resume already marks for catch-up.
    - Source: existing pause policy.
    - Verify: unit test.

13. **Damaged row removed and later added again as a new row.**
    - Trigger: the user removes the row and later tracks the show again.
    - Expected: the new row has a different `dateAdded`. The old mark is pruned as superseded.
    - Source: existing mark-pruning logic.
    - Verify: existing tests plus one damaged-row case.

14. **Every row damaged.**
    - Trigger: all snapshots are undecodable.
    - Expected: the watchlist lists every saved show as status unknown, and export works. Every row is repaired on the next successful refresh. This does not route to launch recovery.
    - Source: the R13 fix.
    - Verify: unit test.

15. **Diagnostics and analytics.**
    - Trigger: damage is detected and later repaired.
    - Expected: a non-fatal analytics event per detection (not per read of an already-marked row), and a diagnostics line for the repair baseline. No user-facing message.
    - Source: product owner decision (silent to the user).
    - Verify: unit test on analytics calls.

## Invariants

1. Never re-alert for a state the user was already told about.
2. Never mark a notification as delivered after a known scheduling failure. The accepted exceptions are termination, or an unknown outcome after `add` was called (R03 scenarios 14 and 15).
3. A delivery-failure restore applies only to the same saved, active row and the still-current decision that attempt wrote. It never overwrites a newer decision. Ownership never depends on timestamps.
4. Suppression never sets up a delivery retry, and it does not alter existing soft-change confirmation behavior.
5. One damaged snapshot never hides other saved shows or drops a saved identity.
6. Repairing a row never produces a notification.
7. The repair requirement is recorded before a fallback row is visible to any caller, and damage is identified only by a decode failure. The damaged snapshot is kept until a successful repair write.
8. Refresh work for one show (decision, scheduling, failure handling) never overlaps with other refresh work for the same show. Other shows are unaffected.

## Product decisions

Decided (October 12, 2026):

1. R03 scenario 4: when notifications are off, the change is consumed with no replay. The planned update history records qualifying updates regardless of scheduling.
2. R03 scenarios 2 and 16: the fix must be verified to actually retry after a transient scheduling failure. Those scenarios are required tests.
3. Testing: the review harness's reproduced scenarios become permanent tests, added alongside each fix.
4. R03 scenario 3: unlimited retries on persistent scheduling failure. Rate-limit failure analytics only if it proves noisy.
5. R03 scenario 6: a superseded undelivered alert may be dropped.
6. R03 scenario 14: "We accept that termination after saving but before successful scheduling can lose an alert." The window is not assumed to be brief. Revisit when designing update history.
7. R03 scenario 18: dropping an undelivered alert when the show is paused is acceptable.
8. R13 scenario 6: a real change that happened while the row was damaged is silently absorbed by the repair baseline.
9. R13 scenario 15: repair is silent to the user (analytics and diagnostics only).

No product decisions remain open. The design review confirmed that R03 scenario 15 applies the termination decision correctly. Scenario 12 now preserves the retry, so no new limitation is introduced.

## Design review findings and resolutions

Review of revision 1 by ChatGPT, October 12, 2026:

1. **P1 — the signature-only restore guard was insufficient.** Resolved by the owned restore (candidate design 1), which compares row identity, both signatures, the status signature, and `lastCheckedAt`. Added R03 scenarios 9, 10, and 11. The timestamp part was superseded in revision 3 (see below).
2. **P1 — repair marking could not wait for a refresh.** Resolved by marking in the repository before returning a fallback row, with a shared mark store (candidate design 2). Damage is identified only by a decode failure. Added R13 scenarios 2, 3, and 11. Awaiting reviewer confirmation.
3. **P2 — confirmation versus retry semantics.** Corrected R03 scenarios 5 and 6, and R13 scenario 5 (`.ended` is not date-backed).
4. **P2 — failure-boundary and persistence tests.** Added R03 scenarios 13 and 15, and R13 scenarios 8 and 9. Changed R03 scenarios 14 and 16 to on-disk store verification.
5. **P2 — notification-service outcome mapping.** Added R03 scenarios 21 and 22, and the `assertionFailure` fact.

Reviewer answers adopted:

1. Reusing `pendingChangeSignature` is reasonable with the ownership guard and the specified confirmation semantics. A dedicated field alone would not solve stale failure handling.
2. Detect damage in the repository and use a shared mark store; keep networking and baseline repair in the refresh service.
3. The Diagnostics delivery paths need the real outcome. The test-notification action must not create watchlist retry state.

Fact qualification adopted: catch-up rows still depend on the updates-map request succeeding in a non-forced refresh (fact 8, R13 scenario 7).

Review of revision 2 by ChatGPT, October 12, 2026:

1. **Finding 2 (R13) confirmed resolved.** Two refinements adopted: the reactivation path in `repository.add` uses the same decoding helper, and the damaged snapshot is kept until a successful repair write (candidate design 2, R13 scenario 2, invariant 7).
2. **Finding 1 (R03) not yet resolved.** `lastCheckedAt` cannot serve as an ownership stamp, because wall-clock time is not guaranteed to be unique or increasing. Resolved in revision 3 by serializing refresh work per show, from decision through failure handling. Row and state checks are kept for user removal, pausing, and re-adding. No timestamp is used. Added the same-instant test (R03 scenario 10).
3. **Scenario 12 must not lose B.** Adopted: an unchanged overlapping observation now preserves the retry.
4. **Scenario 15.** No retry for a genuinely unknown outcome is confirmed. Adopted the four-way classification so that cancellation alone never creates an unknown outcome.

## Out of scope

1. R11 and R08 (update windows aging out). R13 repair bypasses per-row eligibility, but it still needs the updates-map request to succeed.
2. R01 (rollback after a failed save) is a prerequisite for R03 scenario 17 and R13 scenario 9, but it is a separate change.
3. The update history feature itself.
4. Launch recovery for an unreadable store, which is unchanged.

Review of revision 3 by ChatGPT, October 12, 2026: approved. Finding 1 is resolved by per-show serialization of refresh work, with row and state checks for user actions. No design-review questions remain open.

## Revision 4: consistency check after R01 and R08/R11 (October 14, 2026)

R01 and R08/R11 were implemented after revision 3 was approved. This section checks the matrix against the current code. **Approved: the design reviewer (ChatGPT) accepted revision 4 on October 14, 2026, and the product owner approved the delayed catch-up baseline (change 1) the same day.** Where this section and the scenarios above differ, this section wins.

Still valid as written:

1. **Retry does not depend on the updates map.** R11 may advance its coverage watermark past B's server change once B's row is saved. That is harmless: the R03 retry is driven by `pendingChangeSignature`, which forces a fetch (`awaitsConfirmation`) whatever the map says. Fact 8 also still holds: a failed updates request, now possibly the full map, still ends a non-forced refresh before any row is fetched.
2. **R11's coverage rule tolerates serialization.** A pass that skips a busy show counts it only if the saved row already proves coverage. Under R03 the owner saves the row before scheduling, so a show whose delivery is in flight is covered, and one still being fetched is not. A not-found row counts only when the pass saved its own stale flag, so a show skipped while its owner handles a 404 blocks the advance. That is conservative and correct.
3. **R01 supplies the rollback for R03 scenario 17 and R13 scenario 9,** provided the new guarded-restore operation goes through `SwiftDataWatchlistRepository.performWrite`. That requirement is added below.

Proposed changes:

1. **Skip, not join, for a busy show** (candidate design 1.2; R03 scenarios 8, 10 and 12).
   - Scenario 12 requires the second refresh to make no decision for the show, so joining would only add waiting. Waiting uses the 30-second background budget for nothing.
   - Proposal: every refresh skips a show whose work is in flight.
   - Scenario 10's expected result changes accordingly. The catch-up refresh skips the busy show and its mark stays, so the next refresh that reaches the show records the silent baseline and clears any retry. B is still never announced; the baseline is only delayed.
2. **A successful stale write clears the catch-up mark** (R13 scenario 8 left this to implementation).
   - A marked row is fetched on every pass. If the mark stays after a 404, every refresh refetches the row and gets 404 again.
   - The stale write stores the fallback `.unknown` as valid JSON, so the snapshot is repaired, and clearing the mark is safe.
   - A failed stale write keeps the mark.
3. **New R13 scenario 16: a damaged row no longer blocks R11 coverage.** R11's coverage check reads `all()`. Today one undecodable row makes that read throw, so the watermark cannot advance; this is the limitation recorded at R11 completion. After R13, `all()` returns the fallback row.
   - Expected: the fallback row is judged by its stored `sourceUpdatedAt` like any other row. Its repair baseline (catch-up) updates it, and the watermark can advance.
   - Verify: a SwiftData test with one invalid snapshot, where a non-forced refresh advances the watermark after the repair.
4. **Detection events once per detection, not per read** (R13 scenario 15). R11 added a second `all()` read per refresh, the coverage check. Recording the mark marks the detection, so a read of an already-marked row records nothing.
   - Verify: assert one analytics event across a full refresh, which makes at least two reads.
5. **Guarded restore uses R01's write boundary** (R03 scenario 17). The new repository restore operation runs inside `performWrite`, so a failed restore is rolled back, including the fresh-context replacement on iOS 18. `InMemoryWatchlistRepository` implements the same guard, so refresh tests match production semantics (R03 scenario 11).

Test impact, which needs no design change: several R11 coverage tests (scenarios 10, 11 and 16 in the R08/R11 matrix) overlap two passes on the same show. Once R03 serializes per show, the second pass skips that show instead of fetching it. Those tests will be restructured to keep their intent; for example, the first pass is held during delivery (after its save) rather than during the fetch.

Clarifications from the design reviewer's approval:

1. **Scenario 10 applies to a failed delivery.** "B is never announced" holds when B's in-flight delivery fails. If iOS already accepted B, a later pause and resume cannot retract that alert; the baseline only prevents a second one.
2. **Damage detection is tracked separately from the catch-up mark** (change 4). A row can already carry a resume mark when its damage is first found, so "the mark exists" cannot mean "damage already reported". The repository records the detection itself, keyed like marks by show ID and `dateAdded`, and emits the analytics event the first time it sees the damage for that row. This applies whether or not a resume mark already existed. Repair clears the detection record together with the mark.
   - Verify: a damaged row that already has a resume mark still produces exactly one detection event.

Out-of-scope note 1 is superseded: R08/R11 are done. Repair still needs the updates request to succeed (fact 8).

## Implementation status (October 14, 2026)

- **R13: implemented; independent acceptance review pending.** Each R13 scenario 1–16 has a test in `WatchlistSnapshotRepairTests.swift`, except scenario 13's existing pruning tests, which are reused. The repository side covers scenarios 1–3 and 15; the refresh side covers scenarios 4–14 and 16.
  - A successful stale write clears the repair mark only for rows whose damage was reported. A resumed but undamaged row that returns 404 keeps its existing behavior.
- **R13 acceptance review, finding 1 (P2), resolved.** A damaged row repaired through a 404 kept any `pendingChangeSignature`, which forced a refetch on every later refresh even after the mark was cleared. The 404 repair now clears the pending signature in the same saved write and clears the mark only after that write succeeds. Resumed, undamaged rows keep their existing behavior. New regression: `notFoundRepairClearsPendingSignature`, which fails without the fix.
- **R13 accepted (October 14, 2026).** The design reviewer's re-review found no blocking issues.
  - iPhone 16 / iOS 18.6: 551 of 552 passed; the only failure is the documented show-detail audit.
  - iPhone 18 Pro Max / iOS 27.0: 552 of 552 passed.
  - The five suspected intermittent failures passed on both; their earlier cause remains unproven.
- **Suspected intermittent failures (not proven pre-existing).** One full iOS 18.6 run on October 14 failed five tests in `WatchlistPendingRemovalTests` and `WatchlistViewModelTests`: `replacingPendingRemovalEmitsReplacedOutcome`, `replacingPendingRemovalCommitsPrevious`, `timerExpiryRemovesShowWithCancellationAwareRepository`, `failedImmediateDeleteRestoresRow` and `replacingPendingRemovalDropsFirstShowFromDisplayedList`. They use the in-memory repository, which R13 does not touch, and all 38 tests in those suites passed when rerun alone. Passing in isolation does not prove the failures predate R13.
- **R03: implemented; independent acceptance review pending (October 14, 2026).**
  - Delivery returns `NotificationDeliveryOutcome` (accepted, suppressed, failed, unknown). `NotificationService` has a DEBUG scheduling seam. Its DEBUG `assertionFailure` on a scheduling error is removed, because the failure is now expected and retried. A cancellation seen before submission is `failed`; a `CancellationError` from `add` is `unknown`.
  - `WatchlistRefreshService` skips a show whose refresh work is in flight (`inFlightShowIDs`). On `failed` only, it calls the new `WatchlistRepository.restoreUndeliveredNotification`, guarded by `StatusChangeDetector.isStillCurrent`. SwiftData runs it inside `performWrite`; the in-memory and Diagnostics simulated repositories implement the same guard. A protocol-extension default serves test doubles.
  - Tests: `NotificationDeliveryOutcomeTests` (scenarios 15 and 21); `WatchlistDeliveryRetryTests.swift` (scenarios 1–19, 22 and 23, plus the review harness's `FAILED_DELIVERY` reproduction). Scenario 20 reuses the existing catch-up tests. Every new regression test was confirmed to fail with its fix undone.
  - Restructured to keep their intent: the R11 coverage tests `overlappingFailuresKeepCoverage`, `overlappingSuccessCovers` and `olderPassKeepsNewerWatermark` now share one service instance. `clockResetDuringPassSelfCorrects` needed no change; its passes do not overlap.
  - Also restructured, which revision 4 did not anticipate: three `SubscriptionDowngradeRefreshTests` that overlapped two refreshes on one show (`overlappingRefreshAndCatchUp`, `delayedCatchUpAnnouncesNewUpdate` and `staleResponseIsRejected`).
    - One interleaving now ends differently. A catch-up's fetch for a resumed show is in flight, and an ordinary refresh reaches the show. That refresh now skips it, so the catch-up baselines whatever it fetched, silently, including a change published after the resume. Before R03, the ordinary refresh could consume the mark first, so the catch-up announced such a change. Either way, a catch-up running alone silently baselines whatever it fetches, so this window already existed. For the reviewer to confirm.
    - The older-response guard is still covered by `olderResponseKeepsCoverage`.
  - iPhone 16 / iOS 18.6: 588 of 589 passed; the only failure is the documented show-detail audit.
  - iPhone 18 Pro Max / iOS 27.0: 587 of 589 passed. The two failures were suspected intermittent ones, `failedImmediateDeleteRestoresRow` and `replacingPendingRemovalDropsFirstShowFromDisplayedList`. Both suites (38 tests) passed when rerun alone.
  - Manual check still needed: Diagnostics test-notification and refresh-outcome wording (scenarios 22 and 23).
- **R03 acceptance review, finding 1 (P2), fixed; re-review pending.** The Diagnostics simulation reported "will retry next refresh" and then reset, discarding the pending retry. Three causes, all in Diagnostics code:
  - The runner reset after every run. It now keeps the scenario while a retry is pending: `runNextStep` stays on the updated step, and the delayed pipeline reruns on the same data.
  - The simulated premiere was recomputed from the clock on every fetch, so a retry looked like a new change. The premiere is now fixed when the updated phase is entered.
  - `DiagnosticsView` created a new runner on every tap, which also meant the existing two-step simulation always restarted at step 1. It now keeps the runner while the test show is the same, so the two-step flow advances between taps as its documentation describes.
  - New regressions: `simulatedStepRetriesFailedAlert` and `delayedPipelineRetriesFailedAlert`, which use an advancing clock and check that the retried alert is the same one. They replace the wording-only test. Both fail with either the runner fix or the premiere fix undone. Production refresh code is unchanged, so the full suite was not rerun.
- **R03 re-review (October 14, 2026): finding 1 resolved, no new blocking findings.** Not yet fully accepted. Two items are outstanding:
  - ~~A visual check of the Diagnostics screen~~ **Done by the product owner on October 15 in the simulator; everything looked fine.** The two-step flow advanced from step 1 to step 2 and then back to step 1. The delayed pipeline and the test notification each scheduled a banner, and the wording matched and fit on screen. The notifications-off cases cannot be run from Diagnostics, because existing behavior disables those buttons when alerts cannot be delivered. The suppressed wording is covered by `suppressedIsConsumed` and `suppressedMapping`.
  - The two suspected intermittent iOS 27 failures. Both use one-second waits, which suggests timing sensitivity; the cause is unproven.

## Remaining process steps

1. Implement against this matrix, with each scenario's verification as listed. Add the review harness's reproduced scenarios as permanent tests alongside the fixes.
2. R01 (rollback after a failed save) is a prerequisite for R03 scenario 17 and R13 scenario 9.
3. Independent acceptance review of the implemented behavior, followed by a completion report as required by `FEATURE_DEVELOPMENT.md` section 6.
