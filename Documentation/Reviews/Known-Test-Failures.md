Test: testShowDetailPassesAccessibilityAudit
Failure: “Severance” title reported as potentially clipped at larger text sizes.
Environment: fails on iPhone 16 / iOS 18.6; passes on iPhone 16 Pro / iOS 18.6.
Baseline: Claude reproduced it on ab78b37, before R02.
Disposition: open accessibility issue; investigate the layout before adding an audit exception.
During Rxx work: this exact failure in this environment does not block unrelated fixes. Report it as a known failure; investigate any different failure or changed symptom.
Follow-up: include it in our consolidated testing script.

## StoreKit 4C — Plus before Ask to Buy approval after relaunch

Manual failure observed by owner on October 28, 2026: NextSeason 1.0 build 50, iPhone 18 Pro Max / iOS 27.0 simulator, local Xcode StoreKit. Free/no complimentary access was confirmed before the purchase; the manager still showed pending approval after relaunch granted Plus. Read-only logs show local StoreKit returning a current entitlement before the app finishes the transaction, alongside an unknown-transaction-state diagnostic. Cause and production applicability remain unresolved. No fix, pass, or release waiver recorded. See [evidence and investigation](StoreKitPendingRelaunch-2026-10-28.md).

## StoreKit 4D / SK-08 — Declined purchase reported as successful

Owner report, October 28, 2026, during the local Xcode testing session: a new purchase was declined in the transaction manager, but NextSeason recorded a successful purchase. Exact success presentation, resulting access/show state, plan, reset state and transaction ID remain unconfirmed. Added the missing focused decline case as 4D; the broader SK-08 already included decline. Status: open manual failure report, not independently reproduced or fixed; no shared cause with 4C assumed. See [additional observation and coverage](StoreKitPendingRelaunch-2026-10-28.md#declined-purchase-reported-as-successful).

## StoreKit 7C — Monthly first-attempt failure for an already-saved show

Owner report, October 28, 2026: buying Monthly Plus to add/reactivate a show already on the Watchlist produces Couldn't Complete Purchase on the first attempt; the second try succeeds. Previously intermittent elsewhere, reported as apparently consistent in this scenario. Exact build/device/environment and transaction cause remain unconfirmed. Status: open owner-observed failure, not independently reproduced or fixed; no shared cause with 4C/4D assumed. See [report and screenshot](StoreKitMonthlyFirstAttempt-2026-10-28.md).

## StoreKit 8C — Purchase failure after network recovery

Owner report, October 28, 2026: after offline Restore fails, restoring the network, dismissing the error and retrying a purchase produces “The purchase wasn't completed, so NextSeason Plus wasn't unlocked. Please try again.” Reported as apparently repeatable; exact control/plan, transaction result, build/environment and eventual recovery remain unconfirmed. Open functional recovery failure, separate from 8C's wording improvement; no common cause with 7C assumed. See [sequence and screenshot](StoreKitReconnectPurchaseFailure-2026-10-28.md).
