# StoreKit engineering coverage and remaining evidence

**Updated October 28, 2026.** This is an engineering coverage record, not a manual test assignment. The [manual guide](../Post-MVP/NextSeason-StoreKit-Manual-Test-Script.md) contains steps achievable through app actions or documented Apple test controls. Its [checklist](../Post-MVP/NextSeason-StoreKit-Manual-Test-Checklist.md) excludes requirements needing custom control of internal state, provider data, or request timing.

Moving a case here does not pass it, waive it, or establish release readiness. Record current-candidate automated results and any missing integration/UI evidence. Existing test files are starting points, not executed results. Add a case back to the manual script only after there is a repeatable setup with concrete instructions. This change does not authorize building new test modes or running full suites.

Documentation change risk: medium, because coverage must remain traceable while the executable script is simplified. Verification: preserve moved requirements/IDs, review actionable setups against Apple documentation and repository configuration, compare the guide/checklist, and check local links. No application behavior, product policy, release decision, or test outcome is changed.

## Coverage register

| Earlier manual location | Engineering responsibility / available starting point | Evidence still needed |
|---|---|---|
| Focused 3C | Success reported without effective Plus; PurchaseSuccessWithoutAccessTests.swift | Candidate logic results; integrated paywall message, preserved blocked add, and later recovery. No manual UI setup currently supplied. |
| Focused 8A / SK-18.5; restore alternative in 7B | Valid entitlement deliberately withheld from automatic recognition until Restore | Repeatable controlled setup and UI evidence that Restore dismisses the paywall and adds/reactivates the intended row once. Ordinary About Restore cannot establish this branch. |
| About status forced states | PlusAccountPresentationTests.swift; PurchaseServiceTests.swift | Forced first-read uncertainty, active/inactive recovery, restore errors, complimentary precedence, simulated loading, and readable integrated UI. Offline success is not uncertainty evidence. |
| SK-27 controlled portions | SubscriptionDowngradeTests.swift; SubscriptionDowngradeRefreshTests.swift | Controlled active/paused fetches, silent catch-up, retry/Undo marks and suspended stale completions. Device routing smoke remains in manual SK-27. |
| SK-28; precise SK-22 races | WatchlistAdmissionAndDebounceTests.swift; FreeTierReconciliationTests.swift | Both exact add/Undo orders, cap invariants, fixed soft-alert timestamps, and first-read uncertainty. Human rapid taps are not deterministic evidence. |
| SK-29 controlled event while permission denied | NotificationServiceTests.swift; NotificationAuthorizationPolicyTests.swift | Process a known provider change while alerts are disabled; enabling permission is not a promise to replay past changes. Ordinary Settings integration remains in beta walkthrough 10. |
| SK-30 verification failures | PurchaseServiceTests.swift; PurchaseServiceEntitlementOrderingTests.swift | Failed purchase verification grants nothing; entitlement uncertainty preserves the appropriate confirmed state. First establish a repeatable built-in verification-error setup or controlled test; no custom setup is supplied by the manual script. Storefront checks remain manual. |
| CV-06 / exact OC-11 ordering | See retained CV-06 requirements below | Candidate evidence for reversed scans, cancellation, bursts, unverified results, simulation ownership and newest-read stalls. Device observations do not prove request overlap. |
| Failed Restore in 8C / SK-18 | Recoverable thrown restore error and retry | Offline Restore may succeed from cached data. A successful offline Restore does not cover the error branch; record actual controlled error evidence separately. |
| SK-24 temporary Keychain failure | IgnoreComplimentaryPlusTests.swift; PurchaseServiceTests.swift | Already-recognized complimentary access survives temporary Keychain read failure. Ordinary online/offline launches do not force a Keychain error. |

## Success without access — retained requirements

#### 3C. Success reported without Plus access

**Developer-assisted; no manual TestFlight switch exists.** A stale-success fixture makes a purchase report success while leaving Plus inactive. Automated service coverage exists in `NextSeasonTests/PurchaseSuccessWithoutAccessTests.swift` using `reportsStaleSuccess`, but it does not by itself prove the paywall and blocked-add UI steps below. Mark the manual case **Blocked — manual fixture unavailable** unless a developer supplies a UI fixture; record actual automated results separately.

- Simulate a purchase reporting success without Plus entitlement becoming effective.
- Verify the paywall stays open.
- Verify the app explains that Plus has not been unlocked.
- Verify N remains untracked.
- Perform a subsequent genuine successful purchase.
- Verify Plus unlocks and N is added exactly once.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

## Restore during a blocked add — retained requirements

#### 8A. Restore valid Plus during blocked add

- Arrange for a valid Plus entitlement that NextSeason has not yet recognized.
- Start with N untracked and three active shows.
- Attempt to add N.
- On the paywall, select Restore Purchases.
- Verify valid Plus access is recognized.
- Verify the paywall dismisses.
- Verify N is automatically added exactly once.
- Verify the Watchlist remains intact.

