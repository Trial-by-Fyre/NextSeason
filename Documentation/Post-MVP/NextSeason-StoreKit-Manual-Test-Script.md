# NextSeason — StoreKit manual regression and release testing

**Updated October 26, 2026.** Extracted from the beta regression documents and updated with the October 22–23 fixes and current working-copy purchase presentation. This is a plan, not a record of passes. Record the exact installed build; uncommitted working-copy changes are not proof of TestFlight behavior. Use the [matching checklist](NextSeason-StoreKit-Manual-Test-Checklist.md). OC-11 and CV-06 retain their original IDs.

- [Recent-fix regression pass](#focused-regression-pass--recent-purchase-fixes)
- [Setup and full SK-01–SK-30 coverage](#how-to-use-this-script)
- [Entitlement ordering — OC-11](#oc-11--entitlement-ordering-in-real-purchaserestore-flows-item-1)
- [Results](#result-sheet) and [cleanup](#completion-and-cleanup)

**Audience:** Janine and developer-assisted testing. The volunteer purchase checks live in the [beta regression guide](NextSeason-Beta-Regression-Test.md#volunteer-purchase-checks--only-if-assigned) and its matching checklist. Ordinary beta testers do not need this document. Some cases below can be performed manually by Janine; cases requiring Xcode or controlled fixtures are identified separately.

The setup, safeguards, and result sheet below apply to SK-01–SK-30.

## Focused regression pass — recent purchase fixes

Updated October 26, 2026. These cases supplement SK-01–SK-30; they do not replace release coverage. Use the setup below, record the exact candidate build, and run with Simulate Free Tier OFF except section 10. Start with A–C active and D untracked; keep at least five saved shows for lapse/reactivation. Reset purchase state only when needed, after preserving lifecycle evidence.

For every cold launch/relaunch on a complimentary installation, re-enable Ignore Complimentary Plus and confirm the intended access before continuing. Strict startup checks require a non-complimentary installation as explained under paid-device setup. Fixtures unavailable in TestFlight are Blocked, not failures or passes.

### 1. Purchase presentation — SK-02, SK-04/05

These tests target the first-attempt paywall dismissal bug.

#### 1A. Purchase from Search

- Cold-launch NextSeason with Free access and three tracked shows.
- Search for show D.
- Tap Add.
- Verify the Plus paywall opens.
- Verify the paywall has Cancel rather than Done.
- Tap the Monthly plan button on the **first attempt**; there is no separate app Purchase button.
- Verify Apple's purchase confirmation sheet appears without the paywall disappearing.
- Verify the correct plan and price are displayed.
- Cancel Apple's confirmation without completing the purchase.

#### 1B. Purchase from Show Detail

- Start fresh with Free access and D untracked.
- Cold-launch NextSeason.
- Open D's details from Search.
- Tap Add.
- Verify the Plus paywall opens.
- Tap the Annual plan button on the **first attempt**.
- Verify Apple's confirmation appears over the current interface.
- Verify the correct plan and price.
- Cancel Apple's confirmation.

#### 1C. Purchase from About

- Start fresh with Free access.
- Cold-launch NextSeason.
- Open About and select Unlock Plus.
- Attempt to purchase a subscription immediately.
- Verify Apple's confirmation sheet appears on the first attempt.
- Verify the plan and price.
- Cancel Apple's confirmation.

**Expected:** No first-tap disappearance, blank screen, unexpected navigation, or requirement to retry.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 2. Successful purchase — SK-04/05

Run this from both Search and Show Detail using appropriate fresh purchase state.

#### 2A. Search

- Start with three tracked shows and D untracked.
- Search for D and tap Add.
- Purchase Plus successfully.
- Verify the paywall dismisses automatically.
- Verify Plus becomes active.
- Verify D was added **exactly once automatically**.
- Do not tap D's Add button a second time.
- Verify any notification-permission prompt remains usable.
- Verify subsequent shows can be added.

#### 2B. Show Detail

- Repeat with D initially untracked, starting from its detail page.
- Purchase Plus successfully.
- Verify the paywall dismisses.
- Verify D is automatically tracked, exactly once.
- Verify the Show Detail interface reflects the new tracked state.
- Verify notification-permission prompts, if presented, can be responded to normally.

**Expected:** The purchase completes the original Add Show request. No retry, duplicate, or lost action.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 3. Cancellation and purchase failure — SK-06/07

#### 3A. Apple purchase cancellation

- With Free access, attempt to add D.
- Start a Plus purchase.
- Cancel from Apple's confirmation sheet.
- Verify the NextSeason paywall remains available.
- Verify D remains untracked.
- Verify the user can retry the purchase.
- Tap Cancel on the NextSeason paywall.
- Verify the paywall closes and the blocked add is abandoned.

#### 3B. Purchase failure

- Using an available sandbox failure simulation, attempt to buy Plus from D's blocked add.
- Verify an appropriate failure message is displayed.
- Verify the paywall remains available for retry.
- Verify D remains untracked.
- Verify the user can dismiss the paywall safely.

If no reliable failure simulation is available, mark Blocked.

#### 3C. Success reported without Plus access

**Developer-assisted; no manual TestFlight switch exists.** A stale-success fixture makes a purchase report success while leaving Plus inactive. Automated service coverage exists in `NextSeasonTests/PurchaseSuccessWithoutAccessTests.swift` using `reportsStaleSuccess`, but it does not by itself prove the paywall and blocked-add UI steps below. Mark the manual case **Blocked — manual fixture unavailable** unless a developer supplies a UI fixture; record actual automated results separately.

- Simulate a purchase reporting success without Plus entitlement becoming effective.
- Verify the paywall stays open.
- Verify the app explains that Plus has not been unlocked.
- Verify D remains untracked.
- Perform a subsequent genuine successful purchase.
- Verify Plus unlocks and D is added exactly once.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 4. Pending and interrupted purchases — SK-08/09/10

#### 4A. Pending transaction completes while paywall remains open

- Start a blocked add for D.
- Use developer-assisted local Xcode Ask to Buy to create a pending purchase. Approval controls are not configured in the current TestFlight workflow; mark Blocked if this fixture is unavailable.
- Keep the original paywall open.
- Complete or approve the pending transaction.
- Verify Plus becomes active.
- Verify the paywall dismisses.
- Verify D is automatically added exactly once.

#### 4B. Transaction completes after paywall dismissal

- Start a blocked add for D.
- Initiate a pending transaction using the same local Xcode Ask to Buy fixture; mark Blocked if unavailable.
- Dismiss the paywall, if permitted.
- Complete the transaction afterward.
- Verify Plus access is recognized.
- Verify D is **not automatically added** because the original add was abandoned.
- Verify the user can add D normally afterward.

#### 4C. Transaction completes after relaunch

- Start a blocked add for D.
- Initiate a pending transaction using the same local Xcode Ask to Buy fixture; mark Blocked if unavailable.
- Terminate and relaunch NextSeason.
- Complete the pending transaction.
- Verify Plus access is restored.
- Verify the abandoned Add Show operation does not resume.
- Verify D remains untracked until explicitly added.

**Expected:** An active pending action completes automatically; an abandoned action never comes back unexpectedly.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

---

### 5. Subscription expires in background — SK-13

- Start with an active Monthly Plus subscription and at least five tracked shows.
- Confirm Ignore Complimentary Plus is ON.
- Cancel automatic renewal using Apple's sandbox instructions.
- Confirm the subscription remains active until expiration.
- Background NextSeason.
- Wait until the subscription actually expires.
- Reopen NextSeason.
- Verify the entitlement refresh recognizes Free access.
- Verify only the three oldest shows remain active.
- Verify other shows are visible but paused.
- Verify paused-show details are not accessible without Plus.
- Verify no shows were deleted or duplicated.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 6. Subscription expires in foreground — SK-14

- Start with an active Monthly Plus subscription and at least five tracked shows.
- Confirm Ignore Complimentary Plus is ON.
- Cancel automatic renewal.
- Leave NextSeason open in the foreground.
- Wait until the subscription expires.
- Continue through the scheduled expiration recheck, approximately five minutes after expiration.
- Verify the app recognizes Free access without a restart.
- Verify only the three oldest shows remain active.
- Verify remaining shows are paused.
- Verify expiration notices do not repeat unnecessarily.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 7. Resubscription and reactivation — SK-17

#### 7A. Ordinary resubscription

- Start with an expired subscription and at least two paused shows.
- Open the paywall.
- Purchase Plus.
- Verify all paused shows reactivate.
- Verify data, ordering, and sections are preserved.
- Verify another show can be added.

#### 7B. Blocked add for an already-saved paused show

Run through Search and Show Detail, using suitable Free-tier test state.

- Start with an already-saved paused show D.
- Find D through Search or its available detail/add entry point.
- Attempt to add or reactivate D.
- Verify the Plus paywall opens.
- Purchase Plus or successfully restore existing Plus access.
- Verify D remains tracked.
- Verify no duplicate is created.
- Verify D is not removed.
- Verify no inappropriate Undo toast appears.
- Verify D becomes active and accessible.

- Repeat for the other entry point.

**Expected:** Reactivation does not accidentally toggle the existing saved show off.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

---

### 8. Restore Purchases — SK-18

#### 8A. Restore valid Plus during blocked add

- Arrange for a valid Plus entitlement that NextSeason has not yet recognized.
- Start with D untracked and three active shows.
- Attempt to add D.
- On the paywall, select Restore Purchases.
- Verify valid Plus access is recognized.
- Verify the paywall dismisses.
- Verify D is automatically added exactly once.
- Verify the Watchlist remains intact.

If the necessary entitlement state cannot be reproduced, mark Blocked.

#### 8B. No eligible subscription

- Use a sandbox account with no eligible active subscription.
- Attempt to add D to trigger the paywall.
- Tap Restore Purchases.
- Verify Plus is not incorrectly granted.
- Verify D remains untracked.
- Verify the user receives understandable feedback.
- Verify the paywall remains available.

#### 8C. Failed or offline restoration

- Trigger the paywall through D's blocked add.
- Disconnect network access.
- Tap Restore Purchases.
- Verify no crash or indefinite hang occurs.
- Verify D remains untracked.
- Verify appropriate failure or unavailable feedback.
- Restore connectivity.
- Retry restoration.
- Verify the app recovers normally.

#### 8D. Restore after expiration

- Start with expired Plus and paused shows.
- Tap Restore Purchases.
- Verify an expired subscription does not incorrectly unlock Plus.
- Verify paused shows remain intact.
- Verify appropriate feedback is displayed.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 9. Tips — SK-23

- Tips are separate consumable purchases and must never unlock Plus.

#### 9A. First-attempt purchase presentation

- Start with Free access.
- Cold-launch NextSeason.
- Open About and locate the tip options.
- Select a tip and initiate purchase.
- Verify Apple's confirmation sheet appears on the first attempt.
- Verify the correct tip and price.
- Verify About remains presented normally.

#### 9B. Cancellation

- Cancel from Apple's confirmation sheet.
- Verify no tip purchase is recorded as successful.
- Verify the user can attempt a tip again.
- Verify access remains Free.

#### 9C. Successful tip

- Complete a tip purchase.
- Verify appropriate confirmation or acknowledgment.
- Verify Plus is not unlocked.
- Verify the Free-tier three-show limit still applies.
- Verify tracked shows are unchanged.
- Verify the app does not display an unintended subscription paywall.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 10. Simulate Free Tier — SK-25

- Start with active StoreKit Plus and at least five active shows.
- Confirm Ignore Complimentary Plus is ON.
- Turn Simulate Free Tier ON.
- Verify the three oldest shows remain active.
- Verify remaining shows become paused but remain visible.
- Turn Simulate Free Tier OFF.
- Verify all shows reactivate.
- Relaunch NextSeason.
- Re-enable Ignore Complimentary Plus if a stored grant is present.
- Verify access reflects actual StoreKit entitlement and simulation settings.
- Verify no shows or data were lost.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### How to use this script

For recent fixes, use the focused regression pass above after completing setup. For broader release coverage, run SK-01–SK-30 in their listed passes. Each case gives its starting state, actions, and expected result. Record **Pass / Fail / Blocked / Not applicable**, the build, and any evidence. “Blocked” means you could not establish the required state; it does not mean the feature passed.

Use three passes:

1. **Local Xcode:** repeatable purchase, pending, error, refund, and expiration scenarios.
2. **Real-device sandbox/TestFlight:** actual product configuration, entitlement persistence, offline behavior, restore, and billing states.
3. **Complimentary and simulation:** the special beta-access rules, tested separately from paid access.

Repeat monthly and annual purchase/lapse/restoration cases for both plans. Run core purchase, cancel, restore, and paused-row screens with VoiceOver and the largest practical text size on the oldest supported iOS device you have, and on your current iOS device. One device may satisfy both passes when appropriate.

Do not wait for a live TVMaze show to change to test a notification rule. The controlled-data cases near the end require developer assistance; the ordinary app cannot reliably create those situations on demand.

### Record the test setup

- Tester / date:
- App version / build / commit:
- Device / iOS version:
- Xcode version, if applicable:
- Install source: Xcode local / Xcode sandbox / TestFlight / App Store:
- Scheme and build configuration:
- StoreKit configuration: NextSeason.storekit / None:
- Test account alias (do not record passwords):
- Storefront / displayed currency:
- Renewal speed and observed expiration time:
- Billing Grace Period enabled for sandbox? Yes / No:
- Complimentary access present? Yes / No:
- Ignore Complimentary Plus enabled this session? Yes / No:
- Simulate Free Tier enabled? Yes / No:

#### Products to verify

| Product | Identifier | Type |
|---|---|---|
| Plus Monthly | com.trialbyfyre.nextseason.plus.monthly | Auto-renewing subscription |
| Plus Annual | com.trialbyfyre.nextseason.plus.annual | Auto-renewing subscription |
| Trailer | com.trialbyfyre.nextseason.tip.trailer | Consumable tip |
| Pilot | com.trialbyfyre.nextseason.tip.pilot | Consumable tip |
| Hit Show | com.trialbyfyre.nextseason.tip.hitshow | Consumable tip |

Monthly and annual provide the same unlimited-watchlist access. Tips never unlock features. Use the prices actually supplied by the selected storefront; do not compare sandbox prices with the fallback prices in code.

#### Prepare a paid-access test device

Use the normal **NextSeason** scheme, not **NextSeason - Final Complimentary Beta**. The special beta archive configuration grants permanent complimentary access and can conceal paid-subscription failures.

Check About before testing. For Janine/developer-assisted tests on an installation with complimentary access, open About → Diagnostics → Subscription Testing and turn **Ignore Complimentary Plus ON**, with **Simulate Free Tier OFF**. Wait for access to settle and verify Free when no active subscription exists. Ignore Complimentary Plus hides the stored grant without deleting it; it does not hide a paid subscription.

**Both testing overrides are session-only and reset on app termination. After every cold launch/relaunch on a complimentary installation, re-enable Ignore Complimentary Plus before checking StoreKit-only access.** While it is off during startup, complimentary access may already reactivate paused shows; use a separate non-complimentary installation for strict cold-launch paid-access-loss/ordering evidence. Mark that branch Blocked if unavailable. Do not clear a genuine grant. Deleting the app or switching purchase accounts does not reliably remove its synchronizable Keychain grant. Volunteers should use the restricted setup in the beta regression guide’s volunteer purchase section.

Turn **Simulate Free Tier OFF** for every real StoreKit test. It overrides effective access and intentionally survives restore scans within the session.

Remove UI-testing/profile launch arguments. UI tests use stubs and are not a manual StoreKit session.

#### Local Xcode setup

In Xcode, choose the normal NextSeason scheme. Open **Product → Scheme → Edit Scheme → Run → Options**, select the existing **NextSeason.storekit** configuration, and run the app. While running, open **Debug → StoreKit → Manage Transactions**. Reset local test transactions when a case calls for fresh purchase history. Use the configuration editor's renewal-rate controls; use a slower rate for offline tests so the paid period does not end during the test. These local purchases do not validate App Store Connect configuration. [Apple setup guidance](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode), [local testing guidance](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-in-xcode).

Record and restore any temporary scheme/configuration changes afterward. Keep local tests separate from sandbox transactions.

#### Real-device sandbox and TestFlight setup

Create dedicated Sandbox Apple Accounts in App Store Connect → Users and Access → Sandbox. Use accounts with no prior purchase history for fresh-state cases. For an Xcode device build, set the scheme's StoreKit configuration to **None** and use the sandbox account controls on the device.

TestFlight uses sandbox purchases. For controllable billing and renewal scenarios, Apple directs testers to sign out of the production account under **Media & Purchases**, then sign in to the Sandbox Apple Account under Developer settings. Use a dedicated test device where practical; record the original account so you can restore it afterward. Default TestFlight renewals are daily, irrespective of monthly/annual duration; custom sandbox-account settings provide other rates. Do not assume a monthly test lasts a production month. [Apple TestFlight guidance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/).

Sign out of Media & Purchases **before the first launch** of each new TestFlight build. Switching accounts while NextSeason is running can leave StoreKit with the previous account's subscription: Plus may appear active, and after signing out the first purchase can return instantly without Apple's sheet. If that happens, force-quit and relaunch NextSeason before testing purchases.

For short monthly lapse tests, the sandbox account’s three-minute monthly renewal setting is available; use a longer period for offline tests. Record Apple’s actual expiration rather than timing only from the purchase tap. To stop sandbox renewal on iPhone: Settings → Developer → Sandbox Apple Account → Manage → Subscriptions → NextSeason Plus → Cancel Subscription. Cancellation stops renewal, with access retained until expiration. [Apple cancellation instructions](https://developer.apple.com/documentation/storekit/testing-disabling-auto-renew).

Select a manageable renewal rate and note the transaction's expiration. Sandbox settings also allow interrupted purchases and clearing purchase history; clearing that history does not clear the app's watchlist or complimentary Keychain grant. Allow the reset to propagate before starting. [Apple sandbox account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/).

#### Watchlist fixture

Choose seven available shows. Label them in your notes **A–G**, record their names/TVMaze IDs, and add them in that order when instructed. A, B, C must be the oldest. Prefer shows with stable source data. Record their status and “Updated” times before lapse tests.

“Relaunch” below means close the app completely and open it again. “Foreground return” means switch to another app and return without terminating NextSeason.

### Pass 1 — purchases, catalog, and transaction lifecycle

#### SK-01 — Fresh free user and both paywall entry points

**Start:** no subscription, no complimentary access, simulation off, empty watchlist.

1. Open About. Confirm the settled capacity is up to three shows and Unlock NextSeason Plus is available.
2. Add A, B, C from Search. Attempt D from Search.
3. Dismiss the Plus sheet. Open D's detail and attempt to track it there.
4. Open the Plus sheet directly through About, then dismiss it.

**Expected:** both fourth-add attempts show the same Plus options and do not save D. Three shows remain active. Dismissing the sheet makes no purchase and leaves navigation usable. Initial “Checking…” must settle; no indefinite loading.

#### SK-02 — Product catalog, prices, disclosures, and links

**Start:** SK-01 state; online. Run locally, then again in TestFlight.

1. Inspect Monthly and Annual, their period labels, currency, and price.
2. Open each Apple purchase sheet and compare its product/period/price with the app; cancel both.
3. Open Terms of Use and Privacy Policy, then return.
4. Inspect all three tip options in About.

**Expected:** products match their identifiers and App Store Connect configuration. No lifetime option appears. Subscription disclosure and links are readable; links load the intended pages. Tip copy says tips do not unlock features. No stale error or duplicate sheet appears on return.

#### SK-03 — Catalog failure and retry

**Start:** fresh launch without a previously loaded catalog. Local error simulation, or sandbox device offline before launch.

1. Open About and the Plus sheet. If necessary use local StoreKit product-loading error controls; turning off internet will not reliably fail local StoreKit.
2. Observe loading and eventual failure.
3. Restore normal settings/connectivity. Tap Try Again.

**Expected:** unavailable products are not replaced with invented live prices or enabled purchase buttons. A recoverable unavailable message appears; retries restore the catalog. Existing paid access and saved shows do not disappear because product loading failed. Dismiss remains usable when no purchase is in flight. Record a blocked result if the environment cannot induce failure.

#### SK-04 — Monthly purchase

**Start:** free account, A–C active, no prior subscription.

1. Attempt D, then purchase Monthly and approve Apple's confirmation.
2. Observe the Plus sheet closing and About reporting Unlimited. Confirm D is already tracked exactly once before trying to add anything else.
3. Confirm D was added automatically exactly once; do not tap its star again. Add E–G, switch tabs and reopen a saved detail. Repeat from Search and Show Detail with fresh Free state.
4. Relaunch and attempt another addition.

**Expected:** verified Monthly unlocks access without requiring Restore Purchases. Unlimited survives relaunch. No duplicates, unintended paused rows, or repeated purchase prompts. A successful purchase completes the original blocked add automatically exactly once; needing to tap Add again is a failure. Any notification-permission prompt remains usable.

#### SK-05 — Annual purchase

Reset purchase history using the appropriate environment; establish a genuinely free account. Repeat SK-04 with Annual. Confirm the payment sheet uses Annual and its yearly price. Keep one paid fixture for the later lifecycle cases.

#### SK-06 — Cancel the purchase sheet

**Start:** free, A–C active.

1. Start a Monthly purchase and cancel Apple's purchase sheet.
2. Repeat for Annual and a tip.
3. Dismiss the app's Plus sheet and navigate normally.

**Expected:** no Plus grant, no tip thank-you, no scary failure alert for ordinary cancellation, and no stuck busy state. Fourth additions remain blocked.

#### SK-07 — Failed purchase and recovery

**Start:** free. Use Xcode's purchase-failure simulation, or sandbox billing failure settings.

1. Attempt Monthly with failure enabled.
2. Dismiss the error; repeat with Annual and one tip.
3. Turn failure simulation off and retry a subscription successfully.

**Expected:** no entitlement from a failed transaction; clear recoverable feedback; controls usable after failure; successful retry grants access. Errors do not appear twice through both About and the Plus sheet. [Apple purchase-failure guidance](https://developer.apple.com/documentation/storekit/testing-failing-subscription-renewals-and-in-app-purchases).

#### SK-08 — Pending purchase approved, declined, and approved while app is closed

**Environment:** developer-assisted local Xcode; enable Ask to Buy in the configuration editor. This approval/decline fixture is not configured in the current TestFlight workflow. Mark unavailable branches Blocked; sandbox pending initiation does not provide Xcode’s approval controls.

1. As a free user, attempt Monthly. Leave the transaction Pending Approval in the transaction manager.
2. Verify no Plus access yet; the app is navigable after the purchase call returns pending.
3. Keep the original blocked-add paywall open and approve in the manager. Confirm Unlimited, automatic dismissal, and D added exactly once.
4. Reset the fixture. Repeat with Annual, but decline the pending transaction. Confirm free access remains.
5. Reset again. Create a pending blocked add, dismiss the paywall, then approve: Plus unlocks but D stays untracked because the add was abandoned.
6. Reset again. Create a pending blocked add, close the app, approve it, then relaunch: Plus unlocks but the abandoned add does not resume. Reapply Ignore Complimentary Plus after relaunch if needed.

**Expected:** access arrives only after verified completion. Delayed/launch completion is recognized without purchasing twice. Declining grants nothing. Pending is not falsely described as success. There may be no dedicated in-app pending message in the current UI; record the experience separately from entitlement correctness. [Apple Ask to Buy guidance](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode).

#### SK-09 — Interrupted purchase

**Environment:** sandbox, with interrupted purchases enabled for this test account.

1. Start a subscription and follow the interrupted flow without completing the required external action.
2. Return to NextSeason. Check capacity and ability to navigate.
3. Complete the required sandbox action/remove interruption, then finish or retry purchase.

**Expected:** no premature Plus grant; no permanently stuck purchase overlay; completion is recognized. Record whether recovery occurred through the original transaction or a retry.

#### SK-10 — Rapid taps and lifecycle interruption

**Start:** free. Run for a subscription and a tip.

1. Tap a purchase button rapidly twice; try another purchase control while Apple's sheet is active.
2. Cancel. Start again, background NextSeason during the flow, then return.
3. In a separate run, complete purchase and relaunch immediately afterward.

**Expected:** app-originated purchases are not duplicated; no overlapping app sheets or stuck controls. A completed subscription is present after return/relaunch. A completed tip does not unlock Plus. Judge transaction counts using the manager, not just visual alerts.

#### SK-11 — Automatic renewal and switching plans

**Start:** paid, A–G saved, simulation off.

1. Allow at least one real test renewal. Check About and every row before and after foreground return/relaunch.
2. Use the environment's subscription-management UI to switch Monthly → Annual; repeat Annual → Monthly on another run.
3. Note the effective time shown by Apple; check again after the switch takes effect.

**Expected:** no lapse while Apple reports an active entitlement, no duplicate tracked shows, no pausing from a valid renewal, and no historical catch-up burst. Plan changes preserve Plus; do not assume every switch takes effect immediately. Validate that App Store Connect places both plans in the intended subscription group.

### Pass 2 — losing and recovering paid access

#### SK-12 — Cancel renewal without expiring

**Start:** paid A–G, comfortably before expiration.

1. Turn off auto-renew using the environment's subscription-management controls. Locally, use a non-renewing test subscription/renewal control; do not use Refund or deleting transactions as a substitute.
2. Record Apple's entitlement expiration.
3. Return to NextSeason before that time, relaunch, and add another show.

**Expected:** Plus remains Unlimited through the paid period; all shows remain active. Cancellation of renewal alone does not pause anything. [Apple local transaction controls](https://developer.apple.com/documentation/xcode/testing-in-app-purchases-with-storekit-transaction-manager-in-code).

#### SK-13 — Actual expiration with app away

**Start:** SK-12; stop auto-renew and confirm expiration occurs.

1. Leave the app backgrounded while the entitlement expires. Reopen after expiration.
2. Record active and paused names, alert text, row styles, and saved total.
3. Open A; tap D–G in Watchlist; swipe-delete one paused row and Undo.
4. Acknowledge the pause alert, relaunch, and inspect again.

**Expected:** A–C remain active; later saves are retained in Paused — Plus Required. Paused rows hide old season/timestamp information and cannot open detail from Watchlist. Active rows still open. Paused removal/Undo preserves its pause state. No saved show disappears merely because Plus expired. The acknowledged alert does not recur without a new pause event. If Apple has not actually expired the entitlement, this is not a valid expiration test.

#### SK-14 — Expiration while the app is open; foreground/background reconciliation

Repeat expiration while NextSeason stays visible, then switch away and return. Repeat once with the app closed before expiration, and once with an actual scheduled background refresh if your device delivers one.

**Expected:** a foreground entitlement reread detects the lapse and applies the same three-show policy before ordinary watchlist refresh. While continuously foregrounded, the app re-checks about 5 minutes after Apple's recorded expiration and applies the same policy then; record the observed time. A renewal that arrives before then must not pause anything. A billing grace period end is detected on the next foreground return, not by this timer. A background run must reconcile before processing shows. If iOS never schedules a background run, mark that portion Blocked, not Pass.

#### SK-15 — Refund/revocation

**Environment:** local Xcode for controlled refund/revocation; repeat through sandbox controls if available.

1. Establish paid A–G. Refund/revoke the active subscription transaction using the manager.
2. Check the running app, then foreground return and relaunch.
3. Attempt a fourth active addition.

**Expected:** once the verified entitlement is revoked, paid access is removed and extra shows pause without deletion. Fourth additions are blocked. No remaining second valid subscription or complimentary grant may mask this case. Turning renewal off is not equivalent to revocation.

#### SK-16 — Billing grace, grace recovery, and billing retry without entitlement

**Environment:** real-device sandbox account. First record whether Billing Grace Period is enabled for sandbox in App Store Connect.

1. Purchase Plus. Enable sandbox renewal billing failure before the next renewal through Settings → Developer → Sandbox Account → Manage → Account Settings.
2. When Apple reports a grace state, check About, additions, and all seven shows.
3. Resolve billing before grace ends and allow renewal. Confirm access remains.
4. On a separate run, let grace end without recovery, or test billing retry without a grace entitlement. Return to the app.
5. Resolve billing and confirm valid access returns.

**Expected:** Apple's active/grace entitlement keeps Plus. After no entitled state remains, A–C stay active and extras pause. Recovery resumes all saved rows, with silent catch-up. If grace is not configured, mark the grace-specific branch Not applicable and still test retry/expiration. Do not classify every payment failure as immediate access loss. [Apple billing-test guidance](https://developer.apple.com/documentation/storekit/testing-failing-subscription-renewals-and-in-app-purchases).

#### SK-17 — Resubscribe after lapse and repeated lapse

**Start:** lapsed fixture with three active and extras paused.

1. Buy Monthly or Annual again. Inspect all saved shows as access returns.
2. Pull to refresh; relaunch. Record any notifications during reactivation.
3. Let paid access lapse again.

**Expected:** every saved paused row resumes without duplicates. Catch-up updates old data without announcing changes from the paused interval. A later lapse chooses the three oldest surviving saves again; previous free-period selections are not remembered as a separate preference. Current access-change alerts should not remain after restoration. Controlled-data verification of notification history is SK-27.

#### SK-18 — Restore Purchases: active, inactive, failure, repeated

1. With an active paid account, use Restore Purchases from About; repeat from the Plus sheet if reachable. Relaunch first if needed.
2. Repeat on a fresh account without purchases and on an expired account.
3. Induce a restore failure using local error controls or offline real-device testing, then recover and retry.
4. Tap Restore rapidly twice and repeat a successful restore.
5. With developer assistance, establish valid Plus that has not yet been recognized, trigger D’s blocked add, and restore on that paywall. Confirm dismissal and D added exactly once. Mark Blocked if automatic detection prevents establishing this state.

**Expected:** valid access is recovered; restore does not purchase or duplicate shows. No-purchase/expired accounts remain free and see a Restore Purchases alert saying no active subscription was found (in the Plus sheet or About, wherever Restore was tapped); no false “Plus restored” claim. Failure gets recoverable feedback and no stuck busy state. Repeating restore is harmless. Automatic entitlement detection may restore access before you tap Restore; record that as automatic detection, not proof that the button changed access.

#### SK-19 — Reinstall and second-device distinction

**Start:** active subscription on a disposable test installation; export its watchlist first if needed.

1. Delete and reinstall NextSeason using the same testing environment/account. Open About and use Restore if necessary.
2. Repeat on a second device with the same purchase account if available.

**Expected:** paid entitlement is recoverable. Restore Purchases does not itself import the old watchlist. A fresh installation/device may have no saved shows; do not mistake that for subscription failure. Device-backup restoration is a separate migration test, not part of purchase restoration. Do not do this on your only valuable watchlist.

### Pass 3 — offline, limits, tips, and beta rules

#### SK-20 — Existing subscriber offline, without crossing expiration

**Environment:** real-device sandbox/TestFlight; active paid account with no complimentary grant. Choose a long enough test period and record expiration.

1. Launch online and confirm Unlimited/A–G active.
2. Enable Airplane Mode and explicitly disable Wi-Fi. Foreground-return, then relaunch offline.
3. Check About and Watchlist; do not interpret TVMaze fetch errors as entitlement failure.
4. Restore connectivity, foreground-return, and retry any failed action.

**Expected:** no destructive watchlist loss or false confirmed-lapse alert from a temporary verification problem. Cached verified entitlement should be honored when available. If StoreKit is unverified on cold launch, saved pause flags are preserved but new additions may be limited; record the exact state and messaging. Reconnection converges to valid Plus. A show-detail network failure is separate from StoreKit access. If the subscription actually expires while offline, rerun with a longer period before drawing conclusions.

#### SK-21 — Offline free user, offline expiration, and restore failure

1. Relaunch a genuinely free account offline; inspect saved shows and purchase options. Attempt Restore, reconnect, retry.
2. Separately, let a paid subscription expire while disconnected, then reconnect and foreground-return.

**Expected:** offline does not grant free users Plus. Purchase/restore failures are recoverable. After reconnect and a definitive inactive entitlement, extras pause without deletion. No claim that a cached offline state proves current server access; record when the app converges after reconnect.

#### SK-22 — Free slots, paused reactivation, and Undo

**Start:** lapsed A–G.

1. Remove active A using its star, but before confirmation try to add H. Undo A's removal.
2. Confirm removal of A; add paused D through Search/Detail.
3. Attempt H with three active again.
4. Repeat using swipe-delete of an active show, followed by adding H and Undo while the toast exists.
5. With two active shows, tap stars for two different new shows rapidly. Repeat with a slow network, then inspect the saved result after returning to Watchlist.

**Expected:** deferred star removal retains its slot during Undo; a real committed removal frees it. Reactivating D updates its saved row rather than duplicating it. No fourth active row should persist; a blocked addition opens Plus. If the replacement addition completed first, Undo restores the original show as paused, preserving its metadata and leaving the existing active shows unchanged. If Undo won the slot first, the later addition is blocked. Human taps cannot guarantee the precise suspension ordering; SK-28 provides deterministic coverage.

#### SK-23 — Tips for free and paid users

1. As free, purchase Trailer, Pilot, and Hit Show separately. Dismiss each thank-you; buy the same tip again.
2. Cancel a tip, fail a tip, then retry successfully.
3. Relaunch and Restore Purchases. Repeat one tip as paid and one as complimentary.

**Expected:** each successful new tip transaction thanks the user once during its handling; purchases are repeatable consumables. Cancel/failure produces no thank-you. Tips never grant Plus, change pause flags, or consume watchlist slots. Restore does not recreate spent tips or retroactively unlock features. Relaunch must not cause a repeated thank-you loop; the app does not promise a persisted receipt/history screen for tips.

#### SK-24 — Permanent complimentary access

**Start:** a separate previously granted beta installation. Do not use it for SK-12–16.

1. Install the normal non-granting build over the existing beta installation.
2. Relaunch online/offline; check About and add beyond three shows.
3. If this fixture also has a paid subscription, let that subscription expire or revoke it.
4. Retry after a normal foreground return. Optionally check a second device with the same iCloud/Keychain setup, allowing sync time.

**Expected:** recognized permanent complimentary access remains Unlimited independently of purchased entitlement. About identifies complimentary access when there is no active paid subscription. A temporary Keychain problem must not revoke already recognized access. Cross-device discovery may depend on Keychain synchronization; it does not synchronize watchlists. A fresh normal installation with no existing grant must not receive a new complimentary entitlement.

#### SK-25 — Simulate Free Tier: state, restart, purchase, restore, tips

**Start:** actual paid/complimentary Plus with A–G, in Debug or verified TestFlight.

1. About → Diagnostics → Subscription Testing → enable Simulate Free Tier. Inspect the active notice and simulated capacity in About.
2. Confirm A–C active, extras paused, normal cap enforced, export includes all saves.
3. Restore Purchases, purchase a tip, and cancel/fail a Plus purchase; simulation must remain on.
4. Disable simulation; confirm all saves resume. Enable it again, then relaunch; session-only simulation ends and valid actual access resumes.
5. In a fresh local paid-test fixture, make a successful customer Plus purchase started during simulation. It should end simulation after verified active access.
6. Locally repeat with a pending Plus purchase, approving it later. Verify approval ends the same simulation session. Repeat after toggling simulation off/on before approval; an old session's completion must not turn off the new one.

**Expected:** actual purchased/complimentary entitlement is preserved underneath simulation. Renewals, unrelated transactions, restore, and tips do not end the override. Restart ends it; genuine success from the current simulated purchase can end it. If a currently subscribed account cannot make another customer purchase, use a reset fixture; do not count an automatic renewal as this test. Ordinary free users disabling simulation remain free.

#### SK-26 — Production boundary and user-facing presentation

On a real App Store installation when available, verify Diagnostics/Simulate Free Tier are absent and no fresh beta grant is created. Before release, inspect the archived Release configuration and record this as build verification rather than pretending TestFlight proves the App Store boundary.

Check free, paid, complimentary, loading, and unavailable-catalog screens in VoiceOver/large text. Verify price/period labels, error dismissal, paused state, and restore/purchase busy controls remain understandable.

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

### Result sheet

For every row, fill outcome, environment, build, and evidence. Use a separate copy of this document for each release candidate. Repeat rows as needed for monthly/annual, device, and environment.

| Case | Outcome | Environment / plan | Evidence / issue |
|---|---|---|---|
| Focused 1–10 (record each subcase) | | | |
| OC-11 Entitlement integration | | | |
| CV-06 Controlled access evidence | | | |
| SK-01 Free and paywall entries | | | |
| SK-02 Catalog, price, legal links | | | |
| SK-03 Catalog failure/retry | | | |
| SK-04 Monthly purchase | | | |
| SK-05 Annual purchase | | | |
| SK-06 Purchase cancellation | | | |
| SK-07 Failure/retry | | | |
| SK-08 Pending approved/declined/closed | | | |
| SK-09 Interrupted purchase | | | |
| SK-10 Rapid taps/lifecycle | | | |
| SK-11 Renewal/plan switch | | | |
| SK-12 Canceled renewal, still paid | | | |
| SK-13 Actual expiration | | | |
| SK-14 Foreground/background lapse | | | |
| SK-15 Refund/revocation | | | |
| SK-16 Grace/retry/recovery | | | |
| SK-17 Resubscribe/repeated lapse | | | |
| SK-18 Restore matrix | | | |
| SK-19 Reinstall/second device | | | |
| SK-20 Paid offline/reconnect | | | |
| SK-21 Free offline/offline lapse | | | |
| SK-22 Slots/reactivation/Undo | | | |
| SK-23 Tips | | | |
| SK-24 Complimentary | | | |
| SK-25 Simulation | | | |
| SK-26 Production/accessibility | | | |
| SK-27 Controlled catch-up/routing | | | |
| SK-28 Admission/soft alerts/uncertainty | | | |
| SK-29 Permissions | | | |
| SK-30 Verification/storefront | | | |

#### Failure report template

Case ID / build / device / environment / test-account alias:

Starting entitlement, simulation state, active/paused shows:

Exact steps and transaction/expiration times:

Expected result:

Actual result:

Screenshot/video or diagnostic export:

Does it reproduce after reconnect/relaunch? Does complimentary access affect it?

#### Completion and cleanup

Do not claim StoreKit is fully validated solely from local or simulated passes. Before release, have recorded real-device passes for catalog/purchase on both plans, cancellation versus expiry, restoration, revocation where available, offline/reconnect, and applicable grace/retry behavior. Record unavailable controlled scenarios and any presentation failures explicitly. An unscheduled iOS background refresh is a coverage limitation, not a successful test.

Then turn Simulate Free Tier OFF and Ignore Complimentary Plus OFF. Complimentary Plus returns only if a stored grant exists; otherwise access follows StoreKit. Verify saved shows remain intact. Disable local purchase errors, Ask to Buy, interrupted purchases, and billing failures; restore the scheme's original StoreKit setting and the test device's original Media & Purchases account. Keep screenshots/logs and the completed result sheet. Do not clear purchase history on accounts used for ongoing lifecycle tests until their evidence is recorded.

This document does not itself alter repository or App Store Connect settings. It intentionally separates device-backup/watchlist migration from Restore Purchases and separates real StoreKit state from beta simulation.

---

### OC-11 — Entitlement ordering in real purchase/restore flows (item #1)

**Environment:** real-device sandbox/TestFlight, normal non-granting build, no complimentary entitlement, simulation off. Repeat relevant purchase branches for Monthly and Annual. Use the full setup and lifecycle expectations in SK-01–SK-30.

1. Cold launch while free, then purchase Plus as the app becomes usable. Briefly switch away/back around purchase completion. Confirm Unlimited, add beyond three, inspect saved active/paused rows, then relaunch.
2. Repeat with Restore Purchases on a valid paid account, switching away/back while restore is pending. Confirm access and saved rows converge correctly without transient false lapse alerts or a stuck busy state.
3. Where supported by the chosen test environment, approve a pending customer purchase while the app is running, then while closed; return/relaunch. Keep local Ask to Buy simulation distinct from actual sandbox availability.
4. With actual Plus and more than three saves, exercise a renewal and a genuine lapse/recovery during foreground transitions (SK-11–SK-17). Observe that real active access is not revoked by an older answer and genuine inactivity eventually pauses extras.
5. In the separate simulation fixture (SK-25), complete a customer Plus purchase or pending approval from that simulation session. Check that active access is applied, the simulation ends and the purchase UI becomes usable. Restore/tips/renewals must not end simulation.

**Expected:** no late flip back to free after confirmed active access, no false pause event, no duplicate transaction handling and no permanently enabled simulation after the qualifying successful purchase. Current uncertainty preserves previously confirmed state; it is not automatically a lapse.

**Limits:** UI timing does not prove scans overlapped. Record actual observations and use [CV-06](#controlled-verification-register) for controlled stale answers, cancellation, .unverified and stuck reads. A stalled **newest** read is a known limitation: dependent operations can wait until a later refresh commits or the app restarts. Foregrounding does not currently retry stalled initial resolution, and a stalled transaction handler queues later updates. Do not manufacture a “pass” by treating indefinite loading as normal; if a real stall occurs, capture diagnostics/time/account state and report it. Do not force arbitrary timeout-based entitlement changes.

### Controlled verification register

Record current-candidate automated evidence separately from manual observations; existing test code is not a recorded pass. Unavailable fixtures remain Blocked.

| ID / area | Required controlled scenario and expected result | Existing starting points |
|---|---|---|
| CV-06 Access (item #1) | Hold old inactive/active scans and release in reverse order; only newest-request results apply. A newer successful scan releases callers even while an older one remains held. Purchase/update finishing and simulation completion await applied access; restore overlap, cancellation, burst requests, .unverified newest result and complimentary grant preserve their contracts. Record newest-stall recovery limitation without simulating a false inactive entitlement. | PurchaseServiceEntitlementOrderingTests; PurchaseServiceTests; FreeTierSimulationTests; SubscriptionDowngradeTests; EntitlementCheckOrderingReview-2026-10-19.md |

### Source and decision references

- [Entitlement ordering review](../Reviews/EntitlementCheckOrderingReview-2026-10-19.md), [expiration and restore feedback](../Reviews/ExpirationRecheckAndRestoreFeedback-2026-10-21.md), and [Ignore Complimentary Plus review](../Reviews/IgnoreComplimentaryPlus-2026-10-21.md).
- [Testing override behavior](FreeTierSimulation.md).
- [Apple Ask to Buy testing](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode): use local Xcode approval/decline controls for pending completion; do not assume those controls exist in TestFlight.

### StoreKit release coordination

- Use controlled fixtures/test tooling ([SK-27–SK-30](#controlled-data-checks--complete-with-developer-assistance)) to verify qualifying notification events, long titles, duplicate suppression, removed shows, tap behavior, and background refresh. Natural beta use is supplementary evidence.
- Use [this StoreKit guide](#how-to-use-this-script) and its [result sheet](#result-sheet) to record the detailed coverage below.
- Verify monthly and annual purchasing, cancellation, failures, restore, and each of the three tip products with suitable sandbox accounts ([SK-01–SK-19](#pass-1--purchases-catalog-and-transaction-lifecycle), [SK-23](#sk-23--tips-for-free-and-paid-users)). Complimentary beta access must not mask entitlement failures. TestFlight purchasing does not establish production StoreKit correctness; complete applicable production configuration and launch checks separately.
- Verify Plus expiration with more than three stored shows ([SK-13–SK-17](#pass-2--losing-and-recovering-paid-access), [SK-22](#sk-22--free-slots-paused-reactivation-and-undo)): preserve all stored shows and their export, and check the specified free-tier behavior. Verify complimentary entitlement persistence using the intended grant and ordinary release configurations.
- Verify prices come from StoreKit ([SK-02](#sk-02--product-catalog-prices-disclosures-and-links)), product/period presentation matches App Store Connect, legal links work, and Family Sharing is off for both subscriptions.
- Trim the verbose purchase/paywall diagnostic breadcrumbs added October 23, 2026 (`paywall_*`, `purchase_*`, `storekit_purchase_success`, `transaction_update`), especially transaction IDs, unless still needed.
