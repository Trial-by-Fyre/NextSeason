Test: testShowDetailPassesAccessibilityAudit
Failure: “Severance” title reported as potentially clipped at larger text sizes.
Environment: fails on iPhone 16 / iOS 18.6; passes on iPhone 16 Pro / iOS 18.6.
Baseline: Claude reproduced it on ab78b37, before R02.
Disposition: open accessibility issue; investigate the layout before adding an audit exception.
During Rxx work: this exact failure in this environment does not block unrelated fixes. Report it as a known failure; investigate any different failure or changed symptom.
Follow-up: include it in our consolidated testing script.

## testWatchlistSearchNoResultsPassAccessibilityAudit — unresolved Dynamic Type issues on iOS 18

Failure: two “Dynamic Type font sizes are partially unsupported” issues with a nil element and empty label, so no label-based exception can match them. Attachments add nothing beyond the failure message.
Environment: iPhone 16 Pro / iOS 18.6, October 29, 2026. Passes on iPhone 17 Pro / iOS 26.5. Issue counts varied across runs (2 vs. 3) as unresolved contrast issues came and went.
Isolation (temporary edits, all reverted; one failing test per run):
1. Removing the title/description custom styling: still 2 issues.
2. Hiding the notifications banner: still 2.
3. Adding `.accessibilityElement(children: .contain)` to the no-matches view: still 2.
4. Replacing the whole no-matches view with a plain `Text`: 1 remains.
5. Original view without its description: 1 remains.
Reading: one issue comes from the no-matches description (independent of its styling); the other comes from outside the view — most likely the active watchlist search UI (search field with text and Cancel), since Watchlist empty with the same tab bar passes. Not proven to be false positives.
Disposition: open; no audit exception added. Next step: isolate the search UI (for example, audit with the search field inactive) and check whether the description's font actually scales at accessibility sizes on iOS 18.

## StoreKit 4C — Plus before Ask to Buy approval after relaunch

Manual failure observed by owner on October 28, 2026: NextSeason 1.0 build 50, iPhone 18 Pro Max / iOS 27.0 simulator, local Xcode StoreKit. Free/no complimentary access was confirmed before the purchase; the manager still showed pending approval after relaunch granted Plus. Read-only logs show local StoreKit returning a current entitlement before the app finishes the transaction, alongside an unknown-transaction-state diagnostic. Cause and production applicability remain unresolved. No fix, pass, or release waiver recorded. See [evidence and investigation](StoreKitPendingRelaunch-2026-10-28.md).

## StoreKit 4D / SK-08 — Declined purchase reported as successful

Owner report, October 28, 2026, during the local Xcode testing session: a new purchase was declined in the transaction manager, but NextSeason recorded a successful purchase. Exact success presentation, resulting access/show state, plan, reset state and transaction ID remain unconfirmed. Added the missing focused decline case as 4D; the broader SK-08 already included decline. Status: open manual failure report, not independently reproduced or fixed; no shared cause with 4C assumed. See [additional observation and coverage](StoreKitPendingRelaunch-2026-10-28.md#declined-purchase-reported-as-successful).

## StoreKit 7C — Monthly first-attempt failure for an already-saved show

Owner report, October 28, 2026: buying Monthly Plus to add/reactivate a show already on the Watchlist produces Couldn't Complete Purchase on the first attempt; the second try succeeds. Previously intermittent elsewhere, reported as apparently consistent in this scenario. Exact build/device/environment and transaction cause remain unconfirmed. Status: open owner-observed failure, not independently reproduced or fixed; no shared cause with 4C/4D assumed. See [report and screenshot](StoreKitMonthlyFirstAttempt-2026-10-28.md).

## StoreKit 8C — Purchase failure after network recovery

Owner report, October 28, 2026: after offline Restore fails, restoring the network, dismissing the error and retrying a purchase produces “The purchase wasn't completed, so NextSeason Plus wasn't unlocked. Please try again.” Reported as apparently repeatable; exact control/plan, transaction result, build/environment and eventual recovery remain unconfirmed. Open functional recovery failure, separate from 8C's wording improvement; no common cause with 7C assumed. See [sequence and screenshot](StoreKitReconnectPurchaseFailure-2026-10-28.md).
