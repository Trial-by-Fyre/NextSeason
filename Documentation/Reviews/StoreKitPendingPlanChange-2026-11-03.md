# Pending Annual purchase with existing Monthly access

**Reported November 3, 2026. Status: open owner-observed failure; not independently reproduced.** Coverage: history-sensitive local pending plan change, SK-08/SK-11. No fix or release waiver is recorded.

## Reported sequence

During the local Xcode StoreKit test with existing Monthly Plus access, the owner opened the Annual purchase through the debug paywall entry point and selected Ask in the Ask to Buy dialog.

- Immediately after Ask, NextSeason changed to three-show mode.
- After Annual was approved, NextSeason did not immediately return to Plus.
- Switching to another app and back restored Plus.

This records the owner's observations, not verified StoreKit transaction payloads. Exact build, Monthly expiration at the time of Ask, transaction IDs, subscription status results, and elapsed approval-to-foreground time were not captured. The preceding test instructions specified simulation off and retained purchase history; actual switch state was not separately reported with the failure.

## Expected behavior and investigation

A pending Annual purchase must not remove an independently still-valid Monthly entitlement. Whether Monthly was still valid at that instant needs confirmation from its verified expiration/status, particularly with accelerated local renewals. Once a verified approved transaction supplies active access, the running app should apply it without requiring a foreground return.

Investigate the two observations separately: (1) local subscription-status/history interpretation while a replacement purchase is pending, and (2) transaction update/retry delivery and entitlement application after approval. No shared cause or production applicability is established. The existing Xcode-only validation guard and transaction delivery queue are relevant starting points, not established causes.

Preserve the current local transaction history and any available logs before resets. Useful existing breadcrumbs include `storekit_entitlement`, `storekit_status`, `storekit_update_before_finish`, `transaction_update`, and finish/recovery diagnostics when enabled. A new manual repeat is not requested by this record. Prefer controlled investigation before requesting additional owner testing.

Any payment/access behavior change must follow the repository's high-risk discovery, independent design review, focused verification, and independent acceptance requirements. This report alone does not establish a safe fix.


## Owner disposition — November 3, 2026

The owner stated that this exact sequence is not accessible to regular users and is not a significant concern. Investigation is deferred with owner agreement as a known local-test limitation. It requires Xcode Ask to Buy simulation and a debug-only paywall entry point. No fix/pass or production plan-change failure is inferred. Do not require another owner run of this sequence as a release check absent new evidence of relevance to supported user flows.
