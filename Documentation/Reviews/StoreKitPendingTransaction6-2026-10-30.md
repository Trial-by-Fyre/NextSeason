# Transaction 6: pending approval with an unknown subscription state

**October 30, 2026. Focused 4C remains failed; an [Xcode-only candidate guard](StoreKitXcodePendingGuard-2026-10-30.md) is now implemented, pending manual acceptance.**

The owner reran the diagnostic build and supplied the Xcode console, confirming that transaction **6** remained **Pending Approval** in the transaction manager. This manager state is owner-reported. The [selected console evidence](Attachments/StoreKit-6-Pending-Console-2026-10-30.txt) preserves the relevant lines in source order. This supplements the [diagnostic follow-up](StoreKitPendingDiagnostics-2026-10-29.md) and [original failure](StoreKitPendingRelaunch-2026-10-28.md).

## Observed comparison

All three StoreKit paths identify the same Monthly transaction:

- `storekit_update_before_finish`: verified update **id=6, originalID=6**.
- `storekit_entitlement`: verified current entitlement **id=6, originalID=6**.
- `storekit_status`: **queriedID=6, count=1, state=0, verified=true, id=6, originalID=6**.

Each reports `reason=PURCHASE`, `env=Xcode`, `ownership=PURCHASED`, `revoked=nil`, `upgraded=false`, purchase date `2026-10-30T20:00:17Z`, signed date `2026-10-30T20:01:13Z`, and expiration `2026-11-30T21:00:17Z`. These dates are UTC as logged. The first unknown-status response occurs before the first `transaction_update ... new=true` application callback, hence before that callback's subsequent `finish()`. Later repeated entitlement/status reads report the same identity and raw state. An update is subsequently logged as `new=false`.

The console also records `watchlist_set_paused:false:1` and `watchlist_resumed count=1`, showing an access-related side effect. This is resuming an existing paused show; it does not establish that abandoned show N was added. The supplied console does not independently establish N's identity or tracked state.

## Meaning of state 0

A read-only Swift program compiled against Xcode 27.0's iOS Simulator SDK was executed on the owner's booted iOS 27.0 simulator. It printed the named `Product.SubscriptionInfo.RenewalState` constants:

| Named state | Raw value on this runtime |
|---|---|
| subscribed | 1 |
| expired | 2 |
| inBillingRetryPeriod | 3 |
| inGracePeriod | 4 |
| revoked | 5 |

Raw **0** therefore matches none of these documented states on the tested runtime. It must not be described as subscribed, or assumed to be a documented pending-approval enum case. `verified=true` here describes signature verification of the status transaction, not approval or an active renewal state.

Apple documents [current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) as including auto-renewable subscriptions whose renewal state is subscribed or in grace period. The same transaction appearing there while its status is raw 0 is a concrete API discrepancy in this local Xcode test. It supports investigating the StoreKit test environment, but does not alone prove an Apple defect or production applicability.

The current app trusts verified current entitlements and does not consult renewal status for its access decision. This explains how #6 grants access despite the unknown status. A future guard is a candidate, not yet an accepted fix: it must preserve legitimate existing access, grace periods, query/verification failures, delayed approval, and same-ID transaction delivery. A rejected update must not be finished or marked processed in a way that consumes its later legitimate completion.

## Next evidence

After preserving the pending record, approve **#6** in Xcode and capture the console from approval onward plus the manager's resulting state. Determine whether the same ID transitions to subscribed (`1`), whether a fresh update is delivered after the app's earlier finish, and whether N remains untracked. If approval does not produce an update, relaunch and capture that result separately. Do not reset or create a replacement purchase for this comparison.

This turn only inspected supplied logs, read StoreKit constants, and recorded evidence. It did not approve, decline, finish, reset, or otherwise modify simulator transactions, or change app behavior. The controlled independent reproduction remains unavailable as recorded in the preceding review. No app tests or builds were run in this evidence-only follow-up.

## Post-approval comparison supplied later October 30

The owner approved #6; the manager changed to **Purchased**. The owner cleared the console before approval and reports no subsequent output while the app remained running. This does not prove why another update was absent.

The [subsequent relaunch console](Attachments/StoreKit-6-Approved-Console-2026-10-30.txt) now reports the same **id=6, originalID=6**, with **state=1** and a verified status transaction. Purchase and expiration dates are unchanged; signed date advances to `2026-10-30T20:06:50Z`. No transaction update appears in this supplied relaunch excerpt. The entitlement read alone recovers the subscription.

This establishes a **0 → 1** subscription-state transition for the same local test transaction across approval. It makes a status crosscheck a concrete fix candidate. It does not validate unfinished-update delivery after approval with a new guard; the earlier implementation already finished the premature update. A new pending purchase must exercise that path after implementation. Focused 4C remains failed until that verification passes.
