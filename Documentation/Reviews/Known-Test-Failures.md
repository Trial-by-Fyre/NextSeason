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

**Update, November 4, 2026 — owner approved deferral to V2:** The manual nightly run at revision `61441321f0c0779fdfdfb57655b365dbe74621e6` reported the same two Dynamic Type issues on iPhone 16 Pro / iOS 18.6; the test passed on iOS 26.5 and 27.0. During manual inspection at a large accessibility text size, the owner confirmed all content was reachable by scrolling and Large Content Viewer worked for Cancel and both tabs. The owner's Watchlist no-matches screenshot showed enlarged, readable search text and description, with the full description visible. No user-visible defect was identified in that inspected state; this does not establish correct scaling at every text size or prove the audit findings are false positives. Further investigation is postponed to V2 and is not a V1 blocker by owner decision. Keep the audit test active and the known failure open; no audit exception is added. Revisit sooner if unreadable, clipped, or unreachable content is reported. V2 follow-up: isolate the remaining search-control finding and check description scaling across text sizes on iOS 18.

## StoreKit 4C — Plus before Ask to Buy approval after relaunch — resolved October 30

**Original October 28 record:** Manual failure observed by owner on October 28, 2026: NextSeason 1.0 build 50, iPhone 18 Pro Max / iOS 27.0 simulator, local Xcode StoreKit. Free/no complimentary access was confirmed before the purchase; the manager still showed pending approval after relaunch granted Plus. Read-only logs show local StoreKit returning a current entitlement before the app finishes the transaction, alongside an unknown-transaction-state diagnostic. Cause and production applicability remain unresolved. No fix, pass, or release waiver recorded. See [evidence and investigation](StoreKitPendingRelaunch-2026-10-28.md).

**Current disposition, October 30:** The Xcode-only consistency guard and transaction recovery changes are implemented and independently reviewed. After the purchase-outcome/cancellation follow-up, the owner confirmed fresh 4C and normal Xcode purchase/simulation completion passed. The existing approved transaction also recovered Plus and cleared its unfinished warning. The owner deleted the prior test transaction to establish fresh purchase state. This closes the observed fresh-purchase 4C failure for the tested candidate; repurchase after expiry/refund, existing-access plan changes, approval while closed and decline remain separate verification items. The focused run passed 83 tests; no full-suite or broader release pass is inferred. See [implementation, review and acceptance evidence](StoreKitXcodePendingGuard-2026-10-30.md).

## StoreKit 4D / SK-08 — Declined purchase reported as successful — resolved October 30

