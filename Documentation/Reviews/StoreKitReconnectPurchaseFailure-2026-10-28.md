# StoreKit 8C — Purchase fails after restoring network connectivity

**Reported October 28, 2026. Status: open owner-observed recovery failure; not independently reproduced or fixed.** Related coverage: focused 8C, SK-18 and purchase/network recovery.

## Reported sequence

1. During 8C, attempt Restore Purchases without network connectivity; the app displays the generic restore error recorded separately below.
2. Restore network connectivity.
3. Dismiss the restore error.
4. Retry the purchase. NextSeason displays **Couldn't Complete Purchase** with **The purchase wasn't completed, so NextSeason Plus wasn't unlocked. Please try again.**

Owner reports this sequence seems repeatable. No measured attempt count was supplied. The reported retry is a purchase attempt; do not silently rewrite it as a second Restore Purchases attempt. The exact control/plan tapped and whether Apple's payment sheet appeared remain unconfirmed.

## Expected behavior

After connectivity returns and the restore error is dismissed, a valid purchase should be usable and complete through the normal purchase flow. A previous failed Restore must not leave purchase state preventing recovery. Confirmed purchase success must unlock Plus and complete the original blocked add/reactivation once, without duplicate rows. This expectation does not assume the failed attempt actually completed or charged anything.

## Evidence and limits

![Purchase error after network recovery](Attachments/StoreKit-8C-Purchase-After-Reconnect-2026-10-28.png)

The supplied screenshot is named October 28 at 9:02:39 PM and its screen clock shows 9:02. It establishes the purchase-not-unlocked alert on the Plus paywall. Exact build, install source/scheme, device/OS, starting access, target show, transaction ID, reconnection delay, and later recovery outcome were not supplied. Do not infer these from other reports. In particular, unlike 7C, no successful second attempt was reported for this sequence.

The message matches the one seen in [7C's first-attempt purchase failure](StoreKitMonthlyFirstAttempt-2026-10-28.md), but identical wording does not establish a common cause. No transaction outcome/error code was captured for this report. Keep this functional recovery failure separate from the [8C restore-message improvement](StoreKitRestoreErrorMessaging-2026-10-28.md), which only concerns the prior alert's title/body.

## Follow-up evidence

On a focused reproduction, record which control was tapped (Monthly/Annual versus Restore), actual connection availability, Apple's sheet/result, and diagnostics around both the failed Restore and the later purchase. Preserve the initial failure even if a later attempt succeeds. Check that purchase/restore busy state and errors clear correctly on each completed attempt; establish the cause before changing entitlement policy.

No app code, account, scheme or transaction state changed to record this report. No app tests ran; no fix, shared cause, charge or release waiver is asserted.

## October 30 update — reproduced on TestFlight 1.0 (50); cause not established, no fix

Owner reproduced: Free → offline Restore error → reconnect → Monthly purchase fails on the first attempt with the not-unlocked message; the second attempt succeeds. Build 50 is commit `4d7cabd`. The later `8fa0e61` changes only affect Xcode-environment transactions, so they don't change sandbox behavior.

Code tracing (implementer plus an independent reviewer) found no app state left behind by a failed restore. Restore resets `isPurchasing` and sets only the error message, and the entitlement-refresh ordering cannot produce this failure. The message means StoreKit returned `.success` but the following `currentEntitlements` read did not show active Plus. Hypotheses, none confirmed:
- StoreKit returned an earlier transaction (the October 23 success-without-sheet sandbox behavior).
- The entitlement read lagged the new transaction.
- Free-tier simulation was still on.

A regression test confirms the app-side state does not block the next purchase. It cannot model StoreKit itself. Next evidence: immediately after the failed first attempt, copy Diagnostics' recent breadcrumbs (`restore_failed`, `purchase_start`, `storekit_purchase_success` with reason/purchased/expires, `purchase_outcome … store= sim=`) and note whether Apple's payment sheet appeared.

## Owner verification — no longer reproducing on TestFlight 1.0 (51)

The full sequence passed on build 51: the first Monthly purchase after reconnecting succeeded. The owner accepted this as resolved, given the earlier consistent failure on build 50. No build 51 change targeted the purchase path, so the cause remains unidentified. If the not-unlocked message returns, capture the breadcrumbs listed above before retrying.
