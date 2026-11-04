# StoreKit testing reconciliation — November 2, 2026

This is a reading aid and evidence audit, not a new test suite or a release waiver. The owner reports completing the focused testing. The canonical checklist's result sheet is blank; missing written evidence does not mean a test was not performed. No tests were run for this audit. Existing results apply to their recorded candidate/environment, not automatically to every future build.

## Preserve these recorded passes

| Check | Recorded outcome |
|---|---|
| Focused 4C: pending → relaunch → approval while running | Owner passed the updated October 30 candidate. Do not repeat solely because the October 28 checklist still says “Open failure.” |
| Focused 4D: decline | Owner confirmed fixed/passed October 30. The checklist's open-failure warning is stale. |
| Normal local purchase ends simulation; existing approved transaction recovers and finishes | Owner passed October 30. |
| Focused 7C: Monthly first attempt for a saved show | Owner passed in local Xcode/simulator October 30; accepted as resolved. TestFlight equivalent remains unverified. |
| Focused 8C: offline Restore → reconnect → first purchase | Owner passed TestFlight 1.0 (51), including improved restore wording. Accepted as resolved; underlying cause was not established. |

Sources: [updated-candidate and decline acceptance](StoreKitXcodePendingGuard-2026-10-30.md#owner-verification-updated-candidate-checks-passed), [failure dispositions](Known-Test-Failures.md), [7C](StoreKitMonthlyFirstAttempt-2026-10-28.md), [8C](StoreKitReconnectPurchaseFailure-2026-10-28.md).

## Credit focused testing once

For focused cases the owner completed successfully, reuse those observations for the matching broader cases. The repository does not contain individual results for all of them; these are overlap mappings, not newly asserted passes.

| Completed focused case | Broader coverage to credit | Only additional branches to consider |
|---|---|---|
| 1–3: presentation, purchase, cancel/failure | SK-01/02/04–07 | Legal links/disclosures; both product environments; Annual success if only Monthly was bought; tip error/cancel if not already done; purchase survives relaunch |
| 4A–4D: pending | SK-08 | Approval while the app is **closed**, then launch; differs from approval after relaunch |
| 5–6: expiration | SK-12–14 | Paused removal/Undo, acknowledged-alert persistence, closed-app lapse and an actual scheduled background run if delivered |
| 7: resubscription/reactivation | SK-17 | Second lapse; TestFlight saved-show first-attempt purchase if only local 7C was done |
| 8B–8D: Restore | SK-18 | Active-account Restore and repeated taps, if not observed |
| 9: tips | SK-23 | All three products, same tip twice, paid/complimentary states, relaunch/Restore without duplicate thanks |
| 10: simulation | SK-25 | Restore/tip/cancel/failure leave simulation on; pending approval from an earlier simulation session cannot end a newly started session |
| Beta notification-settings walkthrough 10 | SK-29 | Reuse same-build result; no duplicate settings walkthrough |

## Prioritized remaining checks

Suggested order reflects payment/access and saved-data consequences. These remain verification gaps unless matched to an existing observation. Priority is not permission to omit the later checks.

### First: access can change outside a normal purchase

1. **SK-15: refund.** In local Xcode, paid with more than three disposable saves, simulation off, Ask to Buy/errors off, no other active subscription. Ignore Complimentary Plus must be on when applicable (re-enable after relaunch). Refund the active transaction in Manage Transactions. Check while running, after foreground return and after relaunch: three oldest active, extras preserved/paused, fourth new addition blocked. This is local refund evidence, not a sandbox refund pass.
2. **SK-08 closed-app approval.** Start pending, close app, approve in the manager, then relaunch. Plus appears; abandoned add does not resume. Existing 4C does not cover this order.
3. **SK-11/16: renewal, plan changes, billing failure/recovery.** On device, observe a renewal and effective Monthly↔Annual changes without lost access/data. Exercise failed renewal, eventual lapse and recovery. Grace-specific steps apply only if grace is configured; retry/lapse/recovery still apply without grace. Check current App Store Connect settings rather than assuming them.
4. **SK-20/21: offline entitlement lifecycle.** Check an existing subscriber offline before expiration, then separately expiration offline followed by reconnection. No deletion or false Plus grant; definitive inactive access eventually pauses extras. Offline Restore 8C alone does not cover these.
5. **SK-19: reinstall recovery.** Use a disposable installation, exporting valued data first. Same purchase account recovers Plus; purchase restoration is not watchlist restoration. Second-device branch requires another device.
6. **History-sensitive local pending purchases.** The October 30 review explicitly leaves repurchase after expiry/refund and pending plan changes with existing access unverified. Preserve transaction history for these; deleting all history would defeat the check. Record existing access and transaction state; pending must not create new access before approval or remove still-valid existing access. See the October 30 review's remaining platform scenarios.

### Next: short recovery and interaction checks

- **SK-03:** local product-load error → Try Again; existing access/saves survive catalog failure.
- **SK-09/10:** interrupted sandbox purchase and rapid taps/background/return; no premature access, duplicate app purchases or stuck controls.
- **SK-22:** paused-show reactivation after freeing a slot, Undo and three-show cap. Reuse any identical beta observations.
- Fill only the unobserved branches in the overlap table: especially TestFlight saved-show first purchase, all tip products/repeat tip, and Restore repetition.
- **SK-30:** alternate sandbox storefront app price agrees with Apple's sheet; restore account region afterward.

### Release integration and equipment-dependent work

- **SK-24:** an existing complimentary grant survives a normal non-granting update and paid expiry/refund; a fresh normal installation receives no new grant.
- **SK-26/About:** Release build excludes testing controls/new beta grants; large text/VoiceOver keep prices, status and actions usable. Actual App Store installation check happens when available, not through TestFlight.
- **SK-27:** retained notification opens appropriate destination after target removal/pause, including cold launch with actual inactive access. Reuse ordinary active-target beta routing evidence.
- **OC-11:** reuse purchase/restore/foreground observations from the above; manual timing does not prove deterministic entitlement ordering.
- Second device, actual iOS-scheduled background execution, and non-complimentary cold-launch setup depend on available equipment/system scheduling. Record Not run/Blocked with the reason; do not keep attempting to force them or infer a pass.

## Work owned by engineering

Do not attempt forced internal states by repeatedly toggling Airplane Mode or tapping faster. Unverified signatures, held/stale entitlement reads, exact add/Undo races, controlled provider catch-up and temporary Keychain failures belong to the [engineering coverage record](StoreKitEngineeringCoverage-2026-10-28.md). It lists tests and unresolved evidence requirements; test source alone is not a current-candidate pass. The October 30 record establishes 83 focused passing tests in six suites, not full coverage of every engineering row. Full-suite execution remains owner-controlled.

## Recording the remainder

Use the [existing checklist](../Post-MVP/NextSeason-StoreKit-Manual-Test-Checklist.md) for exact setup/cleanup. Record each new result once with build/environment. Keep original historical reports unchanged; use later acceptance above to interpret stale open-failure text. No release requirements are waived by this prioritization. Any decision to ship with material unverified behavior remains the owner's decision.


## Owner completion update — November 3, 2026

The owner reports finishing **Short recovery and interaction checks** and confirms that all tests under **Release integration and equipment-dependent work** were already performed in previous rounds. Credit those reported completions; do not request repetition solely because the original result sheet is blank. No new per-case build, environment, or outcome detail was supplied with this section-level report, so it does not independently establish a current-candidate pass for every branch or close engineering evidence gaps.

The owner explicitly accepts deferring investigation of the local pending Annual/existing Monthly issue because the exact sequence uses Xcode Ask to Buy simulation and a debug-only paywall entry point. Preserve it as a known local-test limitation, not a fixed or passed scenario; production applicability remains unestablished. See [report and disposition](StoreKitPendingPlanChange-2026-11-03.md).

The separately reported offline-expiration reconnection observation remains unresolved: switching away/back after reconnecting retained Unlimited; restart with complimentary access excluded recognized expiration. This completion update does not establish a fix or waive investigation of that separate observation. Normal automatic renewal was not directly verified from the date-only subscription display. Grace-specific testing was not applicable because Billing Grace Period was disabled. These specific qualifications remain alongside the section-level completion report.