**Original October 28 record:** Owner report, October 28, 2026, during the local Xcode testing session: a new purchase was declined in the transaction manager, but NextSeason recorded a successful purchase. Exact success presentation, resulting access/show state, plan, reset state and transaction ID remain unconfirmed. Added the missing focused decline case as 4D; the broader SK-08 already included decline. Status: open manual failure report, not independently reproduced or fixed; no shared cause with 4C assumed. See [additional observation and coverage](StoreKitPendingRelaunch-2026-10-28.md#declined-purchase-reported-as-successful).

**Current disposition, October 30:** The owner confirmed the current transaction recovery/purchase-outcome changes also resolved the observed failure in 4D. Record focused 4D as passed on the owner's report. No new console evidence was supplied, and no exact shared mechanism with 4C or pass of every broader SK-08 branch is inferred. See [acceptance evidence](StoreKitXcodePendingGuard-2026-10-30.md#owner-verification-decline-failure-resolved).

## StoreKit 7C — Monthly first-attempt failure for an already-saved show — no longer reproducing October 30

**Original October 28 record:** Owner report, October 28, 2026: buying Monthly Plus to add/reactivate a show already on the Watchlist produces Couldn't Complete Purchase on the first attempt; the second try succeeds. Previously intermittent elsewhere, reported as apparently consistent in this scenario. Exact build/device/environment and transaction cause remain unconfirmed. Status: open owner-observed failure, not independently reproduced or fixed; no shared cause with 4C/4D assumed. See [report and screenshot](StoreKitMonthlyFirstAttempt-2026-10-28.md).

**Current disposition, October 30:** The owner reports 7C passed on the first attempt with an Xcode build in the simulator (local Xcode StoreKit). The owner accepted this as resolved. That environment includes `8fa0e61`'s Xcode-only transaction delivery changes. They may explain the result, but no mechanism was confirmed, and the original 7C environment was never recorded. 7C was not rerun on TestFlight/sandbox. If the message returns, capture Diagnostics breadcrumbs (`storekit_purchase_success`, `purchase_outcome`) before retrying.

## StoreKit 8C — Purchase failure after network recovery — no longer reproducing October 30

**Original October 28 record:** Owner report, October 28, 2026: after offline Restore fails, restoring the network, dismissing the error and retrying a purchase produces “The purchase wasn't completed, so NextSeason Plus wasn't unlocked. Please try again.” Reported as apparently repeatable; exact control/plan, transaction result, build/environment and eventual recovery remain unconfirmed. Open functional recovery failure, separate from 8C's wording improvement; no common cause with 7C assumed. See [sequence and screenshot](StoreKitReconnectPurchaseFailure-2026-10-28.md).

**Current disposition, October 30:** The owner reproduced the failure consistently on TestFlight 1.0 (50). On TestFlight 1.0 (51) the full sequence passed: the first purchase after reconnecting succeeded. The owner accepted this as resolved. No change in build 51 targeted the purchase path. The 8C restore-message fix changed only wording and logging, and `8fa0e61` affects only Xcode-environment transactions. The cause is therefore unidentified (possibly sandbox account or StoreKit state). Watch for recurrence; if it returns, capture Diagnostics breadcrumbs immediately. The restore wording improvement was verified in the same run. See [investigation](StoreKitReconnectPurchaseFailure-2026-10-28.md).

## newerNotificationSupersedesOlderLookup — intermittent hang; disabled November 4

Failure: `ContentViewNotificationNavigationTests/newerNotificationSupersedesOlderLookup()` exceeds its 1-minute time limit.
Environment: iPhone 18 Pro Max / iOS 27.0 simulator, November 4, 2026. Reproduced with only this test running, and on committed code with all uncommitted work stashed. Intermittent: failed all 3 runs without trace logging (one with only a passive state dump), passed 4 runs with trace logging (which shifts timing), and passed once in an owner run. Test added in `286abd5` (October 19).
Evidence (temporary diagnostics, all reverted): at the hang, show 82's lookup is held as intended, but show 83 is still in `pendingShowID`; `ContentView`'s `onChange(of: pendingShowID)` never started a resolve for it. In passing runs SwiftUI re-rendered between the first request being consumed and the second being queued. Likely cause (not confirmed from a failing trace): when the second request arrives before that re-render, SwiftUI does not observe it, consistent with `onChange` comparing values between renders rather than reporting every assignment.
User impact: very unlikely. It needs two routing requests within the same main-thread turn; taps cannot arrive that close, and the launch buffer holds one. If it happened, the app would open without navigating to the show; nothing is lost.
Disposition: test disabled with `.disabled(...)`; owner accepted deferral. Proper fix (start navigation from the coordinator/routing instead of a view `onChange`, with a medium-risk scenario checklist) is on the [Product Evolution Roadmap](../Post-MVP/NextSeason%20-%20Product%20Evolution%20Roadmap.md#continuous-improvement). Re-enable the test with that fix.

## Local pending Annual with existing Monthly — open November 3

Owner observed three-show mode immediately after selecting Ask for Annual while previously on Monthly. Approval did not restore Plus until switching away and back. Exact Monthly validity at Ask and transaction/status payloads remain unconfirmed; no cause, fix, or production applicability is established. See [failure record](StoreKitPendingPlanChange-2026-11-03.md).

## manualSwitchToSearchReturnsToRoot — intermittent timeout; test fix applied November 6

Failure: `ContentViewNotificationNavigationTests/manualSwitchToSearchReturnsToRoot()` exceeds its 1-minute time limit.
Environment: nightly runs on iPhone 16 Pro / iOS 18.6 (November 3 and 4) and iPhone 17 Pro / iOS 26.5 (November 5 and the November 6 11:11 manual run): 4 of 8 runs since November 3. Passed on iOS 27.0 in each of those runs. The first failure predates the last changes to the test, `ContentView` and `WatchlistView` (November 4).
Evidence: in the failing November 6 log, the first leave-Watchlist commit (`watchlist_commit_on_leave_tab`) ran, but the second (the switch back to Search that commits the pending removal) never did, and no `watchlist_write_remove` followed. The passing iOS 27.0 run in the same nightly logged both commits about 0.4 s apart. The attached spindump had no samples.
Likely cause (not confirmed from a trace): the test waited for a total of two `watchlistViewed` events after returning to Watchlist. If mounting had already recorded two, the wait passed before Watchlist reappeared; the Watchlist → Search selections then landed in one main-actor turn, `onChange(of: selectedTab)` saw no change, and the outcome wait hung. Same `onChange` coalescing as `newerNotificationSupersedesOlderLookup` above.
User impact: none expected; real tab taps cannot arrive within one main-thread turn.
Disposition: test now waits for a new `watchlistViewed` event from Watchlist’s `onAppear` after selecting Watchlist again. This confirms another appearance callback ran before the switch to Search. The cause of the earlier timeouts remains unconfirmed. Passed once in isolation (iPhone simulator, November 6); one pass is not evidence for an intermittent failure. Watch the next nightly runs; if it times out again, capture which wait is pending before changing anything else.


**Recurrence, November 8:** The November 8 02:00 nightly (`63166f98a9`, including the November 6 test change) timed out again on iPhone 16 Pro / iOS 18.6; iOS 26.5 and 27.0 passed. The failing log again has the first leave-Watchlist commit but no second commit before the timeout. The spindump contains “No samples,” so the pending wait is still unknown. Three focused repetitions on the same iOS 18.6 simulator passed on November 8; this does not establish a fix. Added cancellation-only diagnostics to the test to record its current wait, selected tab, Search depth, pending removal, outcomes, and analytics events on recurrence, without trace output during normal execution. App behavior is unchanged. A further setup race is suspected: the test pushes Search detail immediately after selecting Search, while the initial selection's deferred return-to-root work can still clear that path. Confirm the stalled wait before changing synchronization. Status: unresolved, awaiting a failure with the added diagnostics; no v2 deferral recorded for this test.


**Manual full-matrix verification, November 8:** With the uncommitted cancellation-only diagnostics included in a working-copy snapshot, this navigation test passed on iOS 18.6, 26.5, and 27.0. The run had the listed iOS 18.6 accessibility failure and a separate iOS 26.5 populated-Watchlist test setup failure (Search did not show Severance); iOS 27.0 passed completely. The timeout remains unresolved and the failure diagnostic path is unverified. See [full run report](2026-11-08-navigation-diagnostic-full-suite.md) for counts, artifacts, and environment differences.


**Second manual full matrix, November 8:** Run `2026-11-08_112555` used the same saved diagnostic source snapshot. This navigation test again passed on all three versions. iOS 26.5 and 27.0 passed completely; only the listed iOS 18.6 Dynamic Type failure recurred. The earlier iOS 26.5 Search setup failure did not recur. No fix to either intermittent symptom is established; see the [updated full run report](2026-11-08-navigation-diagnostic-full-suite.md).
