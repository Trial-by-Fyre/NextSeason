# Expiration re-check while open, and Restore Purchases feedback

**Features:**
1. A Plus subscription that expires while NextSeason stays open is detected at expiration, not only on the next foreground return or relaunch.
2. Restore Purchases that finds no Plus tells the user, instead of silently leaving the paywall open.

**Risk:** (1) High — subscriptions, entitlement, pausing saved shows, async timing. (2) Medium — user-facing purchase feedback with familiar APIs.

**Status:** Implemented, pending sandbox/TestFlight verification. Independent design review (blocking findings resolved) and independent acceptance review (no blocking findings), 2026-10-21. Product owner chose a 5-minute margin (2026-10-21). Full suite pending (owner-controlled).

## Platform facts (StoreKit documentation)

- `Transaction.expirationDate`: "The date the subscription expires or renews." ([Transaction properties](https://developer.apple.com/documentation/storekit/transaction-properties))
- "The App Store renews the subscription slightly before it expires, to prevent any lapse." Renewals arrive through `Transaction.updates`. ([Handling Subscriptions Billing](https://developer.apple.com/documentation/storekit/handling-subscriptions-billing))
- Subscriptions in a billing grace period are entitled to service. Billing retry without grace is not. ([RenewalState](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalstate))
- Existing code relies on `Transaction.currentEntitlements` already including grace-period and auto-renew-off subscriptions until they end (unchanged).
- **Unverified assumption:** a renewal that happens before expiration is visible in `currentEntitlements` (or delivered through `Transaction.updates`) by the time the re-check runs. Sandbox renewal timing may differ from production; only sandbox/TestFlight testing can reduce this.
- `Task.sleep(for:)` defaults to `ContinuousClock`, which keeps counting while the device sleeps; a deadline passed while suspended fires on resume. The foreground handler also re-reads, so the extra read is harmless.

## Design

1. `PurchaseStoreClient.plusEntitlementCheck()` is replaced by `plusEntitlementStatus()`, returning the existing `PlusEntitlementCheck` plus `expirationDate: Date?`. The live client scans all verified, non-revoked Plus entitlements and reports the **latest** expiration among non-upgraded transactions. Unverified entries never supply a date.
2. When `PurchaseService` commits the newest read (`applyEntitlementCheck`):
   - `.active` with a future expiration-plus-margin deadline → cancel any pending re-check and schedule one `refreshEntitlements()` at `expirationDate + 5 minutes` (owner decision). The wait uses `ContinuousClock` (the `Task.sleep(for:)` default), which keeps counting while the device sleeps, so a deadline passed during suspension fires on resume.
   - `.active` with no date, or with an expiration-plus-margin deadline already elapsed (e.g. grace period), or `.inactive` → cancel any pending re-check; schedule nothing.
   - `.unverified` → leave the existing re-check alone (prior confirmed state is kept, so its expiration still applies).
3. The re-check goes through the normal `refreshEntitlements()`, so the newest-request ordering rule, unverified handling, and `NextSeasonApp`'s `.task(id: confirmedWatchlistAccess)` reconcile all apply unchanged. No new pause path.
4. Sleep and clock are injected for tests. The task is cancelled on deinit.
5. Restore: `PurchaseService` records the raw result of the last committed read (`lastCommittedCheck`), because an `.unverified` read leaves a resolved state unchanged (review finding 1). After a successful restore, the view that started it asks `restoreNotice` and keeps the message in its own `@State`, so a notice cannot appear later somewhere else if the sheet was dismissed mid-restore (finding 6):
   - actual Plus (StoreKit or complimentary) → no notice
   - last committed read unverified → "NextSeason found a Plus purchase but couldn't verify it. Please try again later."
   - otherwise → "No active NextSeason Plus subscription was found for this Apple Account."
   Shown as a "Restore Purchases" alert in `PlusStoreView` and the About Plus section.

## Behavior matrix

| # | Scenario | Expected | Source / owner | Verification |
|---|---|---|---|---|
| E1 | Plus expires (auto-renew off) while app stays open | ~5 min after expiration, entitlement re-read → inactive → three oldest stay active, rest paused, alert shown | Product request; StoreKit | Unit (injected sleep); sandbox SK-14 |
| E2 | Plus renews before expiration while app open | Renewal update refreshes → new expiration → re-check rescheduled; nothing paused | StoreKit docs | Unit; sandbox SK-11 |
| E3 | Re-check fires but renewal not yet visible | Transient pause; renewal via `Transaction.updates` resumes all with silent catch-up | Assumption (above) | Unit (resume after update); sandbox |
| E4 | Grace period (active, expiration-plus-margin deadline elapsed) | No re-check scheduled (no loop); grace end detected on next foreground/relaunch | Platform; accepted limitation | Unit |
| E5 | Re-check read returns unverified | Confirmed Plus kept; nothing paused. If it was the timer's own read, nothing is left scheduled; lapse applies on next foreground/relaunch | Existing invariant | Unit |
| E6 | Newer read commits before timer fires (purchase, restore, foreground) | Pending timer replaced by the newest read's schedule | Design | Unit |
| E7 | Lapse → inactive | Timer cancelled; no further reads scheduled | Design | Unit |
| E8 | App suspended across expiration | Timer fires late on resume and/or foreground handler reads; one extra harmless read | Assumption | Code review; sandbox SK-13 |
| E9 | Simulate Free Tier / complimentary | Unaffected: timer only refreshes actual StoreKit state | Existing design | Existing tests |
| E10 | Monthly + annual both entitled (plan switch) | Uses latest non-upgraded expiration (rare: one group returns one entitlement) | Design | Code review (live client) |
| E11 | Timer's own read reschedules (renewed) | New timer survives; the fired task does not clear it | Review finding 9 | Unit |
| E12 | Expires while paywall/About/Diagnostics sheet is open | Shows pause; alert may wait until the sheet closes; purchasing then works | Review finding 5 | Manual |
| E13 | Pause lands during a foreground refresh | In-flight fetch of a just-paused show is not written or notified (existing guard) | Review finding 7 | Existing test `downgradeDuringInFlightFetch` |
| R1 | Restore, no purchases | "No active … subscription" alert; stays free; paywall stays open | Product request | Unit |
| R2 | Restore finds Plus | No notice; paywall dismisses (existing) | Existing | Unit |
| R3 | Restore finds unverified Plus | "couldn't verify" notice; no grant, no pause | Existing invariant | Unit |
| R4 | Restore fails | Existing error alert only; no notice | Existing | Existing + unit |
| R5 | Restore from About with Plus sheet closed | Alert in About only | UI | Manual |
| R7 | Paywall dismissed while restore is in flight | No notice later, anywhere | Review finding 6 | Code review (view-local state) |
| R8 | Resolved free, restore read unverified | "couldn't verify" notice, not "none found" | Review finding 1 | Unit |
| R6 | Complimentary user restores with no subscription | No notice (they have Plus) | Design | Unit |

## Design review (independent, 2026-10-21)

Findings 1 (R3 undetectable) and 2 (false pause at the renewal boundary) were blocking. 1 is fixed by `lastCommittedCheck` and view-local notices. For 2, the owner chose a 5-minute margin and accepts a transient false pause if a renewal still isn't visible then (it self-corrects through `Transaction.updates` or the next read). Findings 3–9 are folded into the design and matrix above. Finding 10 (no confirmation for a successful restore from About; the status row changes) is accepted as intended.

## Out of scope

- Timer for grace-period end (needs `Product.SubscriptionInfo.Status`); detected on next foreground/relaunch.
- Messaging when Simulate Free Tier masks a restored Plus (developer-only).
- Treating a user-cancelled App Store sign-in during restore as cancellation rather than failure.

## Acceptance review (independent, 2026-10-21)

No blocking findings. Every matrix row was checked against code and tests.

1. A fired re-check whose read was unverified left a stale task reference: **fixed**. The timer clears its reference before reading; covered by `unverifiedRecheckReadLeavesNothingScheduled`.
2. Live client latest-expiration selection (E10: `isUpgraded`, max date, unverified ignored) has no automated test: **follow-up**; covered by sandbox plan-switch SK-11.
3. Tests used the margin constant: **fixed** (`marginIsFiveMinutes`). R3's "no pause" relies on existing unverified tests; `settle` polling bounded at 500 yields: **accepted**.
4. Device clock set more than 5 minutes ahead can run the re-check before the real expiration. It then reads active with a past date and schedules nothing, so the lapse waits for the next foreground: **accepted-limitation candidate** (bounded; owner sign-off needed).
5. Offline renewing subscriber may be paused briefly, sooner than before: the owner-accepted E3 risk.
6. Unverified at re-check keeps Plus until the next foreground (E5): as designed.

## Verification

- Unit (2026-10-21, active simulator): `ExpirationRecheckAndRestoreNoticeTests` 14/14. With the StoreKit/entitlement suites (`PurchaseServiceTests`, `PurchaseServiceEntitlementOrderingTests`, `SubscriptionDowngrade*`, `SubscriptionLifecycleTests`, `FreeTier*`, `PlusEntitlementStoreTests`, `PlusAccountPresentationTests`): 167 passed before the acceptance fixes; ordering plus new suite re-run afterward, 32/32.
- UI tests: none run. No UI test taps Restore or exercises expiration.
- Manual pending: E8, E12, R5, R7; sandbox SK-11, SK-13, SK-14, SK-18.


## Review follow-up: preserve the complete deadline (2026-10-21)

The clock-skew limitation above also affected offsets below five minutes: an active
read could cancel the re-check when expiration appeared past but the full deadline
was still ahead. The scheduler now checks `expirationDate + margin`, preserving
that remaining delay. An elapsed complete deadline still schedules nothing, so a
grace-period read cannot loop. The regression test uses expiration one minute in
the past, expects a four-minute delay, then confirms the fired check detects a
lapse. Boundary tests cover deadlines exactly elapsed and already past. Clock
skew that exhausts the full margin and the other documented limitations remain.

Verification: `ExpirationRecheckAndRestoreNoticeTests` passed (14 tests, including
the new clock-offset regression and three deadline-boundary cases) on iPhone 18
Pro Max / iOS 27.0. No UI or full-suite tests were run. `git diff --check` passed.
