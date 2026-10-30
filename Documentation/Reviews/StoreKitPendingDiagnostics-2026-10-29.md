# Pending Ask to Buy relaunch: diagnostic follow-up

**October 29, 2026. Status: unresolved; focused 4C remains failed. Diagnostic instrumentation only.**

The owner again reports Plus before approval after relaunch. This supplements the [October 28 evidence](StoreKitPendingRelaunch-2026-10-28.md); it does not replace or close that record. No safe entitlement workaround has been established.

## Findings

Read-only unified logs from the owner's iOS 27.0 simulator show Monthly transaction **5** generating `Can't compute renewal state ... s:2: unknown transaction state!` at 20:13:46 and 20:14:02 America/Los_Angeles. At 20:14:02.604 NextSeason receives `transaction_update ... new=true customerPurchase=true`. The same StoreKit error recurs at 20:21:41, 20:34:31 and 20:34:39. These logs support the previously observed discrepancy, but do not independently prove the transaction manager's approval state or the complete signed transaction identity.

Xcode's active scheme was observed as `SKTesting` with iPhone 18 Pro Max as destination. Its configuration references `SKTesting.storekit`, which enables Ask to Buy. The current simulator transaction was not approved, declined, deleted, or reset by this investigation.

The production client derives paid access from verified `Transaction.currentEntitlements`. Its pending purchase branch does not grant access. Apple documents that sequence as the entitlement source, pending completion through transaction updates, and declined Ask to Buy producing no transaction. This makes the contradictory StoreKit response the central unresolved question; it does not establish an Apple defect or production applicability.

## Diagnostic changes

`StoreKitPurchaseStoreClient` now supports the Debug-only launch argument `-StoreKitPendingDiagnostics`, enabled in the `SKTesting` scheme. It records:

- Verified Plus entitlement and update transaction IDs, product, original ID, reason, purchase/signed/expiration/revocation dates, upgrade flag, environment and ownership.
- Subscription group status count and state, verification result and transaction identity, correlated with the queried transaction ID.
- Status query errors by domain/code without treating them as entitlement decisions.

Update evidence is captured before delivery and `finish()`. Full signed payloads, account IDs and verification nonces are not logged. Release access decisions and persistence are unchanged. The existing purchase-success diagnostic output is preserved through a shared formatting helper.

**Timing limitation:** with this argument enabled, the status query is awaited before entitlement resolution or update delivery/finish. A slow or stalled query delays those paths. These runs are timing-instrumented evidence and must not be represented as identical to uninstrumented lifecycle timing. Other schemes without the argument do not perform these extra queries.

Run focused 4C through Xcode with `SKTesting`. Before approving, capture the manager's pending ID/status, About access state, and console lines beginning `storekit_entitlement`, `storekit_update_before_finish`, and `storekit_status`. Compare the same ID after approval. If pre-approval access is already Plus, preserve evidence before further actions. Do not mark this case passed merely because access is eventually available.

## Review and risk

Any change to transaction acceptance/access is **high risk** because incorrect grants and blocked legitimate restores are consequential. Independent design review found no current basis for a workaround. A persistent blanket pending denial can block approval while the app is absent or on another device; `.pending` does not supply a transaction ID. A status guard requires proof that it distinguishes the same pending/approved transaction, preserves grace/valid existing subscriptions, and handles query/verification failures. Filtering access while still finishing the rejected update could consume later approval delivery; same-ID duplicate handling must also be checked.

The abandoned add callback lives only in transient `@State` in `AppAboutPresentationModifier`. Process death discards it. Purchase recovery must not persist or reconstruct that operation.

| Scenario | Required result | Evidence/status |
|---|---|---|
| Ask, then relaunch before approval | Free, N untracked | Owner reports failure; instrumented rerun pending |
| Approve while closed or after relaunch | Plus, no abandoned add | Manual verification pending |
| Decline before/after relaunch | No new Plus or success | Existing 4D remains open |
| Existing valid Plus plus unrelated pending purchase | Existing access retained | Required before any guard |
| Normal purchase, renewal, restore, grace, expiry, revocation | Preserve existing policies | Required before any guard |
| Query/verification errors, overlapping reads, same-ID approval | No false grant/revocation; legitimate completion survives | Required before any guard |

A separate reviewer examined the diagnostic diff and found no blocking findings. Its requested per-line queried transaction correlation and timing limitation were incorporated. No high-risk entitlement behavior was implemented or accepted.

## Verification

A minimal independent app/UI-test probe was built outside the repository at `/private/tmp/NextSeasonPendingProbe`, using a separate iOS 27.0 simulator (`5EF7A1EA-0739-4151-9524-261DC57C4301`). It reads raw StoreKit entitlements/status without NextSeason logic and without `finish()`. The first attempt failed StoreKitTest setup (`SKServiceErrorDomain` 2, underlying `SKInternalErrorDomain` 4). One bounded retry with normal simulator signing and initial app launch failed at the test runner/automation launch level. These attempts did **not** establish a valid pending-purchase reproduction, approval result, or case pass. No further runtime comparisons were attempted.

The final `SKTesting` Debug build succeeded for the generic iOS Simulator destination with Xcode 27.0, including arm64 and x86_64. `git diff --check` passed. No app unit tests or full suite were run for this diagnostic-only change. The separate probe failed as described above; manual 4C/4D acceptance remains pending. The separate probe simulator is shut down; its source and failed run artifacts remain outside the repository for follow-up.

## Apple references

- [Current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements): includes active/grace subscriptions.
- [Purchase results](https://developer.apple.com/documentation/storekit/product/purchaseresult): pending completion becomes available through transaction updates.
- [Transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates): unfinished transactions are delivered at launch.
- [Testing Ask to Buy](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode): explicit approval/decline and no transaction for decline.
- [Subscription status](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status-swift.property): group-level status may contain multiple entries.
