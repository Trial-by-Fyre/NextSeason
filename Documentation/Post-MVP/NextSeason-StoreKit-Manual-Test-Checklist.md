# NextSeason — StoreKit manual regression and release testing — checklist

Checklist companion to `NextSeason-StoreKit-Manual-Test-Script.md`, synchronized October 28, 2026. Check steps after performing them and recording outcomes; checked means covered, not necessarily passed. Use a fresh copy per candidate build.

**Updated October 28, 2026.** These are executable manual checks, not recorded passes. Record the exact installed build; working-copy changes are not proof of TestFlight behavior. Use the [plain guide](NextSeason-StoreKit-Manual-Test-Script.md). Case IDs are retained for existing results; removed controlled cases are tracked in the [engineering coverage record](../Reviews/StoreKitEngineeringCoverage-2026-10-28.md).

- [ ] [Recent-fix regression pass](#focused-regression-pass--recent-purchase-fixes)
- [ ] [Setup and broader release checks](#how-to-use-this-script)
- [ ] [Entitlement ordering — OC-11](#oc-11--entitlement-ordering-in-real-purchaserestore-flows-item-1)
- [ ] [Results](#result-sheet) and [cleanup](#completion-and-cleanup)

**Audience:** advanced technical testers and developers; this work can be delegated. Janine coordinates release decisions. The volunteer purchase checks live in the [beta regression guide](NextSeason-Beta-Regression-Checklist.md#volunteer-purchase-checks) and its matching checklist. Ordinary beta testers do not need this document. Start with the TestFlight checks; use Xcode only for the explicitly labeled local tests. No custom UI test mode is needed for the steps retained here.

### Choose your testing session

- [ ] **TestFlight on your iPhone:** focused 1, 2, 3A, 5–10 (8B–8D only), plus the additional device cases below. Use the [paid-device setup](#prepare-a-paid-access-test-device) and [sandbox account controls](#sandbox-account-controls). Focused 3B can also run here using the billing-failure switch.
- [ ] **App launched from Xcode:** focused 4A–4D and local catalog/error/refund checks. Complete [local Xcode setup](#local-xcode-setup), then use the named controls below. This is a separate development run, not your TestFlight installation.
- [ ] **Engineering evidence:** former 3C, 8A and other forced internal-state requirements live in the [coverage record](../Reviews/StoreKitEngineeringCoverage-2026-10-28.md). They are not tasks to attempt or repeatedly mark Blocked here.

Record a result once when focused and SK cases cover the same actions. Use the SK case for its additional branches. Equipment/account prerequisites may still be unavailable; record those as Not run with a reason. Do not invent results for unobserved states.

## Focused regression pass — recent purchase fixes

Updated October 28, 2026. These focused checks cover recent fixes; the later SK cases supply additional release scenarios. Cases 3C and 8A have moved to the engineering record; remaining IDs are unchanged. Use the setup below, record the exact candidate build, and run with Simulate Free Tier OFF except section 10. Use **N** only for a new, untracked show and **P** only for an already-saved paused show. For new-add cases, start with A–C active and N absent from the saved list. For lapse/reactivation, separately prepare at least five saved shows, with P among the later saves that pause. These are different starting states; reset them between cases. The SK cases below use their own A–G show labels, not these N/P labels. Reset purchase state only when needed, after preserving lifecycle evidence. A purchase reset does not remove saved shows: before another new-add case, remove its previous N (or D in the SK cases) and any extra disposable test shows, completing removal with OK/timeout, so the named new show is untracked and A–C are the three active shows. Never remove valued shows to prepare a case.

For every cold launch/relaunch on a complimentary installation, re-enable Ignore Complimentary Plus and confirm the intended access before continuing. Strict startup checks require a non-complimentary installation as explained under paid-device setup. The pending cases in section 4 use Xcode, with the setup below; do them in a separate local session.

### 1. Purchase presentation — SK-02, SK-04/05

These tests target the first-attempt paywall dismissal bug.

#### 1A. Purchase from Search

- [ ] Cold-launch NextSeason with Free access and three tracked shows.
- [ ] Search for show N.
- [ ] Tap the empty star to add the show.
- [ ] Verify the Plus paywall opens.
- [ ] Verify the paywall has Cancel rather than Done.
- [ ] Tap the Monthly plan button on the **first attempt**; there is no separate app Purchase button.
- [ ] Verify Apple's purchase confirmation sheet appears without the paywall disappearing.
- [ ] Verify the correct plan and price are displayed.
- [ ] Cancel Apple's confirmation without completing the purchase.

#### 1B. Purchase from Show Detail

- [ ] Start fresh with Free access and N untracked.
- [ ] Cold-launch NextSeason.
- [ ] Open N's details from Search.
- [ ] Tap the empty star to add the show.
- [ ] Verify the Plus paywall opens.
- [ ] Tap the Annual plan button on the **first attempt**.
- [ ] Verify Apple's confirmation appears over the current interface.
- [ ] Verify the correct plan and price.
- [ ] Cancel Apple's confirmation.

#### 1C. Purchase from About

- [ ] Start fresh with Free access.
- [ ] Cold-launch NextSeason.
- [ ] Open About and select **Unlock NextSeason Plus**.
- [ ] Attempt to purchase a subscription immediately.
- [ ] Verify Apple's confirmation sheet appears on the first attempt.
- [ ] Verify the plan and price.
- [ ] Cancel Apple's confirmation.

**Expected:** No first-tap disappearance, blank screen, unexpected navigation, or requirement to retry.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 2. Successful purchase — SK-04/05

Run this from both Search and Show Detail, using a different sandbox account with no purchases or the purchase-history reset in [sandbox account controls](#sandbox-account-controls) between runs. Preserve lifecycle evidence before resetting.

#### 2A. Search

- [ ] Start with three tracked shows and N untracked.
- [ ] Search for N and tap its empty star to add it.
- [ ] Purchase Plus successfully.
- [ ] Verify the paywall dismisses automatically.
- [ ] Verify Plus becomes active.
- [ ] Verify N was added **exactly once automatically**.
- [ ] Do not tap N’s star a second time.
- [ ] Verify any notification-permission prompt remains usable.
- [ ] Verify subsequent shows can be added.

#### 2B. Show Detail

- [ ] Repeat with N initially untracked, starting from its detail page.
- [ ] Purchase Plus successfully.
- [ ] Verify the paywall dismisses.
- [ ] Verify N is automatically tracked, exactly once.
- [ ] Verify the Show Detail interface reflects the new tracked state.
- [ ] Verify notification-permission prompts, if presented, can be responded to normally.

**Expected:** The purchase completes the original Add Show request. No retry, duplicate, or lost action.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 3. Cancellation and purchase failure — SK-06/07

#### 3A. Apple purchase cancellation

- [ ] With Free access, attempt to add N.
- [ ] Start a Plus purchase.
- [ ] Cancel from Apple's confirmation sheet.
- [ ] Verify the NextSeason paywall remains available.
- [ ] Verify N remains untracked.
- [ ] Verify the user can retry the purchase.
- [ ] Tap Cancel on the NextSeason paywall.
- [ ] Verify the paywall closes and the blocked add is abandoned.

#### 3B. Purchase failure

**Setup:** use the [sandbox billing-failure switch](#sandbox-account-controls), or the [Xcode purchase-error control](#local-xcode-setup). Start Free with N untracked and A–C active.

- [ ] Turn on purchase failure, then attempt to buy Plus from N's blocked add.
- [ ] Verify an understandable failure message appears and N remains untracked.
- [ ] Verify the paywall remains usable for retry or cancellation.
- [ ] Turn failure off and retry successfully; N is added once and Plus becomes active.

**Result:** Pass / Fail / Not run; record the environment and any error text.

### 4. Pending purchases — local Xcode / SK-08

**Setup for all four cases:** follow [Ask to Buy setup](#ask-to-buy-setup) below. Start each case with Free access, A–C active and N untracked. These controls are built into Xcode; no custom app fixture is required.

#### 4A. Pending transaction completes while paywall remains open

- [ ] Start a blocked add for N.
- [ ] Attempt a Plus purchase and choose **Ask** in Apple’s Ask Permission dialog. In Xcode’s transaction manager, confirm **Pending Ask to Buy** before continuing.
- [ ] Keep the original paywall open.
- [ ] In Xcode’s transaction manager, select the pending purchase, Control-click it, and choose **Approve**.
- [ ] Verify Plus becomes active.
- [ ] Verify the paywall dismisses.
- [ ] Verify N is automatically added exactly once.

#### 4B. Transaction completes after paywall dismissal

- [ ] Start a blocked add for N.
- [ ] Attempt a Plus purchase, choose **Ask**, and confirm **Pending Ask to Buy** in Xcode’s transaction manager.
- [ ] Dismiss the paywall, if permitted.
- [ ] In Xcode’s transaction manager, Control-click the pending purchase and choose **Approve** afterward.
- [ ] Verify Plus access is recognized.
- [ ] Verify N is **not automatically added** because the original add was abandoned.
- [ ] Verify the user can add N normally afterward.

#### 4C. Transaction completes after relaunch

**Open failure:** build 50 granted Plus before approval in the owner’s iOS 27.0 simulator test, while Xcode still showed pending approval. Keep this case failed until resolved; see [diagnostic evidence](../Reviews/StoreKitPendingRelaunch-2026-10-28.md).

- [ ] Start a blocked add for N.
- [ ] Attempt a Plus purchase, choose **Ask**, and confirm **Pending Ask to Buy** in Xcode’s transaction manager.
- [ ] Terminate and relaunch NextSeason.
- [ ] In Xcode’s transaction manager, Control-click the pending purchase and choose **Approve**.
- [ ] Verify Plus access is restored.
- [ ] Verify the abandoned Add Show operation does not resume.
- [ ] Verify N remains untracked until explicitly added.

#### 4D. Pending purchase is declined

**Open failure:** owner reported that a new purchase declined in Xcode’s transaction manager was recorded as successful by NextSeason. See the [failure record](../Reviews/StoreKitPendingRelaunch-2026-10-28.md#declined-purchase-reported-as-successful). Cause is not established; keep this case failed until resolved.

- [ ] Save evidence of earlier cases before resetting. Use the Ask to Buy setup to delete local subscription transactions, relaunch, and confirm Free access with A–C active and N untracked. Do not carry a previously approved subscription into this case.
- [ ] Start N’s blocked add, choose a Plus plan, and choose **Ask** in Apple’s dialog.
- [ ] Confirm the transaction is **Pending Ask to Buy** in the manager and NextSeason still shows Free access.
- [ ] In the transaction manager, Control-click that pending transaction and choose **Decline**.
- [ ] Verify NextSeason does not report a successful purchase, grant Plus, or add N. The app remains usable, and the paywall can be dismissed or used to retry.
- [ ] Relaunch and verify access remains Free and N remains untracked. Re-enable Ignore Complimentary Plus only if the test installation has a stored grant; leave Simulate Free Tier OFF.

**Expected:** An active pending action completes automatically only after approval; an abandoned action never comes back unexpectedly. Declining grants no Plus access and produces no purchase-success result.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

---

### 5. Subscription expires in background — SK-13

- [ ] Start with an active Monthly Plus subscription and at least five tracked shows.
- [ ] Confirm Ignore Complimentary Plus is ON.
- [ ] Cancel automatic renewal using Apple's sandbox instructions.
- [ ] Confirm the subscription remains active until expiration.
- [ ] Background NextSeason.
- [ ] Wait until the subscription actually expires.
- [ ] Reopen NextSeason.
- [ ] Verify the entitlement refresh recognizes Free access.
- [ ] Verify only the three oldest shows remain active.
- [ ] Verify other shows are visible but paused.
- [ ] Verify paused-show details are not accessible without Plus.
- [ ] Verify no shows were deleted or duplicated.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 6. Subscription expires in foreground — SK-14

- [ ] Start with an active Monthly Plus subscription and at least five tracked shows.
- [ ] Confirm Ignore Complimentary Plus is ON.
- [ ] Cancel automatic renewal.
- [ ] Leave NextSeason open in the foreground.
- [ ] Wait until the subscription expires.
- [ ] Continue through the scheduled expiration recheck, approximately five minutes after expiration.
- [ ] Verify the app recognizes Free access without a restart.
- [ ] Verify only the three oldest shows remain active.
- [ ] Verify remaining shows are paused.
- [ ] Verify expiration notices do not repeat unnecessarily.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 7. Resubscription and reactivation — SK-17

#### 7A. Ordinary resubscription

- [ ] Start with an expired subscription and at least two paused shows.
- [ ] Open the paywall.
- [ ] Purchase Plus.
- [ ] Verify all paused shows reactivate.
- [ ] Verify data, ordering, and sections are preserved.
- [ ] Verify another show can be added.

#### 7B. Blocked add for an already-saved paused show

Run through Search and Show Detail. Use the expired state from section 5: three active shows and P already saved but paused.

- [ ] Start with an already-saved paused show P.
- [ ] Find P through Search or its available detail/add entry point.
- [ ] Attempt to add or reactivate P.
- [ ] Verify the Plus paywall opens.
- [ ] Purchase Plus. The separate restore-during-blocked-add requirement is retained in the engineering record.
- [ ] Verify P remains tracked.
- [ ] Verify no duplicate is created.
- [ ] Verify P is not removed.
- [ ] Verify no inappropriate Undo toast appears.
- [ ] Verify P becomes active and accessible.

- [ ] Let the sandbox subscription expire again as in section 5, confirm P is paused with three active shows, then repeat for the other entry point.

**Expected:** Reactivation does not accidentally toggle the existing saved show off.

#### 7C. Monthly purchase first attempt for an already-saved show

**Open failure:** owner reports the first Monthly purchase attempt displays **Couldn't Complete Purchase** / “The purchase wasn't completed, so NextSeason Plus wasn't unlocked. Please try again.” It has occurred intermittently elsewhere and appears consistent when purchasing to reactivate an already-saved show; the second attempt succeeds. See [report and screenshot](../Reviews/StoreKitMonthlyFirstAttempt-2026-10-28.md).

Reuse 7B’s starting state and Monthly purchase actions. Record the first attempt separately from any retry, including whether Apple’s sheet appeared and whether Plus/the saved show became active. If retry succeeds, preserve the first-attempt failure; do not mark it passed merely because retry worked. Expected: a valid purchase succeeds on the first attempt and reactivates the saved show once.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

---

### 8. Restore Purchases — SK-18

#### 8B. No eligible subscription

- [ ] Use a sandbox account with no eligible active subscription.
- [ ] Attempt to add N to trigger the paywall.
- [ ] Tap Restore Purchases.
- [ ] Verify Plus is not incorrectly granted.
- [ ] Verify N remains untracked.
- [ ] Verify the user receives understandable feedback.
- [ ] Verify the paywall remains available.

#### 8C. Offline Restore and reconnect

**Open recovery failure:** after an offline Restore error, the owner restored connectivity, dismissed the error and retried a purchase; the app displayed the purchase-not-unlocked error. Reported as repeatable; see the [8C recovery report and screenshot](../Reviews/StoreKitReconnectPurchaseFailure-2026-10-28.md). Keep this separate from the wording improvement below.

**Open presentation improvement:** the observed alert uses a purchase-specific title and generic restore error. Record clearer restore/network wording as a follow-up; see the [8C report](../Reviews/StoreKitRestoreErrorMessaging-2026-10-28.md). This does not establish the underlying error code.

- [ ] Start Free with N untracked and three active shows; trigger the paywall through N's blocked add.
- [ ] Turn on Airplane Mode and explicitly turn Wi-Fi off.
- [ ] Tap Restore Purchases; record the actual result. Cached StoreKit data can allow a successful response, so an error is not required.
- [ ] Verify no crash or indefinite hang occurs and N remains untracked while there is no active Plus subscription. If an error appears, check that it is understandable and dismissible.
- [ ] Restore connectivity and retry. Verify controls remain usable and the final access matches the account.

This tests offline behavior and reconnection. Forced restore errors belong to the engineering record; an offline success does not establish that error branch.

#### 8D. Restore after expiration

- [ ] Start with expired Plus and paused shows.
- [ ] Tap Restore Purchases.
- [ ] Verify an expired subscription does not incorrectly unlock Plus.
- [ ] Verify paused shows remain intact.
- [ ] Verify appropriate feedback is displayed.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 9. Tips — SK-23

- [ ] Tips are separate consumable purchases and must never unlock Plus.

#### 9A. First-attempt purchase presentation

- [ ] Start with Free access.
- [ ] Cold-launch NextSeason.
- [ ] Open About and locate the tip options.
- [ ] Select a tip and initiate purchase.
- [ ] Verify Apple's confirmation sheet appears on the first attempt.
- [ ] Verify the correct tip and price.
- [ ] Verify About remains presented normally.

#### 9B. Cancellation

- [ ] Cancel from Apple's confirmation sheet.
- [ ] Verify no tip purchase is recorded as successful.
- [ ] Verify the user can attempt a tip again.
- [ ] Verify access remains Free.

#### 9C. Successful tip

- [ ] Complete a tip purchase.
- [ ] Verify appropriate confirmation or acknowledgment.
- [ ] Verify Plus is not unlocked.
- [ ] Verify the Free-tier three-show limit still applies.
- [ ] Verify tracked shows are unchanged.
- [ ] Verify the app does not display an unintended subscription paywall.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### 10. Simulate Free Tier — SK-25

- [ ] Start with active StoreKit Plus and at least five active shows.
- [ ] Confirm Ignore Complimentary Plus is ON.
- [ ] Turn Simulate Free Tier ON.
- [ ] Verify the three oldest shows remain active.
- [ ] Verify remaining shows become paused but remain visible.
- [ ] Turn Simulate Free Tier OFF.
- [ ] Verify all shows reactivate.
- [ ] Relaunch NextSeason.
- [ ] Re-enable Ignore Complimentary Plus if a stored grant is present.
- [ ] Verify access reflects actual StoreKit entitlement and simulation settings.
- [ ] Verify no shows or data were lost.

**Result:** Pass / Fail / Blocked / Not applicable / Not run; record each subcase separately with build, environment and evidence.

### How to use this script

**Show setup:** the SK cases use A–G added in that order. D is initially new in purchase cases and later saved/paused in lapse cases; establish each case’s stated starting state. Do not carry the focused pass’s N/P assumptions into these cases.

For recent fixes, use the focused regression pass above after completing setup. For broader manual coverage, run the retained SK cases in their listed passes. SK-28 and the controlled portions of other cases are in the engineering record. Each case gives its starting state, actions, and expected result. Record **Pass / Fail / Blocked / Not applicable**, the build, and any evidence. “Blocked” means you could not establish the required state; it does not mean the feature passed.

Use three passes:

- [ ] 1. **Local Xcode:** repeatable purchase, pending, error, refund, and expiration scenarios.
- [ ] 2. **Real-device sandbox/TestFlight:** actual product configuration, entitlement persistence, offline behavior, restore, and billing states.
- [ ] 3. **Complimentary and simulation:** the special beta-access rules, tested separately from paid access.

Repeat monthly and annual purchase/lapse/restoration cases for both plans. Run core purchase, cancel, restore, and paused-row screens with VoiceOver and the largest practical text size on the oldest supported iOS device you have, and on your current iOS device. One device may satisfy both passes when appropriate.

Do not wait for a live TVMaze change or try to manufacture a timing race. Controlled notification and ordering requirements are in the engineering record; ordinary device notification taps remain below.

### Record the test setup

- [ ] Tester / date:
- [ ] App version / build / commit:
- [ ] Device / iOS version:
- [ ] Xcode version, if applicable:
- [ ] Install source: Xcode local / Xcode sandbox / TestFlight / App Store:
- [ ] Scheme and build configuration:
- [ ] StoreKit configuration: NextSeason.storekit / None:
- [ ] Test account alias (do not record passwords):
- [ ] Storefront / displayed currency:
- [ ] Renewal speed and observed expiration time:
- [ ] Billing Grace Period enabled for sandbox? Yes / No:
- [ ] Complimentary access present? Yes / No:
- [ ] Ignore Complimentary Plus enabled this session? Yes / No:
- [ ] Simulate Free Tier enabled? Yes / No:

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

For strict genuinely Free cold-launch tests, use a normal non-granting build with no active subscription and no stored/synchronized complimentary grant. An unused spare device on the same iCloud Keychain can inherit a grant; confirm settled Free access with both overrides OFF rather than relying on reinstall. Do not change the owner’s iCloud account or delete a grant just for testing.

Check About before testing. For Janine/developer-assisted tests on an installation with complimentary access, open About → Diagnostics → Subscription Testing and turn **Ignore Complimentary Plus ON**, with **Simulate Free Tier OFF**. Wait for access to settle and verify Free when no active subscription exists. Ignore Complimentary Plus hides the stored grant without deleting it; it does not hide a paid subscription.

**Both testing overrides are session-only and reset on app termination. After every cold launch/relaunch on a complimentary installation, re-enable Ignore Complimentary Plus before checking StoreKit-only access.** While it is off during startup, complimentary access may already reactivate paused shows; use a separate non-complimentary installation for strict cold-launch paid-access-loss/ordering evidence. Mark that branch Blocked if unavailable. Do not clear a genuine grant. Deleting the app or switching purchase accounts does not reliably remove its synchronizable Keychain grant. Volunteers use the purchase section in the beta regression guide.

Turn **Simulate Free Tier OFF** for every real StoreKit test. It overrides effective access and intentionally survives restore scans within the session.

Remove UI-testing/profile launch arguments. UI tests use stubs and are not a manual StoreKit session.

#### Local Xcode setup

Use a simulator or disposable development installation. Local StoreKit transactions do not charge an Apple Account, and do not validate App Store Connect products. Do not replace your only valuable TestFlight installation just to run local checks.

- [ ] 1. Open `NextSeason.xcodeproj` in Xcode. Select the normal **NextSeason** scheme and your test simulator/device, not **NextSeason - Final Complimentary Beta**.
- [ ] 2. Open **Product → Scheme → Edit Scheme → Run → Options**. Record the current **StoreKit Configuration**, then select **NextSeason.storekit**. The existing file is `NextSeason/StoreKit/NextSeason.storekit`; no new configuration file is needed.
- [ ] 3. Open that file in the Project navigator. Select **Configuration Settings** and keep purchase dialogs enabled. Run the app with Xcode’s Run button.
- [ ] 4. Open **Debug → StoreKit → Manage Transactions** and select NextSeason on the correct simulator/device. This is where you inspect, approve, decline, delete and refund local purchases.
- [ ] 5. To start another Free case, first save any evidence, then select and **delete** the local subscription transactions in this manager. Turn off error/interruption options, relaunch, and confirm About settles to **Up to 3 shows**. Deleting local transactions resets purchase state, not the Watchlist. Use Refund only in the refund test. On a complimentary installation, re-enable **Ignore Complimentary Plus** after relaunch; keep **Simulate Free Tier OFF** unless the case explicitly tests it.
- [ ] 6. For a **purchase error**, select the configuration file → **Configuration Settings** → **Simulated StoreKit Errors**. Enable the **Purchase** API error and choose a network error. Retry the purchase in the app, then disable that error to recover.
- [ ] 7. For a **catalog error**, use the same error settings for **Load Products** (product loading), then terminate and run the app so no earlier in-memory catalog is reused. Open the Plus sheet, observe its unavailable state, disable the error, and tap Try Again.
- [ ] 8. When done, disable all errors/Ask to Buy/interruption settings and restore the scheme’s original StoreKit Configuration. Select **None** for a subsequent Xcode sandbox run; local transaction history and sandbox purchase history are separate.

Apple documents these controls in [local setup](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode), the [transaction manager](https://developer.apple.com/documentation/xcode/testing-in-app-purchases-with-storekit-transaction-manager-in-code), and [StoreKit error simulation](https://developer.apple.com/videos/play/wwdc2023/10140/). Setting names can vary slightly by Xcode version; record the actual selected API/error.

#### Ask to Buy setup

For focused 4A–4D and SK-08:

- [ ] 1. Complete local Xcode setup above and establish Free access with three active shows. Leave the show to be added untracked.
- [ ] 2. Select **NextSeason.storekit** → **Configuration Settings**. Under **Purchase Options**, enable **Ask to Buy**. In older Xcode layouts, the same switch is under **Editor → Enable Ask to Buy** while that file is selected.
- [ ] 3. Run NextSeason. Attempt Monthly or Annual from the blocked-add paywall. In Apple’s **Ask Permission** dialog choose **Ask**. The transaction manager must show **Pending Ask to Buy**; Plus must still be inactive.
- [ ] 4. Leave that pending transaction alone while performing the case’s app actions. To complete it, Control-click it in the manager and choose **Approve**; for the decline branch choose **Decline**.
- [ ] 5. Between cases, delete the local test subscription transactions, relaunch, reapply Ignore Complimentary Plus if needed, and confirm Free. Keep Ask to Buy on for the next pending case; turn it off when these cases are finished.

Do not sign into a child account or configure a real family. This is Apple’s local simulation, separate from TestFlight. See [Apple’s Ask to Buy instructions](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode).

#### Real-device sandbox and TestFlight setup

Create dedicated Sandbox Apple Accounts in App Store Connect → Users and Access → Sandbox. Use accounts with no prior purchase history for fresh-state cases. For an Xcode device build, set the scheme's StoreKit configuration to **None** and use the sandbox account controls on the device.

TestFlight uses sandbox purchases. For controllable billing and renewal scenarios, Apple directs testers to sign out of the production account under **Media & Purchases**, then sign in to the Sandbox Apple Account under Developer settings. Use a dedicated test device where practical; record the original account so you can restore it afterward. Default TestFlight renewals are daily, irrespective of monthly/annual duration; custom sandbox-account settings provide other rates. Do not assume a monthly test lasts a production month. [Apple TestFlight guidance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/).

Sign out of Media & Purchases **before the first launch** of each new TestFlight build. Switching accounts while NextSeason is running can leave StoreKit with the previous account's subscription: Plus may appear active, and after signing out the first purchase can return instantly without Apple's sheet. If that happens, force-quit and relaunch NextSeason before testing purchases.

For short monthly lapse tests, the sandbox account’s three-minute monthly renewal setting is available; use a longer period for offline tests. Record Apple’s actual expiration rather than timing only from the purchase tap. To stop sandbox renewal on iPhone: Settings → Developer → Sandbox Apple Account → Manage → Subscriptions → NextSeason Plus → Cancel Subscription. Cancellation stops renewal, with access retained until expiration. [Apple cancellation instructions](https://developer.apple.com/documentation/storekit/testing-disabling-auto-renew).

Select a manageable renewal rate and note the transaction's expiration. Sandbox settings also allow interrupted purchases and clearing purchase history; clearing that history does not clear the app's watchlist or complimentary Keychain grant. Allow the reset to propagate before starting. [Apple sandbox account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/).

#### Sandbox account controls

Use only your dedicated Sandbox Apple Account, and preserve ongoing lifecycle evidence before resetting its history.

- [ ] **Fresh purchase state:** switch to a new sandbox test account with no purchases, or use Settings → Developer → Sandbox Apple Account → Manage → **Clear Purchase History**. Wait for clearing to finish, force-quit/relaunch NextSeason, re-enable Ignore Complimentary Plus if needed, and confirm settled Free access. Leave Simulate Free Tier OFF. This does not erase your Watchlist or complimentary grant.
- [ ] **Failed purchase / failed renewal:** in Settings → Developer → Sandbox Apple Account → Manage → **Account Settings**, turn **Allow Purchases & Renewals OFF**. A new purchase fails; an existing subscription fails at its next renewal. Turn the same switch ON for a successful retry or billing recovery. This affects that sandbox account on all its devices; restore it when finished. [Apple billing controls](https://developer.apple.com/documentation/storekit/testing-failing-subscription-renewals-and-in-app-purchases).
- [ ] **Interrupted purchase:** in App Store Connect → Users and Access → Sandbox, select the test account, enable **Interrupt Purchases for This Tester**, and Save. Attempt a purchase; leave its requested action unfinished for SK-09, then complete the displayed action or disable that option and retry. [Apple account controls](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/).
- [ ] **Cancel renewal / change plan:** on the iPhone, Settings → Developer → Sandbox Apple Account → Manage → **Subscriptions** → **NextSeason Plus**. Cancel Subscription stops future renewals; the existing paid period must actually expire before testing lapse. Select the other available plan for SK-11 and record Apple’s effective date.

#### Watchlist setup

Choose seven available shows. Label them in your notes **A–G**, record their names/TVMaze IDs, and add them in that order when instructed. A, B, C must be the oldest. Prefer shows with stable source data. Record their status and “Updated” times before lapse tests.

“Relaunch” below means close the app completely and open it again. “Foreground return” means switch to another app and return without terminating NextSeason.

### Pass 1 — purchases, catalog, and transaction lifecycle

#### SK-01 — Fresh free user and both paywall entry points

**Start:** no subscription, no complimentary access, simulation off, empty watchlist.

- [ ] 1. Open About. Confirm the settled capacity is up to three shows and Unlock NextSeason Plus is available.
- [ ] 2. Add A, B, C from Search. Attempt D from Search.
- [ ] 3. Dismiss the Plus sheet. Open D's detail and attempt to track it there.
- [ ] 4. Open the Plus sheet directly through About, then dismiss it.

**Expected:** both fourth-add attempts show the same Plus options and do not save D. Three shows remain active. Dismissing the sheet makes no purchase and leaves navigation usable. Initial “Checking…” must settle; no indefinite loading.

#### SK-02 — Product catalog, prices, disclosures, and links

**Start:** SK-01 state; online. Run locally, then again in TestFlight; record local prices separately from the real App Store Connect catalog.

- [ ] 1. Inspect Monthly and Annual, their period labels, currency, and price.
- [ ] 2. Open each Apple purchase sheet and compare its product/period/price with the app; cancel both.
- [ ] 3. Open Terms of Use and Privacy Policy, then return.
- [ ] 4. Inspect all three tip options in About.

**Expected:** products match their identifiers and the selected environment’s configuration. The TestFlight run, rather than local StoreKit, must agree with App Store Connect. No lifetime option appears. Subscription disclosure and links are readable; links load the intended pages. Tip copy says tips do not unlock features. No stale error or duplicate sheet appears on return.

#### SK-03 — Catalog failure and retry

**Environment:** local Xcode, using the catalog-error setup in [local Xcode setup](#local-xcode-setup), step 7.

- [ ] 1. Enable the Load Products error, terminate/re-run the app, then open About and the Plus sheet. Turning off internet is not this local error setup.
- [ ] 2. Observe loading and eventual failure.
- [ ] 3. Disable the Load Products error. Tap Try Again.

**Expected:** unavailable products are not replaced with invented live prices or enabled purchase buttons. A recoverable unavailable message appears; retries restore the catalog. Existing paid access and saved shows do not disappear because product loading failed. Dismiss remains usable when no purchase is in flight.

#### SK-04 — Monthly purchase

**Start:** free account, A–C active, no prior subscription.

- [ ] 1. Attempt D, then purchase Monthly and approve Apple's confirmation.
- [ ] 2. Observe the Plus sheet closing and About reporting Unlimited. Confirm D is already tracked exactly once before trying to add anything else.
- [ ] 3. Confirm D was added automatically exactly once; do not tap its star again. Add E–G, switch tabs and reopen a saved detail. Repeat from Search and Show Detail with fresh Free state.
- [ ] 4. Relaunch and attempt another addition.

**Expected:** verified Monthly unlocks access without requiring Restore Purchases. Unlimited survives relaunch. No duplicates, unintended paused rows, or repeated purchase prompts. A successful purchase completes the original blocked add automatically exactly once; needing to tap Add again is a failure. Any notification-permission prompt remains usable.

#### SK-05 — Annual purchase

Reset purchase history using the appropriate environment; establish a genuinely free account. Repeat SK-04 with Annual. Confirm the payment sheet uses Annual and its yearly price. Keep one paid test account/installation for the later lifecycle cases.

#### SK-06 — Cancel the purchase sheet

**Start:** free, A–C active.

- [ ] 1. Start a Monthly purchase and cancel Apple's purchase sheet.
- [ ] 2. Repeat for Annual and a tip.
- [ ] 3. Dismiss the app's Plus sheet and navigate normally.

**Expected:** no Plus grant, no tip thank-you, no scary failure alert for ordinary cancellation, and no stuck busy state. Fourth additions remain blocked.

#### SK-07 — Failed purchase and recovery

**Start:** Free. Enable the Purchase API error in [local Xcode setup](#local-xcode-setup), step 6, or turn Allow Purchases & Renewals OFF using [sandbox account controls](#sandbox-account-controls).

- [ ] 1. Attempt Monthly with failure enabled.
- [ ] 2. Dismiss the error; repeat with Annual and one tip.
- [ ] 3. Turn failure simulation off and retry a subscription successfully.

**Expected:** no entitlement from a failed transaction; clear recoverable feedback; controls usable after failure; successful retry grants access. Errors do not appear twice through both About and the Plus sheet. [Apple purchase-failure guidance](https://developer.apple.com/documentation/storekit/testing-failing-subscription-renewals-and-in-app-purchases).

#### SK-08 — Pending purchase approved, declined, and approved while app is closed

**Environment:** local Xcode. Follow [Ask to Buy setup](#ask-to-buy-setup), including the transaction reset between runs. Start A–C active and D untracked. These approval controls do not operate on your TestFlight installation.

- [ ] 1. With A–C active and D untracked, attempt to add D, choose Monthly on its paywall, then choose **Ask** in Apple’s Ask Permission dialog. Confirm **Pending Ask to Buy** in the transaction manager.
- [ ] 2. Verify no Plus access yet; the app is navigable after the purchase call returns pending.
- [ ] 3. Keep the original blocked-add paywall open and approve in the manager. Confirm Unlimited, automatic dismissal, and D added exactly once.
- [ ] 4. Delete the local subscription transactions, relaunch, confirm Free and leave D untracked. Repeat with Annual, but decline the pending transaction. Confirm free access remains.
- [ ] 5. Delete the local subscription transactions, relaunch and confirm Free. Create a pending blocked add, dismiss the paywall, then approve: Plus unlocks but D stays untracked because the add was abandoned.
- [ ] 6. Delete the local subscription transactions, relaunch and confirm Free. Create a pending blocked add, close the app, approve it, then relaunch: Plus unlocks but the abandoned add does not resume. Reapply Ignore Complimentary Plus after relaunch if needed.

**Expected:** access arrives only after verified completion. Delayed/launch completion is recognized without purchasing twice. Declining grants nothing. Pending is not falsely described as success. There may be no dedicated in-app pending message in the current UI; record the experience separately from entitlement correctness. [Apple Ask to Buy guidance](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode).

#### SK-09 — Interrupted purchase

**Environment:** sandbox. Follow the **Interrupted purchase** instructions in [sandbox account controls](#sandbox-account-controls) before starting.

- [ ] 1. Start a subscription and follow the interrupted flow without completing the required external action.
- [ ] 2. Return to NextSeason. Check capacity and ability to navigate.
- [ ] 3. Complete the required sandbox action/remove interruption, then finish or retry purchase.

**Expected:** no premature Plus grant; no permanently stuck purchase overlay; completion is recognized. Record whether recovery occurred through the original transaction or a retry.

#### SK-10 — Rapid taps and lifecycle interruption

**Environment:** local Xcode, Free access. Run for a subscription and a tip; inspect counts in Debug → StoreKit → Manage Transactions.

- [ ] 1. Tap a purchase button rapidly twice; try another purchase control while Apple's sheet is active.
- [ ] 2. Cancel. Start again, background NextSeason during the flow, then return.
- [ ] 3. In a separate run, complete purchase and relaunch immediately afterward.

**Expected:** app-originated purchases are not duplicated; no overlapping app sheets or stuck controls. A completed subscription is present after return/relaunch. A completed tip does not unlock Plus. Judge transaction counts using the manager, not just visual alerts.

#### SK-11 — Automatic renewal and switching plans

**Start:** paid, A–G saved, simulation off.

- [ ] 1. Allow at least one real test renewal. Check About and every row before and after foreground return/relaunch.
- [ ] 2. Use the environment's subscription-management UI to switch Monthly → Annual; repeat Annual → Monthly on another run.
- [ ] 3. Note the effective time shown by Apple; check again after the switch takes effect.

**Expected:** no lapse while Apple reports an active entitlement, no duplicate tracked shows, no pausing from a valid renewal, and no historical catch-up burst. Plan changes preserve Plus; do not assume every switch takes effect immediately. Validate that App Store Connect places both plans in the intended subscription group.

### Pass 2 — losing and recovering paid access

#### SK-12 — Cancel renewal without expiring

**Environment:** sandbox/TestFlight, paid A–G, comfortably before expiration; use the recorded sandbox renewal rate.

- [ ] 1. Turn off auto-renew using the environment's subscription-management controls. Use Settings → Developer → Sandbox Apple Account → Manage → Subscriptions → NextSeason Plus → Cancel Subscription. Do not use Refund or transaction deletion as a substitute.
- [ ] 2. Record Apple's entitlement expiration.
- [ ] 3. Return to NextSeason before that time, relaunch, and add another show.

**Expected:** Plus remains Unlimited through the paid period; all shows remain active. Cancellation of renewal alone does not pause anything. [Apple local transaction controls](https://developer.apple.com/documentation/xcode/testing-in-app-purchases-with-storekit-transaction-manager-in-code).

#### SK-13 — Actual expiration with app away

**Start:** SK-12; stop auto-renew and confirm expiration occurs.

- [ ] 1. Leave the app backgrounded while the entitlement expires. Reopen after expiration.
- [ ] 2. Record active and paused names, alert text, row styles, and saved total.
- [ ] 3. Open A; tap D–G in Watchlist; swipe-delete one paused row and Undo.
- [ ] 4. Acknowledge the pause alert, relaunch, and inspect again.

**Expected:** A–C remain active; later saves are retained in Paused — Plus Required. Paused rows hide old season/timestamp information and cannot open detail from Watchlist. Active rows still open. Paused removal/Undo preserves its pause state. No saved show disappears merely because Plus expired. The acknowledged alert does not recur without a new pause event. If Apple has not actually expired the entitlement, this is not a valid expiration test.

#### SK-14 — Expiration while the app is open; foreground/background reconciliation

Repeat expiration while NextSeason stays visible, then switch away and return. Repeat once with the app closed before expiration, and once with an actual scheduled background refresh if your device delivers one.

**Expected:** a foreground entitlement reread detects the lapse and applies the same three-show policy before ordinary watchlist refresh. While continuously foregrounded, the app re-checks about 5 minutes after Apple's recorded expiration and applies the same policy then; record the observed time. A renewal that arrives before then must not pause anything. A billing grace period end is detected on the next foreground return, not by this timer. A background run must reconcile before processing shows. If iOS never schedules a background run, mark that portion Blocked, not Pass.

#### SK-15 — Refund/revocation

**Environment:** [local Xcode setup](#local-xcode-setup), with Ask to Buy and errors off. This is the local refund test; it is not evidence of a sandbox/App Store refund.

- [ ] 1. Establish paid A–G. Open Debug → StoreKit → Manage Transactions, select the active subscription transaction, and click **Refund**.
- [ ] 2. Check the running app, then foreground return and relaunch.
- [ ] 3. Attempt a fourth active addition.

**Expected:** once the verified entitlement is revoked, paid access is removed and extra shows pause without deletion. Fourth additions are blocked. No remaining second valid subscription or complimentary grant may mask this case. Turning renewal off is not equivalent to revocation.

#### SK-16 — Billing grace, grace recovery, and billing retry without entitlement

**Environment:** real-device sandbox account. First record whether Billing Grace Period is enabled for sandbox in App Store Connect.

- [ ] 1. Purchase Plus with Allow Purchases & Renewals ON. Before the next renewal, turn that switch OFF using [sandbox account controls](#sandbox-account-controls).
- [ ] 2. When Apple reports a grace state, check About, additions, and all seven shows.
- [ ] 3. Turn Allow Purchases & Renewals ON before grace ends and allow renewal. Confirm access remains.
- [ ] 4. On a separate run, let grace end without recovery, or test billing retry without a grace entitlement. Return to the app.
- [ ] 5. Turn Allow Purchases & Renewals ON and confirm valid access returns after Apple completes recovery.

**Expected:** Apple's active/grace entitlement keeps Plus. After no entitled state remains, A–C stay active and extras pause. Recovery resumes all saved rows, with silent catch-up. If grace is not configured, mark the grace-specific branch Not applicable and still test retry/expiration. Do not classify every payment failure as immediate access loss. [Apple billing-test guidance](https://developer.apple.com/documentation/storekit/testing-failing-subscription-renewals-and-in-app-purchases).

#### SK-17 — Resubscribe after lapse and repeated lapse

**Start:** use SK-13’s expired subscription, with three active shows and extras paused.

- [ ] 1. Buy Monthly or Annual again. Inspect all saved shows as access returns.
- [ ] 2. Pull to refresh; relaunch. Record any notifications during reactivation.
- [ ] 3. Let paid access lapse again.

**Expected:** every saved paused row resumes without duplicates. Catch-up updates old data without announcing changes from the paused interval. A later lapse chooses the three oldest surviving saves again; previous free-period selections are not remembered as a separate preference. Current access-change alerts should not remain after restoration. Controlled notification-history verification is in the [engineering record](../Reviews/StoreKitEngineeringCoverage-2026-10-28.md); ordinary notification observations do not establish silent catch-up correctness.

#### SK-18 — Restore Purchases: active, inactive, offline, repeated

- [ ] 1. With an active paid account, use Restore Purchases from About; repeat from the Plus sheet if reachable. Relaunch first if needed.
- [ ] 2. Repeat on a fresh account without purchases and on an expired account.
- [ ] 3. Use Airplane Mode with Wi-Fi off and tap Restore, noting the actual outcome; cached responses may succeed. Reconnect and retry. Check any observed error for clear feedback, but do not require a failure or claim this proves the forced-error branch.
- [ ] 4. Tap Restore rapidly twice and repeat a successful restore.

**Expected:** valid access is recovered; restore does not purchase or duplicate shows. No-purchase/expired accounts remain free and see a Restore Purchases alert saying no active subscription was found (in the Plus sheet or About, wherever Restore was tapped); no false “Plus restored” claim. Failure gets recoverable feedback and no stuck busy state. Repeating restore is harmless. Automatic entitlement detection may restore access before you tap Restore; record that as automatic detection, not proof that the button changed access.

#### SK-19 — Reinstall and second-device distinction

**Start:** active subscription on a disposable test installation; export its watchlist first if needed.

- [ ] 1. Delete and reinstall NextSeason using the same testing environment/account. Open About and use Restore if necessary.
- [ ] 2. Repeat on a second device with the same purchase account if available.

**Expected:** paid entitlement is recoverable. Restore Purchases does not itself import the old watchlist. A fresh installation/device may have no saved shows; do not mistake that for subscription failure. Device-backup restoration is a separate migration test, not part of purchase restoration. Do not do this on your only valuable watchlist.

### Pass 3 — offline, limits, tips, and beta rules

#### SK-20 — Existing subscriber offline, without crossing expiration

**Environment:** real-device sandbox/TestFlight; active paid account with no complimentary grant. Choose a long enough test period and record expiration.

- [ ] 1. Launch online and confirm Unlimited/A–G active.
- [ ] 2. Enable Airplane Mode and explicitly disable Wi-Fi. Foreground-return, then relaunch offline.
- [ ] 3. Check About and Watchlist; do not interpret TVMaze fetch errors as entitlement failure.
- [ ] 4. Restore connectivity, foreground-return, and retry any failed action.

**Expected:** no destructive watchlist loss or false confirmed-lapse alert from a temporary verification problem. Cached verified entitlement should be honored when available. If StoreKit is unverified on cold launch, saved pause flags are preserved but new additions may be limited; record the exact state and messaging. Reconnection converges to valid Plus. A show-detail network failure is separate from StoreKit access. If the subscription actually expires while offline, rerun with a longer period before drawing conclusions.

#### SK-21 — Offline free user, offline expiration, and restore failure

- [ ] 1. Relaunch a genuinely free account offline; inspect saved shows and purchase options. Attempt Restore, reconnect, retry.
- [ ] 2. Separately, let a paid subscription expire while disconnected, then reconnect and foreground-return.

**Expected:** offline does not grant free users Plus. Purchase/restore failures are recoverable. After reconnect and a definitive inactive entitlement, extras pause without deletion. No claim that a cached offline state proves current server access; record when the app converges after reconnect.

#### SK-22 — Free slots, paused reactivation, and Undo

**Start:** the expired state from SK-13: A–C active, D–G paused, and H a new untracked show. Use only shows you are willing to remove.

- [ ] 1. Remove active A using its Watchlist star, then tap Undo on the removal toast. Confirm A remains active and the saved list is unchanged.
- [ ] 2. Remove A again and finish with OK or timeout. In the Search tab, find paused D and tap its empty star to reactivate it. Confirm D appears once as active, with B and C still active.
- [ ] 3. Attempt to add H. Confirm Plus opens, H stays untracked and there are still three active shows. Cancel the paywall.
- [ ] 4. Swipe-delete one active test show and tap Undo. Confirm it returns once and the active count stays at three.

**Expected:** Undo preserves one saved row; a committed active removal frees one slot. Reactivating a paused show updates its existing row without duplication. The free cap still applies. Exact competing additions/removal/Undo orders are engineering coverage, not a manual timing exercise.

#### SK-23 — Tips for free and paid users

- [ ] 1. As free, purchase Trailer, Pilot, and Hit Show separately. Dismiss each thank-you; buy the same tip again.
- [ ] 2. Cancel a tip. Use the Purchase API error (local setup step 6) or sandbox Allow Purchases & Renewals OFF to fail a tip; disable the error/turn the switch ON and retry successfully.
- [ ] 3. Relaunch and Restore Purchases. Repeat one tip as paid and one as complimentary.

**Expected:** each successful new tip transaction thanks the user once during its handling; purchases are repeatable consumables. Cancel/failure produces no thank-you. Tips never grant Plus, change pause flags, or consume watchlist slots. Restore does not recreate spent tips or retroactively unlock features. Relaunch must not cause a repeated thank-you loop; the app does not promise a persisted receipt/history screen for tips.

#### SK-24 — Permanent complimentary access

**Start:** a separate previously granted beta installation. Do not use it for SK-12–16.

- [ ] 1. Install the normal non-granting build over the existing beta installation.
- [ ] 2. Relaunch online/offline; check About and add beyond three shows.
- [ ] 3. If this installation also has a paid subscription, let that subscription expire or revoke it.
- [ ] 4. Retry after a normal foreground return. Optionally check a second device with the same iCloud/Keychain setup, allowing sync time.

**Expected:** recognized permanent complimentary access remains Unlimited independently of purchased entitlement. About identifies complimentary access when there is no active paid subscription. Forced Keychain-failure retention is tracked in the engineering record; these ordinary launches do not force that error. Cross-device discovery may depend on Keychain synchronization; it does not synchronize watchlists. A fresh normal installation with no existing grant must not receive a new complimentary entitlement.

#### SK-25 — Simulate Free Tier: state, restart, purchase, restore, tips

**Start:** actual paid/complimentary Plus with A–G, in Debug or verified TestFlight.

- [ ] 1. About → Diagnostics → Subscription Testing → enable Simulate Free Tier. Inspect the active notice and simulated capacity in About.
- [ ] 2. Confirm A–C active, extras paused, normal cap enforced, export includes all saves.
- [ ] 3. Restore Purchases and purchase a tip; simulation must remain on. For the cancel/failure branches, use the separate local Free state described in step 5, with simulation enabled. Cancel Apple’s sheet, then enable the Purchase API error (local setup step 6) and retry; neither outcome may end simulation. Disable the error afterward. Do not try to buy an already-active plan merely to force a failure.
- [ ] 4. Disable simulation; confirm all saves resume. Enable it again, then relaunch; session-only simulation ends and valid actual access resumes.
- [ ] 5. In a separate local run, delete local subscription transactions using setup step 5 and confirm Free access. Remove D and any extra disposable test shows if saved, completing removal, so A–C remain active and D is untracked. Then enable Simulate Free Tier, attempt D, and purchase Plus. Verified customer purchase success should end simulation and add D once. This run starts Free, so there is no need to buy a second already-active subscription.
- [ ] 6. Reset the local subscription transactions again, remove disposable D if it was saved, and follow Ask to Buy setup with A–C active and D untracked. Enable simulation while Free, attempt D, choose Ask, and approve in the transaction manager. Confirm simulation ends. Reset transactions, remove disposable D and re-establish A–C active/D untracked again. Repeat, but toggle simulation OFF then ON before approval: that earlier session’s completion must leave the new simulation ON. Turn it OFF afterward.

**Expected:** actual purchased/complimentary entitlement is preserved underneath simulation. Renewals, unrelated transactions, restore, and tips do not end the override. Restart ends it; genuine success from the current simulated purchase can end it. Use the separate Free local runs in steps 5–6 rather than trying to purchase an already-active plan; an automatic renewal does not count. Ordinary free users disabling simulation remain free.

#### SK-26 — Production boundary and user-facing presentation

On a real App Store installation when available, verify Diagnostics/Simulate Free Tier are absent and no fresh beta grant is created. Before release, inspect the archived Release configuration and record this as build verification rather than pretending TestFlight proves the App Store boundary.

Check free, paid, complimentary, loading, and unavailable-catalog screens in VoiceOver/large text. Verify price/period labels, error dismissal, paused state, and restore/purchase busy controls remain understandable.

#### About Plus status acceptance checks

- [ ] 1. In each prepared Free, paid, complimentary and simulated state, open About. Free shows **Up to 3 shows** and Unlock NextSeason Plus; paid shows **Unlimited** with the paid footer; complimentary-only access shows **Unlimited** with the permanent complimentary footer; simulation explicitly says **Up to 3 shows (simulated)**.
- [ ] 2. Use Restore Purchases in each reachable state. Confirm controls return to usable state and the final status matches actual access. If paid and complimentary access coexist, the paid footer takes priority.
- [ ] 3. Check these screens with large text and VoiceOver. The status/footer and Restore control must remain readable and reachable.

Loading may finish too quickly to observe; note it only if seen. Do not attempt to force **Unable to Verify Plus** through Airplane Mode. Controlled loading/uncertainty/error transitions are in the [engineering record](../Reviews/StoreKitEngineeringCoverage-2026-10-28.md).

### Additional device checks

#### SK-27 — Old notification destinations

Use a physical device with visible notification permission and disposable saved shows. This checks delivery/navigation, not production change detection.

- [ ] 1. With at least one active saved show, open About → Diagnostics → **Send Test Notification**. Record the selected show from the outcome text (Lupin if saved, otherwise the most recently added show). Close Diagnostics and go to the Home Screen before the roughly five-second delay ends.
- [ ] 2. Leave the delivered alert untapped. Remove that show and finish removal with OK/timeout, then tap the retained alert. Confirm Search details open without silently re-adding it. If the provider is unavailable, check for understandable feedback rather than a crash.
- [ ] 3. On a separate run, create an alert for an active show that will become paused. With Plus and at least four disposable saves, the selected target (Lupin if saved, otherwise the most recently added show) must be outside the three oldest. Use a disposable show set with that ordering; do not remove a valued Lupin just to change the target. Deliver the alert, enable Simulate Free Tier, confirm the target is paused, then tap the retained alert. Expect Watchlist without paused details.
- [ ] 4. For the closed-app version, first deliver a new alert while the later-saved target is active. Cancel sandbox renewal and wait for actual expiration as in SK-13; confirm the target is paused. Use a non-complimentary test installation, since complimentary access can reactivate shows during startup. Close the app and tap that retained alert; record the destination. Simulation ends at termination and cannot prepare this state. If no such test installation is available, record this equipment-dependent branch Not run.

**Expected:** active saved alerts open that show’s Watchlist details (reuse beta walkthrough 11); removed targets use Search without re-adding; paused targets remain protected. Restore simulation/settings afterward. Controlled provider changes, catch-up and held fetches are in the engineering record under the same SK-27 ID.

#### SK-29 — Notification permission integration

Reuse beta walkthrough 10’s actual-device settings-return result on this build. It covers disabling/enabling notifications, About status, the Watchlist banner and continued normal tracking. Do not repeat the same steps solely to fill another result row. Controlled processing of a known provider change while notifications are disabled is in the engineering record.

#### SK-30 — Sandbox storefront presentation

- [ ] 1. Record the current sandbox account country/region. In App Store Connect → Users and Access → Sandbox, select your test account, change **Country or Region**, and Save.
- [ ] 2. Sign out/in again with that Sandbox Apple Account on the test device, then force-quit/relaunch NextSeason. Reapply Ignore Complimentary Plus when needed.
- [ ] 3. Open the loaded catalog and Apple’s purchase sheet. Compare the newly supplied product, currency, period and price; cancel without purchasing.
- [ ] 4. Restore the original sandbox country/region and sign in again.

**Expected:** the app agrees with Apple’s sheet for the selected storefront. Do not force a particular currency where Apple’s chosen storefront legitimately uses the same one. No lifetime, promotional-offer or Family Sharing flow is implemented by the current local product configuration. Verification-failure requirements are retained separately in the engineering record. [Apple storefront controls](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/).

### Result sheet

For each applicable manual row, fill outcome, environment, build, and evidence. Do not repeat overlapping focused/SK checks. The engineering record owns 3C, 8A, SK-28, CV-06 and the moved controlled portions; none needs a Blocked checkbox in this manual result sheet. Use a separate copy of this document for each release candidate. Repeat rows as needed for monthly/annual, device, and environment.

| Case | Outcome | Environment / plan | Evidence / issue |
|---|---|---|---|
| Focused retained cases (3C/8A moved; record each attempted subcase) | | | |
| OC-11 Entitlement integration | | | |
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
| SK-18 Reachable Restore cases | | | |
| SK-19 Reinstall/second device | | | |
| SK-20 Paid offline/reconnect | | | |
| SK-21 Free offline/offline lapse | | | |
| SK-22 Slots/reactivation/Undo | | | |
| SK-23 Tips | | | |
| SK-24 Complimentary | | | |
| SK-25 Simulation | | | |
| SK-26 Production/accessibility | | | |
| SK-27 Device notification destinations | | | |
| SK-29 Permissions | | | |
| SK-30 Sandbox storefront | | | |

#### Failure report template

Case ID / build / device / environment / test-account alias:

Starting entitlement, simulation state, active/paused shows:

Exact steps and transaction/expiration times:

Expected result:

Actual result:

Screenshot/video or diagnostic export:

Does it reproduce after reconnect/relaunch? Does complimentary access affect it?

#### Completion and cleanup

Do not claim StoreKit is fully validated solely from local or simulated passes. Before release, have recorded real-device passes for catalog/purchase on both plans, cancellation versus expiry, restoration, revocation where available, offline/reconnect, and applicable grace/retry behavior. Keep the separate engineering evidence gaps and any presentation failures explicit. An unscheduled iOS background refresh is a coverage limitation, not a successful test.

Then turn Simulate Free Tier OFF and Ignore Complimentary Plus OFF. Complimentary Plus returns only if a stored grant exists; otherwise access follows StoreKit. Verify saved shows remain intact. Disable local purchase errors, Ask to Buy, interrupted purchases, and billing failures; restore the scheme's original StoreKit setting and the test device's original Media & Purchases account. Keep screenshots/logs and the completed result sheet. Do not clear purchase history on accounts used for ongoing lifecycle tests until their evidence is recorded.

This document does not itself alter repository or App Store Connect settings. It intentionally separates device-backup/watchlist migration from Restore Purchases and separates real StoreKit state from beta simulation.

---

### OC-11 — Entitlement ordering in real purchase/restore flows (item #1)

**Environment:** real-device sandbox/TestFlight, normal non-granting build, no complimentary entitlement, simulation off. Repeat relevant purchase branches for Monthly and Annual. Reuse the setup and retained SK lifecycle cases; do not repeat evidence already recorded there. Steps 3 and 5 reference separate local Xcode runs.

- [ ] 1. Cold launch while free, then purchase Plus as the app becomes usable. Briefly switch away/back around purchase completion. Confirm Unlimited, add beyond three, inspect saved active/paused rows, then relaunch.
- [ ] 2. Repeat with Restore Purchases on a valid paid account, switching away/back while restore is pending. Confirm access and saved rows converge correctly without transient false lapse alerts or a stuck busy state.
- [ ] 3. Reuse the local SK-08 Ask to Buy observations for delayed completion; record their local environment separately. Do not attempt Xcode approval controls on the TestFlight build.
- [ ] 4. With actual Plus and more than three saves, exercise a renewal and a genuine lapse/recovery during foreground transitions (SK-11–SK-17). Observe that real active access is not revoked by an older answer and genuine inactivity eventually pauses extras.
- [ ] 5. In the separate local Free runs described in SK-25 steps 5–6, complete a customer Plus purchase or pending approval from that simulation session. Check that active access is applied, the simulation ends and the purchase UI becomes usable. Restore/tips/renewals must not end simulation.

**Expected:** no late flip back to free after confirmed active access, no false pause event, no duplicate transaction handling and no permanently enabled simulation after the qualifying successful purchase. Current uncertainty preserves previously confirmed state; it is not automatically a lapse.

**Limits:** UI timing does not prove scans overlapped. Record actual observations and use [CV-06](../Reviews/StoreKitEngineeringCoverage-2026-10-28.md#controlled-verification-register) for controlled stale answers, cancellation, .unverified and stuck reads. A stalled **newest** read is a known limitation: dependent operations can wait until a later refresh commits or the app restarts. Foregrounding does not currently retry stalled initial resolution, and a stalled transaction handler queues later updates. Do not manufacture a “pass” by treating indefinite loading as normal; if a real stall occurs, capture diagnostics/time/account state and report it. Do not force arbitrary timeout-based entitlement changes.

### Controlled verification register

CV-06 and the other non-manual requirements are maintained in the [engineering coverage record](../Reviews/StoreKitEngineeringCoverage-2026-10-28.md#controlled-verification-register), outside this tester checklist. No coverage is passed or waived by moving it.

### Source and decision references

- [ ] [October 26 manual-coverage review dispositions](../Reviews/ManualTestCoverageReview-2026-10-26.md).

- [ ] [Entitlement ordering review](../Reviews/EntitlementCheckOrderingReview-2026-10-19.md), [expiration and restore feedback](../Reviews/ExpirationRecheckAndRestoreFeedback-2026-10-21.md), and [Ignore Complimentary Plus review](../Reviews/IgnoreComplimentaryPlus-2026-10-21.md).
- [ ] [Testing override behavior](FreeTierSimulation.md).
- [ ] [Apple Ask to Buy testing](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode): use local Xcode approval/decline controls for pending completion; do not assume those controls exist in TestFlight.

### StoreKit release coordination

- [ ] Follow [Permanent complimentary Plus for beta testers](Complimentary%20Plus%20Beta%20Grant.md): after the final granting beta has been distributed, remove the **NextSeason - Final Complimentary Beta** shared scheme, the **BetaComplimentary** project/target build configurations, and `Config/BetaComplimentary.xcconfig`. Preserve entitlement recognition/persistence and the build guards. These are separately assigned project cleanup actions, not edits performed by following this test document.
- [ ] Run `python3 Scripts/tests/test-complimentary-plus-build.py` before distribution and again after the approved cleanup; record actual results. Select the normal **NextSeason** scheme and create a new normal **Release** archive for App Store submission. Verify that exact archive/build is selected in App Store Connect; never select the previously uploaded granting beta. A passing TestFlight runtime check does not establish this submission boundary.

- [ ] Review the [engineering coverage record](../Reviews/StoreKitEngineeringCoverage-2026-10-28.md) for controlled notification events, catch-up, exact ordering, verification errors and other evidence that ordinary app taps cannot establish. Manual results alone do not close those requirements.
- [ ] Use [this StoreKit guide](#how-to-use-this-script) and its [result sheet](#result-sheet) to record the detailed coverage below.
- [ ] Verify monthly and annual purchasing, cancellation, failures, restore, and each of the three tip products with suitable sandbox accounts ([SK-01–SK-19](#pass-1--purchases-catalog-and-transaction-lifecycle), [SK-23](#sk-23--tips-for-free-and-paid-users)). Complimentary beta access must not mask entitlement failures. TestFlight purchasing does not establish production StoreKit correctness; complete applicable production configuration and launch checks separately.
- [ ] Verify Plus expiration with more than three stored shows ([SK-13–SK-17](#pass-2--losing-and-recovering-paid-access), [SK-22](#sk-22--free-slots-paused-reactivation-and-undo)): preserve all stored shows and their export, and check the specified free-tier behavior. Verify complimentary entitlement persistence using the intended grant and ordinary release configurations.
- [ ] Verify prices come from StoreKit ([SK-02](#sk-02--product-catalog-prices-disclosures-and-links)), product/period presentation matches App Store Connect, legal links work, and Family Sharing is off for both subscriptions.
- [ ] Trim the verbose purchase/paywall diagnostic breadcrumbs added October 23, 2026 (`paywall_*`, `purchase_*`, `storekit_purchase_success`, `transaction_update`), especially transaction IDs, unless still needed.
