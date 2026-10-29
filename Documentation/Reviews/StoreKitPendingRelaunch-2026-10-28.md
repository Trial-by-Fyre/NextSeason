# StoreKit pending purchase grants access after relaunch

**Recorded October 28, 2026. Status: manual failure observed; cause not conclusively isolated; no fix or accepted limitation.**

## Observation

Owner ran focused StoreKit case 4C in the simulator. Free access was confirmed before purchase. The Monthly purchase remained pending approval in Xcode's transaction manager, but relaunching NextSeason granted Plus before approval. Owner confirmed the manager still showed pending approval after the unexpected grant. Complimentary access is not involved: application diagnostics report both `comp=false` and `storedComp=false` in the pre-purchase/pending state. No screenshot of the manager was captured by the agent; that status is owner-reported.

Environment observed through read-only diagnostics: NextSeason 1.0 build 50; booted iPhone 18 Pro Max simulator on iOS 27.0; local StoreKit configuration with Ask to Buy enabled. The repository has an `SK Testing` Debug scheme selecting `NextSeason.storekit`; the exact running Xcode application version was not independently established (27.0 and 27.1 RC are installed).

## Declined purchase reported as successful

**Additional owner report, October 28, 2026; focused case 4D / existing SK-08 decline branch.** The owner started a new purchase, declined the transaction in Xcode’s transaction manager, and NextSeason recorded a successful purchase. Expected: a declined Ask to Buy request must not report purchase success, grant Plus, or complete the blocked add.

This report is recorded alongside 4C because both involve pending-purchase resolution. It has not been independently reproduced or correlated with a specific transaction ID/log timestamp. The exact success indication, actual access/added-show state, plan, reset state and whether a relaunch occurred during the decline case were not supplied; do not infer them from the earlier 4C logs. The cause of either observation is not established, and a common cause has not been proven. Keep both observations open. No transaction state was changed by the agent to record this report.

A decline branch already existed in broader SK-08, but was missing from the focused cases 4A–4C. Added focused **4D** with explicit Free/reset/pending prerequisites, decline, no-success/no-add assertions, and a relaunch check. Existing case IDs are unchanged.

## Recorded timeline

Times below are October 28, 2026, America/Los_Angeles. Read via simulator unified logs without restarting, approving, declining, deleting or otherwise changing the owner's transaction.

- 14:58:18.958: NextSeason starts Monthly purchase with `unlimited=false`, `store=resolved(isEntitled: false)`, `comp=false`, `storedComp=false`, `sim=false`.
- 14:58:26.303: purchase returns `pending`, `verified=false`; access remains Free.
- 14:58:46.739: app relaunches.
- 14:58:50.894–.895: StoreKit receives queries for unfinished transactions and current entitlements in the local Xcode test context.
- 14:58:50.925: storekitd reports `Can't compute renewal state for transaction [4]` for Monthly, ending `unknown transaction state!`.
- 14:58:50.927–.928: current-entitlement and unfinished queries each return one transaction. These responses precede the app's finish request.
- 14:58:50.973: NextSeason receives a verified Monthly transaction update (`new=true`, `customerPurchase=true`).
- 14:58:51.312–.315: another current-entitlement query returns one transaction.
- 14:58:51.373–.374: the app requests finishing transaction 4.
- 14:58:51.499: NextSeason logs a duplicate update (`new=false`). StoreKit subsequently reports transaction 4 already finished.

Similar pending-then-relaunch/update sequences appear in earlier attempts at 14:53–14:54 and 14:55–14:56. They are supporting diagnostics, not separate agent-controlled reproductions or independent passes.

## Code-path findings and limits

`PurchaseService` starts each production service instance with entitlement state `.loading`; it does not persist paid access as a launch default. Its `.pending` purchase branch does not grant Plus. Effective access also permits complimentary entitlement, but the owner's setup and application logs rule out that explanation for the observed purchase.

`StoreKitPurchaseStoreClient` accepts verified Plus entries returned by `Transaction.currentEntitlements` and delivers verified `Transaction.updates` before calling `finish()`. `PurchaseService.handleVerifiedTransaction` refreshes entitlements; it does not directly equate a pending purchase with paid access. The local StoreKit service returning an entitlement while its manager still reports pending is therefore the primary discrepancy to investigate. The entitlement response occurs before the finish request, so finish alone does not explain the initial inconsistent response. The existing log does not expose the full signed payload or IDs for every entitlement response; do not claim that all identity/state questions are resolved.

This evidence points toward local StoreKit behavior but does not establish an Apple defect, a production exploit, or a safe app workaround. A verified transaction and a completed approval are different observations; the missing diagnostic comparison is the exact entitlement payload/transaction identity versus the manager's pending record and renewal status.

## Follow-up

- Keep focused **4C failed** for build 50; keep the related closed/relaunch SK-08 branch open. Do not mark it passed because the purchase eventually grants access.
- Preserve the pending manager state and diagnostic evidence before any reset. A screenshot showing its transaction ID/status and About Unlimited would strengthen the record.
- Next controlled investigation should compare the same pending transaction's ID, signed fields and subscription status across the pre-launch and post-launch queries. Use a separate disposable simulator/session so the owner's evidence is not overwritten.
- If the discrepancy is reproduced in local StoreKit, prepare a minimal reproduction for Apple and compare available Xcode/runtime combinations. An Apple report has not been submitted.
- Do not add a persistent app-side “pending means deny all access” workaround without reviewing successful out-of-app approvals, restoration, existing subscriptions and restart behavior. Such a payment-behavior change requires the repository's discovery/review process.

No app code changed, no app tests ran, no transaction was approved/deleted, and no production applicability or release waiver was inferred in this investigation. Existing stub-based pending tests are not proof of this real StoreKit relaunch behavior.

## References

- [StoreKit manual guide](../Post-MVP/NextSeason-StoreKit-Manual-Test-Script.md).
- [Apple pending purchase result](https://developer.apple.com/documentation/storekit/product/purchaseresult/pending): a later successful pending purchase is delivered through transaction updates.
- [Apple transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates): unfinished transactions are delivered at launch.
- [Apple Ask to Buy testing](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode): approval and decline are explicit test actions.
