# NextSeason: beta regression and release testing

This is the master test plan, not a record of tests already passed. Choose the section for your assignment:

- [Beta tester walkthrough](#beta-tester-walkthrough) — the main 30–45-minute walkthrough and follow-up normal use.
- [Assigned StoreKit testing](#assigned-storekit-testing) — detailed purchase, entitlement, and controlled-data cases; run only the assigned cases in the required environment.
- [Release coordinator checklist — Janine only](#release-coordinator-checklist--janine-only) — release coverage and checks beyond the walkthrough.

## Beta tester walkthrough

Thank you for helping test NextSeason before release! A **regression test** means checking that the app's existing features still work after the latest changes. You don't need technical knowledge: follow the steps below and tell me where the app behaves differently from the expected result.

Allow roughly 30–45 minutes for the main walkthrough, plus normal use over the next day or two. Mark each numbered test **Pass**, **Problem**, or **Skipped**. For skipped tests, include the reason. If something goes wrong, keep testing the other areas when possible.

## Before you start

1. Record your iPhone model, iOS version, and NextSeason version/build shown in TestFlight.
2. If you already have NextSeason, note or screenshot your Watchlist **before** updating. Install the latest requested TestFlight build over the existing app.
3. Start with an internet connection. Keep a note of any iPhone settings you change so you can restore them afterward.
4. Use two or three temporary test shows that you don't mind removing. Try one ongoing show, one ended show, and one with a long title. Live TV information changes, so don't expect a particular premiere date from this script.
5. **Do not delete the app or reset its data for this walkthrough.** Your Watchlist is stored locally. Clean-install testing is a separately assigned task.

Use the corresponding control if a button's wording differs slightly from this script. If you cannot find a feature, report that rather than guessing.

## 1. Update and launch

1. Open NextSeason after installing the update.
2. Check your previous Watchlist against your note or screenshot.
3. Switch between Search and Watchlist several times.
4. Open a show, go back, leave the app for the Home Screen, and return.

**Expected:** The app opens without crashing or becoming stuck. Your existing shows remain. Navigation works, and returning to the app leaves it usable. No unexpected recovery or reset screen appears.

## 2. Search for shows

1. Search for a familiar show by its full title.
2. Search for part of that title.
3. Try a broad search, such as `Star Trek`, and scroll through the results.
4. Try an older or less-popular show you know.
5. Try a title containing punctuation, and then try it without that punctuation.
6. Search for nonsense, such as `zzqxvnonexistentshow`.
7. Clear the search field and search again.
8. Change the search text quickly from one title to a different title.

**Expected:** Results are relevant and scroll normally. No-results searches give understandable feedback. Clearing or changing the search works. Once the latest search finishes, results belong to the latest query. Report missing known shows, confusing duplicates, or results that open the wrong show; not every alternate spelling is guaranteed to match.

## 3. Open show details

1. Open an ongoing show from Search.
2. Scroll to the bottom and back up.
3. Check its title, overview, and any displayed season or episode information.
4. Open an ended show and check its status.
5. Open a long-title show and check for clipped text or overlapping controls.
6. If a source/details link is shown, open it, then return to NextSeason.

**Expected:** Each result opens the correct show. Information is readable, scrolling and back navigation work, and missing dates are presented clearly. Source links open the intended show's page. An ended show should not misleadingly promise another season.

## 4. Add shows and check the Watchlist

1. Add a temporary test show using its star control.
2. Open Watchlist and find it.
3. Open its details from Watchlist.
4. Return to Search and find the same show again.
5. Try adding it again if the controls allow that action.
6. Add other temporary test shows within your available limit.
7. Scroll through the Watchlist, including past section headings.

**Expected:** Added shows appear once, their stars reflect their tracked state, and the state agrees between Search, details, and Watchlist. Section headings remain readable as rows scroll beneath them. Grouping agrees with the status/date information displayed for each show.

## 5. Search your Watchlist

1. Open the Watchlist search control.
2. Enter part of a tracked show's title.
3. Enter a title or nonsense that does not match your Watchlist.
4. Clear the field and close search.

**Expected:** Matching tracked shows appear. No matches are communicated clearly. Clearing or closing search restores the full Watchlist without removing any shows.

## 6. Remove and re-add a show

1. Remove a **temporary test show** by tapping its selected star.
2. Check that it disappears from Watchlist and is no longer starred in Search/details.
3. Add it again.
4. In Watchlist, swipe that temporary show's row and use Delete.
5. Check its state again, then re-add it if desired.

**Expected:** Both removal methods work. Other shows are unaffected. Re-adding creates one entry, with consistent star state throughout the app.

## 7. Keep data between sessions

1. Screenshot or note the current Watchlist.
2. Leave NextSeason and use another app briefly, then return.
3. Close NextSeason from the app switcher and reopen it.
4. If convenient, restart your iPhone and open NextSeason again.

**Expected:** The Watchlist remains intact after each step. Ordinary closing and reopening does not trigger a recovery screen.

## 8. Export your Watchlist

1. Find the Watchlist export action in the app's menu.
2. Start an export, then cancel the share sheet.
3. Confirm that your Watchlist is unchanged.
4. Export again and save the CSV to Files.
5. Open it in Numbers, Excel, or another spreadsheet app, if available.
6. Compare the exported show names and count with your full Watchlist. If possible, also export while a Watchlist search is active.

**Expected:** The share sheet works and canceling is harmless. The CSV contains the **complete stored Watchlist**, even when the on-screen list is filtered. It includes show names and TVMaze IDs, with TVDB IDs where available. Titles containing punctuation remain in their correct cells. Export does not require Plus. If you cannot open the CSV, report that part as skipped.

## 9. Free limit and Plus — follow the applicable branch

### If you have complimentary beta Plus or an active subscription

1. Record which access state the app shows.
2. Try tracking a fourth show.
3. Close and reopen the app and confirm your access and shows remain.
4. Open About and inspect any Plus/access information available there.

**Expected:** Plus allows more than three tracked shows. Complimentary access remains recognized. **Skip the free-limit branch; do not remove your complimentary access to test it.**

### If you are using the free tier

1. With exactly three tracked shows, try adding a fourth.
2. Check the Plus screen, including monthly and annual choices, prices, and legal links.
3. Dismiss it without buying and check your Watchlist.
4. Remove one temporary show, then add a different show to return to three.
5. Open Plus from About using the available upgrade control.

**Expected:** Adding a fourth show opens Plus without adding the show. Dismissing leaves the original three intact. After removing one, another can be added. Both routes to Plus work. Prices and subscription periods are readable; currency may vary by region.

### Optional purchase tests — only if specifically assigned

This is a brief purchase smoke test. Assigned purchase testers should also use [Assigned StoreKit testing](#assigned-storekit-testing), which provides setup, detailed cases, and a result sheet. Completing this smoke test does not complete StoreKit coverage.

Test the assigned subscription or tip through **the TestFlight build**. Cancel the purchase sheet first and verify that cancellation leaves the app usable. Then complete the assigned test purchase. Record the product and outcome. Use Restore Purchases if assigned.

**Expected:** A completed Plus purchase unlocks tracking beyond three shows. A canceled purchase does not unlock Plus or remove data. Tips are optional and do not unlock Plus. Restoration recognizes eligible previous purchases or gives understandable feedback when none exist.

If the purchase sheet does not clearly identify a test/sandbox purchase, stop and ask Janine before proceeding. Do not buy through a public App Store listing for this test. Complimentary access can mask purchase/restore failures, so report it and leave those checks to an assigned purchase tester.

## 10. Notifications allowed and disabled

1. In iPhone Settings, check NextSeason's notification permission. Record whether it was already allowed or denied.
2. If NextSeason presents its permission request during normal use, record when it appears and your choice. Do not reinstall just to trigger it.
3. With notifications allowed, open NextSeason and confirm Search and Watchlist work.
4. Turn notifications off in iPhone Settings, return to NextSeason, and repeat a search and Watchlist visit.
5. Restore your preferred notification setting.

**Expected:** Core features work with either permission setting. Denying permission does not cause a crash or repeated system permission requests. No notification banner is expected while permission is off.

During the next day or two, if a real show update notification arrives, screenshot it, check that the text is understandable, and tap it. Record where the app opens and whether it shows the relevant information. Report duplicate notifications or a notification for a removed show.

**No notification arriving is not automatically a failure:** there may be no qualifying show change. Mark actual delivery/tap testing as skipped unless an update occurs or Janine supplies a controlled test.

## 11. Background App Refresh

1. In iPhone Settings, note NextSeason's Background App Refresh setting.
2. If available, turn it off for NextSeason.
3. Open the app, search, and visit your Watchlist.
4. Restore your original setting.
5. With refresh enabled, use the app normally over the next day or two. Leave it in the background normally rather than repeatedly closing it from the app switcher.
6. Note any displayed update times and changes in show information.

**Expected:** Disabling background refresh does not prevent normal foreground use or erase data. With it enabled, report what you observe; do not expect an update at an exact time. iOS controls when background work runs, and this walkthrough alone cannot prove that it ran.

## 12. Offline and network recovery

1. Load your Watchlist while online.
2. Turn on Airplane Mode and ensure Wi-Fi is also off.
3. Open Watchlist and a previously viewed show.
4. Try searching for a different show.
5. Restore connectivity and retry the search. Revisit Watchlist.
6. If you naturally encounter a weak connection later, note any long waits or errors; you do not need to find a poor-signal location.

**Expected:** Stored shows remain intact. Cached information may be available; uncached information may not be. Network failures should produce understandable feedback rather than a crash or an indefinite unusable screen. After connectivity returns, the app can recover and search again.

## 13. Readability and appearance

1. Check Search, show details, Watchlist, and About in your normal appearance.
2. Switch the iPhone between Light and Dark appearance and revisit those screens.
3. In Accessibility settings, increase text size to the largest accessibility size. Check those screens and Plus, if accessible.
4. Try scrolling, searching, tapping stars, and dismissing sheets with large text.
5. If comfortable, briefly enable Increase Contrast, Button Shapes, Reduce Transparency, and Reduce Motion, checking the main screens after changes.
6. Restore your preferred settings.

**Expected:** Text and controls remain readable and reachable. Important text does not overlap or disappear. Watchlist section headers stay readable. States such as tracked/untracked can be distinguished without relying only on color. Report confusing wording or truncated English text, including on phones using another system language.

## 14. VoiceOver — optional if comfortable using it

1. Enable VoiceOver using your usual method. If unfamiliar with it, skip this test.
2. Navigate Search, read a result, and open its details.
3. Find the star control and check whether its label/action describes adding or removing the show correctly.
4. Navigate Watchlist, its search control, and the available row actions.
5. Open and dismiss a menu or sheet, then turn VoiceOver off if desired.

**Expected:** Controls have meaningful labels and their states are announced correctly. Navigation order makes sense. You can search, track a show, and return without becoming trapped. Report the exact screen/control for any unclear announcement.

## 15. About and links

1. Open About and check the displayed app information.
2. Open Privacy Policy and Support, then return to the app.
3. Open Write a Review and any available purchase/legal links. Do not submit a review for this test.
4. If Support opens an email draft, check its destination and cancel it without sending.

**Expected:** Website links open the intended pages. Support email, when offered, is addressed to `support@getnextseason.com`. Return navigation works. If an App Store/review link cannot resolve before launch, record the destination and error so Janine can distinguish listing availability from a broken link.

## 16. Optional time-zone check

1. Screenshot a show with a displayed upcoming date.
2. Note your current iPhone time-zone setting, then temporarily choose a substantially different time zone. Leave the actual date/time correct.
3. Reopen the app and inspect that show and its Watchlist grouping.
4. Restore your original time-zone setting.

**Expected:** Dates remain readable and the app stays usable. Capture before/after differences for Janine to review; whether a date should change depends on how the source represents it. Do not assume every date difference is a bug.

## Send your results

Please send your completed test numbers, including passes and skips, so I know what was covered. Use TestFlight feedback or your usual feedback channel with me.

For each problem, include:

- Test number and a short description.
- iPhone model, iOS version, and NextSeason version/build.
- Whether you have free, subscription, or complimentary beta access.
- Exact steps, including the show title/search text where relevant.
- What you expected and what happened instead.
- Screenshot or screen recording if possible.
- Whether it happens again, and approximately when it occurred.

If the app crashes, loses shows, becomes stuck, or unexpectedly asks to reset local data, report that promptly. Do not reset or reinstall before reporting it.

Example: **Test 5 — Problem.** Searching my Watchlist for “Trek” showed no matches even though Star Trek: Enterprise is tracked. Clearing the field brought it back. Happened twice. [Device/iOS/build; screenshot.]


---

## Assigned StoreKit testing

For assigned purchase testers and developer-assisted verification. Ordinary beta testers can complete the walkthrough above without running these cases. The setup, safeguards, and result sheet below apply to this section.

Prepared October 11, 2026, against the current working copy, including the final admission check, soft-change confirmation, and catch-up/Undo fixes. Updated to include the About unverified-entitlement presentation fix. This document is a test plan, not a record of tests already passed.

### How to use this script

Run the numbered cases in order. Each case gives its starting state, actions, and expected result. Record **Pass / Fail / Blocked / Not applicable**, the build, and any evidence. “Blocked” means you could not establish the required state; it does not mean the feature passed.

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

Check About before testing. If it says permanent complimentary Plus, that device is unsuitable for real paid-access-loss tests. Use a separate clean simulator/device without that entitlement. Deleting the app or changing the Sandbox Apple Account does not reliably remove the app's complimentary access: it is also stored in synchronizable Keychain. Do not clear a tester's genuine complimentary grant just to obtain a free state.

Turn **Simulate Free Tier OFF** for every real StoreKit test. It overrides effective access and intentionally survives restore scans within the session.

Remove UI-testing/profile launch arguments. UI tests use stubs and are not a manual StoreKit session.

#### Local Xcode setup

In Xcode, choose the normal NextSeason scheme. Open **Product → Scheme → Edit Scheme → Run → Options**, select the existing **NextSeason.storekit** configuration, and run the app. While running, open **Debug → StoreKit → Manage Transactions**. Reset local test transactions when a case calls for fresh purchase history. Use the configuration editor's renewal-rate controls; use a slower rate for offline tests so the paid period does not end during the test. These local purchases do not validate App Store Connect configuration. [Apple setup guidance](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode), [local testing guidance](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-in-xcode).

Record and restore any temporary scheme/configuration changes afterward. Keep local tests separate from sandbox transactions.

#### Real-device sandbox and TestFlight setup

Create dedicated Sandbox Apple Accounts in App Store Connect → Users and Access → Sandbox. Use accounts with no prior purchase history for fresh-state cases. For an Xcode device build, set the scheme's StoreKit configuration to **None** and use the sandbox account controls on the device.

TestFlight uses sandbox purchases. For controllable billing and renewal scenarios, Apple directs testers to sign out of the production account under **Media & Purchases**, then sign in to the Sandbox Apple Account under Developer settings. Use a dedicated test device where practical; record the original account so you can restore it afterward. Default TestFlight renewals are daily, irrespective of monthly/annual duration; custom sandbox-account settings provide other rates. Do not assume a monthly test lasts a production month. [Apple TestFlight guidance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/).

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
2. Observe the Plus sheet closing and About reporting Unlimited.
3. Add D–G; switch tabs and reopen a saved detail.
4. Relaunch and attempt another addition.

**Expected:** verified Monthly unlocks access without requiring Restore Purchases. Unlimited survives relaunch. No duplicates, unintended paused rows, or repeated purchase prompts. The blocked add is not assumed to happen automatically: if D was not added, tap its star again after purchase.

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

**Environment:** local Xcode; enable Ask to Buy in the configuration editor.

1. As a free user, attempt Monthly. Leave the transaction Pending Approval in the transaction manager.
2. Verify no Plus access yet; the app is navigable after the purchase call returns pending.
3. Approve the transaction in the manager while the app runs. Confirm Unlimited and adding D.
4. Reset the fixture. Repeat with Annual, but decline the pending transaction. Confirm free access remains.
5. Reset again. Create a pending purchase, close the app, approve it, then relaunch.

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

**Expected:** a foreground entitlement reread detects the lapse and applies the same three-show policy before ordinary watchlist refresh. The implementation does not promise a timer-driven UI transition at the exact second of expiration while continuously foregrounded. Record that timing rather than expecting it. A background run must reconcile before processing shows. If iOS never schedules a background run, mark that portion Blocked, not Pass.

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

**Expected:** valid access is recovered; restore does not purchase or duplicate shows. No-purchase/expired accounts remain free; no false “Plus restored” claim. Failure gets recoverable feedback and no stuck busy state. Repeating restore is harmless. Automatic entitlement detection may restore access before you tap Restore; record that as automatic detection, not proof that the button changed access.

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

**Expected:** deferred star removal retains its slot during Undo; a real committed removal frees it. Reactivating D updates its saved row rather than duplicating it. No fourth active row should persist; a blocked addition opens Plus. Record which show becomes active/paused if immediate Undo and an already-completed addition compete. Human taps cannot guarantee the precise suspension ordering; SK-28 provides deterministic coverage.

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

Then disable local purchase errors, Ask to Buy, interrupted purchases, billing failures, and simulation; restore the scheme's original StoreKit setting and the test device's original Media & Purchases account. Keep screenshots/logs and the completed result sheet. Do not clear purchase history on accounts used for ongoing lifecycle tests until their evidence is recorded.

This script does not alter the repository or App Store Connect settings. It intentionally separates device-backup/watchlist migration from Restore Purchases and separates real StoreKit state from beta simulation.

---

## Release coordinator checklist — Janine only

The walkthrough provides broad user-facing regression coverage. Completing it does not, by itself, complete every engineering or production check in the roadmap.

- Assign coverage across iOS 18, 26, and 27 and different screen sizes, including both system-design generations. Testers use their existing devices; they should not upgrade/downgrade iOS for this task.
- Track results against a specific final version/build. After fixes, repeat affected tests and connected flows; broader changes may require another full pass.
- Assign a clean install on a spare device or controlled test environment, including empty Watchlist, initial launch, and first-run permission allow/deny paths. Separately verify upgrade from earlier TestFlight builds with existing data. Do not risk a tester's only Watchlist.
- Use controlled fixtures/test tooling ([SK-27–SK-30](#controlled-data-checks--complete-with-developer-assistance)) to verify qualifying notification events, long titles, duplicate suppression, removed shows, tap behavior, and background refresh. Natural beta use is supplementary evidence.
- Use [Assigned StoreKit testing](#assigned-storekit-testing) and its [result sheet](#result-sheet) to record the detailed coverage below.
- Verify monthly and annual purchasing, cancellation, failures, restore, and each of the three tip products with suitable sandbox accounts ([SK-01–SK-19](#pass-1--purchases-catalog-and-transaction-lifecycle), [SK-23](#sk-23--tips-for-free-and-paid-users)). Complimentary beta access must not mask entitlement failures. TestFlight purchasing does not establish production StoreKit correctness; complete applicable production configuration and launch checks separately.
- Verify Plus expiration with more than three stored shows ([SK-13–SK-17](#pass-2--losing-and-recovering-paid-access), [SK-22](#sk-22--free-slots-paused-reactivation-and-undo)): preserve all stored shows and their export, and check the specified free-tier behavior. Verify complimentary entitlement persistence using the intended grant and ordinary release configurations.
- Verify prices come from StoreKit ([SK-02](#sk-02--product-catalog-prices-disclosures-and-links)), product/period presentation matches App Store Connect, legal links work, and Family Sharing is off for both subscriptions.
- Test persistence recovery and crash-loop prevention using controlled failure injection, including diagnostics export, readable-Watchlist export, reset consequences, and successful relaunch. Do not ask ordinary testers to corrupt storage or trigger resets.
- Run unit/UI tests and the final Instruments pass for leaks, memory growth, and performance. Perform SwiftData migration checks whenever a schema change is included, using representative earlier stores.
- Review date/time-zone differences against the intended date model. Verify all user-facing error and recovery states and release visibility of diagnostics.
- Check the final build against screenshots, description, supported OS/device settings, and current feature set. This script intentionally contains no removed theme-switcher test or CSV import test.

Prepared from the App Store Readiness Roadmap uploaded October 7, 2026, and the audited README. Exact UI wording and build-specific test hooks should be checked against the final candidate before distributing.
