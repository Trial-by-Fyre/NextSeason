# Permanent complimentary Plus for beta testers

## Final beta distribution

Select the shared **NextSeason - Final Complimentary Beta** scheme and Archive. Its archive action uses the dedicated `BetaComplimentary` configuration, cloned from Release with the same bundle identifier and signing team. Only `Config/BetaComplimentary.xcconfig` enables `COMPLIMENTARY_PLUS_BETA_GRANT`. Use ordinary App Store Connect distribution so existing external testers can receive it.

The normal **NextSeason** scheme still archives using Release. Debug, Release, and Profile have no grant flags. The app’s always-running `Verify complimentary Plus build` phase rejects either grant flag outside `BetaComplimentary`, checking both `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and `OTHER_SWIFT_FLAGS` (including command-line overrides). A Swift compile-time guard also rejects the grant flag without the dedicated configuration marker. Do not bypass these guards.

`TemporaryBetaPlusGrant` first checks the verified app transaction. A verified sandbox transaction grants access; verified production/Xcode transactions and failed verification reject access even if the receipt suggests TestFlight. If the transaction lookup throws an availability error, only the dedicated granting beta may use the `sandboxReceipt` channel signal as fallback (the same signal used by Diagnostics). This receipt path is not cryptographic verification. Cancellation does not grant access. Failed eligibility detection retries when the app becomes active; a tester must run the granting beta with successful detection before moving to production. No version or build number is used, and watchlist size does not affect eligibility.

Grant checks now record `complimentary_plus_*` breadcrumbs in the existing Diagnostics export: disabled granting, verified environment and eligibility, verification failure, lookup error domain/code, cancellation, and receipt fallback eligibility. No transaction payloads or account identifiers are logged. If a phone remains free, background/reopen the app, then copy/share the Diagnostics report to see the decision.

## Cleanup after distributing the final beta

Normal production archives are already safe, even before this cleanup. After the final beta has been distributed:

1. Delete the **NextSeason - Final Complimentary Beta** shared scheme.
2. In Xcode’s project Info tab, delete **BetaComplimentary** from the build configurations (project and all targets).
3. Delete `Config/BetaComplimentary.xcconfig`.

Keep `PlusEntitlementStore`, `ComplimentaryPlusPersistence`, their PurchaseService integration, and the build/compile-time guards. `TemporaryBetaPlusGrant` can remain dormant: with the grant condition absent, eligibility returns false without contacting StoreKit. Subsequent TestFlight and production archives use the normal **NextSeason** scheme.

Run `python3 Scripts/tests/test-complimentary-plus-build.py` before distribution and after cleanup to check the configuration boundary and injected-flag rejection.

These guards prevent a normal configuration from compiling the grant. They do not stop someone selecting an already-uploaded final beta build for App Store submission; submit a new normal Release archive instead. The runtime production-environment check remains a second barrier.

## Permanent recognition and persistence

Existing `plusGrandfathered == true` migrates unconditionally, including users whose old evaluation already ran. The old evaluation flag alone confers no access. The new entitlement is a permanent Boolean, separate from StoreKit subscriptions, purchases, tips, restoration, and subscription lapses. It has no renewal or expiration date.

UserDefaults is the local cache and migration source. A synchronizable app-private Keychain item provides best-effort recovery after reinstall and through iCloud Keychain on replacement devices. Reads never revoke an existing grant; failed writes retry on subsequent launches/activation. Keep the bundle identifier, signing team/access group, and Keychain service/account stable between beta and production. Device replacement depends on iCloud Keychain availability and sync; deletion of both copies cannot be recovered without an account/server. App Store Restore Purchases restores actual purchases only.

Before distributing: run the designated archive on a physical TestFlight device, verify complimentary status with an empty watchlist, then test production recognition, reinstall recovery, and (with iCloud Keychain enabled) another device. Simulator/mocked tests cannot establish real signing or iCloud synchronization behavior.