If the necessary entitlement state cannot be reproduced, mark Blocked.

## About status — controlled presentation requirements

#### About Plus status acceptance checks

Use the same build for each state. Restore Purchases stays visible throughout; it is temporarily disabled while a purchase/restore is in progress. Initial loading may finish too quickly to observe visually; record that rather than assuming a mandatory visible delay.

| State | Status | Footer / action | Upgrade button |
|---|---|---|---|
| First entitlement read loading, no complimentary access | Checking… | Confirming your NextSeason Plus status. | Hidden |
| First read unverified, no complimentary access | Unable to Verify Plus | Verification-uncertainty guidance below; Restore Purchases available | Hidden |
| Confirmed free | Up to 3 shows | NextSeason Plus removes the watchlist limit. | Visible |
| Confirmed paid | Unlimited | You have NextSeason Plus. | Hidden |
| Complimentary without confirmed paid access | Unlimited | You have permanent complimentary NextSeason Plus. Thank you for beta testing. | Hidden |
| Simulate Free Tier enabled | Up to 3 shows (simulated) | Simulation guidance and instructions to turn it off in Diagnostics | Hidden during the first StoreKit read; visible after it finishes |

1. Cold launch with no complimentary grant. Observe loading if visible, then confirmed paid/free presentation. Check that no stale uncertainty footer or upgrade button remains after the settled answer.
2. Use a controlled unverified first-read fixture with no complimentary grant. About must display **Unable to Verify Plus**, hide **Unlock NextSeason Plus**, and omit ordinary three-show capacity. Verify the exact footer: “NextSeason couldn't verify your subscription status. Your saved shows are preserved. Check your connection and try Restore Purchases.” Existing saved tracking state must not be paused merely because verification is uncertain. New additions still follow the existing unverified-access limit; this fix does not grant unlimited access.
3. From that fixture, allow a definitive active answer and use Restore Purchases. About must become Unlimited with the paid footer and no upgrade button. The view must update without reopening About.
4. Repeat with a definitive inactive answer on refresh/foreground return. About must become Up to 3 shows with the ordinary free footer and upgrade button. A confirmed lapse may now pause extras through the existing access policy; distinguish this from uncertainty.
5. Repeat Restore Purchases while the entitlement remains unverified. About must stay Unable to Verify Plus with the upgrade button hidden; completing a restore request is not proof of verified paid access. After the request ends, Restore Purchases becomes usable again. Separately test a thrown restore error and recovery.
6. Repeat loading, unverified, and confirmed-free states with a recognized complimentary grant. About remains Unlimited with the complimentary footer. If both paid and complimentary access are present, the paid footer takes priority.
7. Enable simulation over paid, complimentary, and unverified states. About uses the explicit simulated presentation; turning simulation off restores the actual presentation. Preserve the existing rule that the simulated upgrade button waits for the first StoreKit read to finish.
8. With VoiceOver and large text, check the new status/footer are understandable and readable and the Restore Purchases control remains reachable.

A real unverified entitlement can be hard to force. Airplane Mode may produce a cached verified answer instead. If you cannot produce the state on a device, record that portion **Blocked**, and separately record the controlled-fixture/unit-test evidence from `PlusAccountPresentationTests`. Do not record a successful offline launch as proof that the unverified presentation was exercised. The presentation implementation has been reviewed; visual/device acceptance remains to be recorded.

## Controlled provider, ordering and verification requirements

### Controlled-data checks — complete with developer assistance

These are part of the complete coverage record, but cannot be reliably forced through ordinary shipped-app taps. Do not modify live TVMaze records, use debugger shortcuts that bypass entitlement checks, or treat a fictional notification as production proof.

#### SK-27 — Paused refresh, historical catch-up, and old notification navigation

Have the developer use controlled TVMaze responses on the current code, or run the existing subscription-downgrade suites and record the exact build/results.

Verify:

1. Pause D–G; publish a new status for an active show and a paused show; run the production refresh. Only active shows fetch/update/notify.
2. Resume Plus after historical changes to paused shows. They get a silent baseline; a genuinely later change notifies once.
3. Fail catch-up, swipe-delete its marked show, refresh while absent, Undo, then refresh. The original mark survives and historical data remains silent. Delete and add a genuinely new row instead; the old mark must not silence it.
4. Tap a notification whose show has become paused, both while running and from a cold launch. It lands on Watchlist without paused detail navigation after access reconciliation.
5. Tap an active show's notification; it opens its detail. Tap one for a removed show; it uses the Search fallback or handles unavailable data without crashing.
6. Change access/pause state while a show's fetch is suspended. No stale response unpauses the row or announces its history.

For a manual old-notification smoke check, Diagnostics → Send Test Notification chooses Lupin if tracked, otherwise a saved row; record the actual selected show. Deliver the notification while the show is active, leave it untapped, cause real lapse or enable simulation, and then tap it. Repeat from a closed app with real inactive entitlement. The diagnostics notification is fictional and intentionally bypasses production change detection: it tests delivery/routing only. It is not proof that paused shows can or cannot generate production alerts.

#### SK-28 — Deterministic free admission and ordinary soft-alert confirmation

Use the current `WatchlistAdmissionAndDebounceTests.swift` suites, or an equivalent controlled manual fixture, to verify:

- Two different additions both hold stale counts during detail fetches; first saves, second hits the cap.
- Immediate Undo restores an active row while an addition is suspended; addition is rejected when it resumes.
- An undated announcement and an ending each use one fixed TVMaze update timestamp: first non-forced refresh waits, second announces, third does not repeat.
- A first StoreKit check still loading does not pause saves; an unverified first check preserves saved state without granting unverified unlimited additions; unverified after confirmed paid access preserves that answer; subsequent definitive active/inactive results converge correctly.

The competing-add test now describes detail-fetch suspension accurately; it does not separately guarantee both additions waited for StoreKit. If you want that exact ordering proven, record it as a separate coverage item rather than claiming a human rapid-tap test establishes it.

#### SK-29 — Notification permission integration

1. Deny notification permission; check the Watchlist banner and About status.
2. Use Enable Notifications/Open Settings to enable it. Return and inspect status.
3. Disable permission after enabling it; return again.
4. With controlled data, discover a change while permission is disabled, then re-enable.

**Expected:** UI reflects current alert settings on return; normal tracking still works; enablement takes the appropriate permission/Settings path. Changes processed while notifications are disabled are not promised as a replay backlog. About explains that iOS decides background timing. A silent manual pull-to-refresh intentionally updates the list without production alerts.

#### SK-30 — Unverified transaction and storefront edge cases

With developer assistance, inject StoreKit verification failure for a purchase and for current entitlements. Distinguish this from a network failure: Airplane Mode does not guarantee an unverified transaction. A failed purchase verification must not grant Plus; current-entitlement uncertainty follows SK-28. If available, also change sandbox storefront and verify newly loaded catalog currency/price agrees with Apple's sheet. No special lifetime, promotional-offer, or Family Sharing flow is implemented by this local product configuration; test those only if explicitly enabled in App Store Connect for release.

## Controlled verification register

Record current-candidate automated evidence separately from manual observations; existing test code is not a recorded pass. Unavailable fixtures remain Blocked.

| ID / area | Required controlled scenario and expected result | Existing starting points |
|---|---|---|
| CV-06 Access (item #1) | Hold old inactive/active scans and release in reverse order; only newest-request results apply. A newer successful scan releases callers even while an older one remains held. Purchase/update finishing and simulation completion await applied access; restore overlap, cancellation, burst requests, .unverified newest result and complimentary grant preserve their contracts. Record newest-stall recovery limitation without simulating a false inactive entitlement. | PurchaseServiceEntitlementOrderingTests; PurchaseServiceTests; FreeTierSimulationTests; SubscriptionDowngradeTests; EntitlementCheckOrderingReview-2026-10-19.md |

## Competing removal/add/Undo requirements — retained engineering detail

#### SK-22 — Free slots, paused reactivation, and Undo

**Start:** lapsed A–G.

1. Remove active A using its star, but before confirmation try to add H. Undo A's removal.
2. Confirm removal of A; add paused D through Search/Detail.
3. Attempt H with three active again.
4. Repeat using swipe-delete of an active show, followed by adding H and Undo while the toast exists.
5. With two active shows, tap stars for two different new shows rapidly. Repeat with a slow network, then inspect the saved result after returning to Watchlist.

**Expected:** deferred star removal retains its slot during Undo; a real committed removal frees it. Reactivating D updates its saved row rather than duplicating it. No fourth active row should persist; a blocked addition opens Plus. If the replacement addition completed first, Undo restores the original show as paused, preserving its metadata and leaving the existing active shows unchanged. If Undo won the slot first, the later addition is blocked. Human taps cannot guarantee the precise suspension ordering; SK-28 provides deterministic coverage.

## Evidence status and sources

No app tests or device scenarios were run for this documentation revision. The missing setups above remain engineering evidence gaps. The prior script wording is retained above to preserve expected behavior, not to ask a tester to manufacture those states. Full-suite execution remains owner-controlled.

- [Existing beta engineering coverage index](BetaRegressionCoverage-2026-10-26.md).
- [Free-tier simulation and complimentary override contracts](../Post-MVP/FreeTierSimulation.md).
- [Apple local StoreKit setup](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode).
- [Apple Ask to Buy controls](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode).
- [Apple transaction manager](https://developer.apple.com/documentation/xcode/testing-in-app-purchases-with-storekit-transaction-manager-in-code).
