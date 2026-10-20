# NextSeason: beta regression and release testing — checklist copy

Checklist copy of `NextSeason-Beta-Regression-Test.md`, synchronized October 19, 2026. Check a step after performing it and recording its result. A checked box means covered, not necessarily passed. Keep skipped or blocked steps unchecked and record why. Use a fresh copy for each build or release candidate.

This is the master test plan, not a record of tests already passed. Choose the section for your assignment:

- [Beta tester walkthrough](#beta-tester-walkthrough) — the main 30–45-minute walkthrough and follow-up normal use.
- [October fixes — Janine's manual pass](#october-fixes--janines-manual-pass) — the consolidated October checks, device routing matrix, results sheet and controlled-verification register.
- [Assigned StoreKit testing](#assigned-storekit-testing) — detailed purchase, entitlement, and controlled-data cases; run only the assigned cases in the required environment.
- [Release coordinator checklist — Janine only](#release-coordinator-checklist--janine-only) — release coverage and checks beyond the walkthrough.

**Updated October 19, 2026.** Janine: use walkthrough 1–16 for broad coverage, the October pass for the recent fixes, and SK-01–SK-30 for the applicable purchase/lapse branches. Follow the October run order and record results against one candidate build. This is a plan; no case is pre-marked passed. A printable/checkable copy is [here](NextSeason-Beta-Regression-Checklist.md).

## Beta tester walkthrough

Thank you for helping test NextSeason before release! A **regression test** means checking that the app's existing features still work after the latest changes. You don't need technical knowledge: follow the steps below and tell me where the app behaves differently from the expected result.

Allow roughly 30–45 minutes for the main walkthrough, plus normal use over the next day or two. Mark each numbered test **Pass**, **Problem**, or **Skipped**. For skipped tests, include the reason. If something goes wrong, keep testing the other areas when possible.

## Before you start

- [ ] 1. Record your iPhone model, iOS version, and NextSeason version/build shown in TestFlight.
- [ ] 2. If you already have NextSeason, note or screenshot your Watchlist **before** updating. Install the latest requested TestFlight build over the existing app.
- [ ] 3. Start with an internet connection. Keep a note of any iPhone settings you change so you can restore them afterward.
- [ ] 4. Use two or three temporary test shows that you don't mind removing. Try one ongoing show, one ended show, and one with a long title. Live TV information changes, so don't expect a particular premiere date from this script.
- [ ] 5. **Do not delete the app or reset its data for this walkthrough.** Your Watchlist is stored locally. Clean-install testing is a separately assigned task.

Use the corresponding control if a button's wording differs slightly from this script. If you cannot find a feature, report that rather than guessing.

## 1. Update and launch

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Open NextSeason after installing the update.
- [ ] 2. Check your previous Watchlist against your note or screenshot.
- [ ] 3. Switch between Search and Watchlist several times.
- [ ] 4. Open a show, go back, leave the app for the Home Screen, and return.

**Expected:** The app opens without crashing or becoming stuck. Your existing shows remain. Navigation works, and returning to the app leaves it usable. No unexpected recovery or reset screen appears.

## 2. Search for shows

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Search for a familiar show by its full title.
- [ ] 2. Search for part of that title.
- [ ] 3. Try a broad search, such as `Star Trek`, and scroll through the results. Use Load More if it appears; live providers may return different counts.
- [ ] 4. Try an older or less-popular show you know.
- [ ] 5. Try a title containing punctuation, and then try it without that punctuation.
- [ ] 6. Search for nonsense, such as `zzqxvnonexistentshow`.
- [ ] 7. Clear the search field and search again.
- [ ] 8. Change the search text quickly from one title to a different title.

**Expected:** Results are relevant and scroll normally. No-results searches give understandable feedback. Clearing or changing the search works. Once the latest search finishes, results belong to the latest query. Report missing known shows, confusing duplicates, or results that open the wrong show; not every alternate spelling is guaranteed to match.

## 3. Open show details

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Open an ongoing show from Search.
- [ ] 2. Scroll to the bottom and back up.
- [ ] 3. Check its title, overview, and any displayed season or episode information.
- [ ] 4. Open an ended show and check its status.
- [ ] 5. Open a long-title show and check for clipped text or overlapping controls.
- [ ] 6. If a source/details link is shown, open it, then return to NextSeason.

**Expected:** Each result opens the correct show. Information is readable, scrolling and back navigation work, and missing dates are presented clearly. Source links open the intended show's page. An ended show should not misleadingly promise another season.

## 4. Add shows and check the Watchlist

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Add a temporary test show using its star control.
- [ ] 2. Open Watchlist and find it.
- [ ] 3. Open its details from Watchlist.
- [ ] 4. Return to Search and find the same show again.
- [ ] 5. Try adding it again if the controls allow that action.
- [ ] 6. Add other temporary test shows within your available limit.
- [ ] 7. Scroll through the Watchlist, including past section headings.

**Expected:** Added shows appear once, their stars reflect their tracked state, and the state agrees between Search, details, and Watchlist. Section headings remain readable as rows scroll beneath them. Grouping agrees with the status/date information displayed for each show.

## 5. Search your Watchlist

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Open the Watchlist search control.
- [ ] 2. Enter part of a tracked show's title.
- [ ] 3. Enter a title or nonsense that does not match your Watchlist.
- [ ] 4. Clear the field and close search.

**Expected:** Matching tracked shows appear. No matches are communicated clearly. Clearing or closing search restores the full Watchlist without removing any shows.

## 6. Remove, Undo and re-add a show

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Un-star a **temporary test show**. While its Undo toast is visible, tap Undo; check its star and saved row.
- [ ] 2. Repeat, this time tap OK (or let the toast expire), then check Watchlist and Search/details. Re-add the show.
- [ ] 3. Swipe-delete it from Watchlist. The row disappears immediately; tap Undo and confirm it returns once.
- [ ] 4. Repeat swipe-delete, tap OK or let the toast expire, then re-add if desired.

**Expected:** star removal is deferred until OK/timeout, so the saved row can remain visible in its pending state. Swipe-delete persists immediately; Undo restores it. After committed removal the show is unstarred/absent; after Undo it is saved once. Other shows are unaffected. Normal Undo lasts about five seconds, or twenty with VoiceOver. Janine's extended checks are OC-03–OC-05.

## 7. Keep data between sessions

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Screenshot or note the current Watchlist.
- [ ] 2. Leave NextSeason and use another app briefly, then return.
- [ ] 3. Close NextSeason from the app switcher and reopen it.
- [ ] 4. If convenient, restart your iPhone and open NextSeason again.

**Expected:** The Watchlist remains intact after each step. Ordinary closing and reopening does not trigger a recovery screen.

## 8. Export your Watchlist

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Find the Watchlist export action in the app's menu.
- [ ] 2. Start an export, then cancel the share sheet.
- [ ] 3. Confirm that your Watchlist is unchanged.
- [ ] 4. Export again and save the CSV to Files.
- [ ] 5. Open it in Numbers, Excel, or another spreadsheet app, if available.
- [ ] 6. Compare the exported show names and count with your full Watchlist. If possible, also export while a Watchlist search is active.

**Expected:** The share sheet works and canceling is harmless. The CSV contains the **complete stored Watchlist**, even when the on-screen list is filtered. It includes show names and TVMaze IDs, with TVDB IDs where available. Titles containing punctuation remain in their correct cells. Export does not require Plus. If you cannot open the CSV, report that part as skipped.

## 9. Free limit and Plus — follow the applicable branch

- [ ] Case performed; outcome, environment and evidence recorded.

### If you have complimentary beta Plus or an active subscription

- [ ] 1. Record which access state the app shows.
- [ ] 2. Try tracking a fourth show.
- [ ] 3. Close and reopen the app and confirm your access and shows remain.
- [ ] 4. Open About and inspect any Plus/access information available there.

**Expected:** Plus allows more than three tracked shows. Complimentary access remains recognized. **Skip the free-limit branch; do not remove your complimentary access to test it.**

### If you are using the free tier

- [ ] 1. With exactly three tracked shows, try adding a fourth.
- [ ] 2. Check the Plus screen, including monthly and annual choices, prices, and legal links.
- [ ] 3. Dismiss it without buying and check your Watchlist.
- [ ] 4. Remove one temporary show, then add a different show to return to three.
- [ ] 5. Open Plus from About using the available upgrade control.

**Expected:** Adding a fourth show opens Plus without adding the show. Dismissing leaves the original three intact. After removing one, another can be added. Both routes to Plus work. Prices and subscription periods are readable; currency may vary by region.

### Optional purchase tests — only if specifically assigned

This is a brief purchase smoke test. Assigned purchase testers should also use [Assigned StoreKit testing](#assigned-storekit-testing), which provides setup, detailed cases, and a result sheet. Completing this smoke test does not complete StoreKit coverage.

Test the assigned subscription or tip through **the TestFlight build**. Cancel the purchase sheet first and verify that cancellation leaves the app usable. Then complete the assigned test purchase. Record the product and outcome. Use Restore Purchases if assigned.

**Expected:** A completed Plus purchase unlocks tracking beyond three shows. A canceled purchase does not unlock Plus or remove data. Tips are optional and do not unlock Plus. Restoration recognizes eligible previous purchases or gives understandable feedback when none exist.

If the purchase sheet does not clearly identify a test/sandbox purchase, stop and ask Janine before proceeding. Do not buy through a public App Store listing for this test. Complimentary access can mask purchase/restore failures, so report it and leave those checks to an assigned purchase tester.

## 10. Notifications allowed and disabled

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. In iPhone Settings, check NextSeason's notification permission. Record whether it was already allowed or denied.
- [ ] 2. If NextSeason presents its permission request during normal use, record when it appears and your choice. Do not reinstall just to trigger it.
- [ ] 3. With notifications allowed, open NextSeason and confirm Search and Watchlist work.
- [ ] 4. Turn notifications off in iPhone Settings, return to NextSeason, and repeat a search and Watchlist visit.
- [ ] 5. Restore your preferred notification setting.

**Expected:** Core features work with either permission setting. Denying permission does not cause a crash or repeated system permission requests. No notification banner is expected while permission is off.

During the next day or two, if a real show update notification arrives, screenshot it, check that the text is understandable, and tap it. Record where the app opens and whether it shows the relevant information. Report duplicate notifications or a notification for a removed show.

**No notification arriving is not automatically a failure:** there may be no qualifying show change. Mark actual delivery/tap testing as skipped unless an update occurs or Janine supplies a controlled test.

## 11. Background App Refresh

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. In iPhone Settings, note NextSeason's Background App Refresh setting.
- [ ] 2. If available, turn it off for NextSeason.
- [ ] 3. Open the app, search, and visit your Watchlist.
- [ ] 4. Restore your original setting.
- [ ] 5. With refresh enabled, use the app normally over the next day or two. Leave it in the background normally rather than repeatedly closing it from the app switcher.
- [ ] 6. Note any displayed update times and changes in show information.

**Expected:** Disabling background refresh does not prevent normal foreground use or erase data. With it enabled, report what you observe; do not expect an update at an exact time. iOS controls when background work runs, and this walkthrough alone cannot prove that it ran.

## 12. Offline and network recovery

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Load your Watchlist while online.
- [ ] 2. Turn on Airplane Mode and ensure Wi-Fi is also off.
- [ ] 3. Open Watchlist and a previously viewed show.
- [ ] 4. Try searching for a different show.
- [ ] 5. Restore connectivity and retry the search. Revisit Watchlist.
- [ ] 6. If you naturally encounter a weak connection later, note any long waits or errors; you do not need to find a poor-signal location.

**Expected:** Stored shows remain intact. Cached information may be available; uncached information may not be. Network failures should produce understandable feedback rather than a crash or an indefinite unusable screen. After connectivity returns, the app can recover and search again.

## 13. Readability and appearance

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Check Search, show details, Watchlist, and About in your normal appearance.
- [ ] 2. Switch the iPhone between Light and Dark appearance and revisit those screens.
- [ ] 3. In Accessibility settings, increase text size to the largest accessibility size. Check those screens and Plus, if accessible.
- [ ] 4. Try scrolling, searching, tapping stars, and dismissing sheets with large text.
- [ ] 5. If comfortable, briefly enable Increase Contrast, Button Shapes, Reduce Transparency, and Reduce Motion, checking the main screens after changes.
- [ ] 6. Restore your preferred settings.

**Expected:** Text and controls remain readable and reachable. Important text does not overlap or disappear. Watchlist section headers stay readable. States such as tracked/untracked can be distinguished without relying only on color. Report confusing wording or truncated English text, including on phones using another system language.

## 14. VoiceOver — optional if comfortable using it

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Enable VoiceOver using your usual method. If unfamiliar with it, skip this test.
- [ ] 2. Navigate Search, read a result, and open its details.
- [ ] 3. Find the star control and check whether its label/action describes adding or removing the show correctly.
- [ ] 4. Navigate Watchlist, its search control, and the available row actions.
- [ ] 5. Open and dismiss a menu or sheet, then turn VoiceOver off if desired.

**Expected:** Controls have meaningful labels and their states are announced correctly. Navigation order makes sense. You can search, track a show, and return without becoming trapped. Report the exact screen/control for any unclear announcement.

## 15. About and links

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Open About and check the displayed app information.
- [ ] 2. Open Privacy Policy and Support, then return to the app.
- [ ] 3. Open Write a Review and any available purchase/legal links. Do not submit a review for this test.
- [ ] 4. If Support opens an email draft, check its destination and cancel it without sending.

**Expected:** Website links open the intended pages. Support email, when offered, is addressed to `support@getnextseason.com`. Return navigation works. If an App Store/review link cannot resolve before launch, record the destination and error so Janine can distinguish listing availability from a broken link.

## 16. Time-zone/date check (when a dated show is available)

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Screenshot a show with a displayed upcoming date.
- [ ] 2. Note your current iPhone time-zone setting, then temporarily choose a substantially different time zone. Leave the actual date/time correct.
- [ ] 3. Reopen the app and inspect that show and its Watchlist grouping.
- [ ] 4. Restore your original time-zone setting.

**Expected:** a premiere date is a provider calendar day and must remain the same day after changing time zone; localized formatting may change. Actual instants such as Date Added/Updated can display differently. Status calculations use UTC days. Keep the device clock correct; restore the original time zone. Record the case skipped if no dated show is available. Janine's exact cross-surface checks are OC-10.

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

Originally prepared October 11, 2026; updated October 19 to integrate the reviewed notification, Undo, date and access behavior. OC-11 adds real-device entitlement-ordering smoke checks and CV-06 identifies its deterministic verification. This document is a test plan, not a record of tests already passed.

### How to use this script

Run the numbered cases in order. Each case gives its starting state, actions, and expected result. Record **Pass / Fail / Blocked / Not applicable**, the build, and any evidence. “Blocked” means you could not establish the required state; it does not mean the feature passed.

Use three passes:

- [ ] 1. **Local Xcode:** repeatable purchase, pending, error, refund, and expiration scenarios.
- [ ] 2. **Real-device sandbox/TestFlight:** actual product configuration, entitlement persistence, offline behavior, restore, and billing states.
- [ ] 3. **Complimentary and simulation:** the special beta-access rules, tested separately from paid access.

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

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** no subscription, no complimentary access, simulation off, empty watchlist.

- [ ] 1. Open About. Confirm the settled capacity is up to three shows and Unlock NextSeason Plus is available.
- [ ] 2. Add A, B, C from Search. Attempt D from Search.
- [ ] 3. Dismiss the Plus sheet. Open D's detail and attempt to track it there.
- [ ] 4. Open the Plus sheet directly through About, then dismiss it.

**Expected:** both fourth-add attempts show the same Plus options and do not save D. Three shows remain active. Dismissing the sheet makes no purchase and leaves navigation usable. Initial “Checking…” must settle; no indefinite loading.

#### SK-02 — Product catalog, prices, disclosures, and links

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** SK-01 state; online. Run locally, then again in TestFlight.

- [ ] 1. Inspect Monthly and Annual, their period labels, currency, and price.
- [ ] 2. Open each Apple purchase sheet and compare its product/period/price with the app; cancel both.
- [ ] 3. Open Terms of Use and Privacy Policy, then return.
- [ ] 4. Inspect all three tip options in About.

**Expected:** products match their identifiers and App Store Connect configuration. No lifetime option appears. Subscription disclosure and links are readable; links load the intended pages. Tip copy says tips do not unlock features. No stale error or duplicate sheet appears on return.

#### SK-03 — Catalog failure and retry

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** fresh launch without a previously loaded catalog. Local error simulation, or sandbox device offline before launch.

- [ ] 1. Open About and the Plus sheet. If necessary use local StoreKit product-loading error controls; turning off internet will not reliably fail local StoreKit.
- [ ] 2. Observe loading and eventual failure.
- [ ] 3. Restore normal settings/connectivity. Tap Try Again.

**Expected:** unavailable products are not replaced with invented live prices or enabled purchase buttons. A recoverable unavailable message appears; retries restore the catalog. Existing paid access and saved shows do not disappear because product loading failed. Dismiss remains usable when no purchase is in flight. Record a blocked result if the environment cannot induce failure.

#### SK-04 — Monthly purchase

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** free account, A–C active, no prior subscription.

- [ ] 1. Attempt D, then purchase Monthly and approve Apple's confirmation.
- [ ] 2. Observe the Plus sheet closing and About reporting Unlimited.
- [ ] 3. Add D–G; switch tabs and reopen a saved detail.
- [ ] 4. Relaunch and attempt another addition.

**Expected:** verified Monthly unlocks access without requiring Restore Purchases. Unlimited survives relaunch. No duplicates, unintended paused rows, or repeated purchase prompts. The blocked add is not assumed to happen automatically: if D was not added, tap its star again after purchase.

#### SK-05 — Annual purchase

- [ ] Case performed; outcome, environment and evidence recorded.

Reset purchase history using the appropriate environment; establish a genuinely free account. Repeat SK-04 with Annual. Confirm the payment sheet uses Annual and its yearly price. Keep one paid fixture for the later lifecycle cases.

#### SK-06 — Cancel the purchase sheet

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** free, A–C active.

- [ ] 1. Start a Monthly purchase and cancel Apple's purchase sheet.
- [ ] 2. Repeat for Annual and a tip.
- [ ] 3. Dismiss the app's Plus sheet and navigate normally.

**Expected:** no Plus grant, no tip thank-you, no scary failure alert for ordinary cancellation, and no stuck busy state. Fourth additions remain blocked.

#### SK-07 — Failed purchase and recovery

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** free. Use Xcode's purchase-failure simulation, or sandbox billing failure settings.

- [ ] 1. Attempt Monthly with failure enabled.
- [ ] 2. Dismiss the error; repeat with Annual and one tip.
- [ ] 3. Turn failure simulation off and retry a subscription successfully.

**Expected:** no entitlement from a failed transaction; clear recoverable feedback; controls usable after failure; successful retry grants access. Errors do not appear twice through both About and the Plus sheet. [Apple purchase-failure guidance](https://developer.apple.com/documentation/storekit/testing-failing-subscription-renewals-and-in-app-purchases).

#### SK-08 — Pending purchase approved, declined, and approved while app is closed

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** local Xcode; enable Ask to Buy in the configuration editor.

- [ ] 1. As a free user, attempt Monthly. Leave the transaction Pending Approval in the transaction manager.
- [ ] 2. Verify no Plus access yet; the app is navigable after the purchase call returns pending.
- [ ] 3. Approve the transaction in the manager while the app runs. Confirm Unlimited and adding D.
- [ ] 4. Reset the fixture. Repeat with Annual, but decline the pending transaction. Confirm free access remains.
- [ ] 5. Reset again. Create a pending purchase, close the app, approve it, then relaunch.

**Expected:** access arrives only after verified completion. Delayed/launch completion is recognized without purchasing twice. Declining grants nothing. Pending is not falsely described as success. There may be no dedicated in-app pending message in the current UI; record the experience separately from entitlement correctness. [Apple Ask to Buy guidance](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode).

#### SK-09 — Interrupted purchase

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** sandbox, with interrupted purchases enabled for this test account.

- [ ] 1. Start a subscription and follow the interrupted flow without completing the required external action.
- [ ] 2. Return to NextSeason. Check capacity and ability to navigate.
- [ ] 3. Complete the required sandbox action/remove interruption, then finish or retry purchase.

**Expected:** no premature Plus grant; no permanently stuck purchase overlay; completion is recognized. Record whether recovery occurred through the original transaction or a retry.

#### SK-10 — Rapid taps and lifecycle interruption

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** free. Run for a subscription and a tip.

- [ ] 1. Tap a purchase button rapidly twice; try another purchase control while Apple's sheet is active.
- [ ] 2. Cancel. Start again, background NextSeason during the flow, then return.
- [ ] 3. In a separate run, complete purchase and relaunch immediately afterward.

**Expected:** app-originated purchases are not duplicated; no overlapping app sheets or stuck controls. A completed subscription is present after return/relaunch. A completed tip does not unlock Plus. Judge transaction counts using the manager, not just visual alerts.

#### SK-11 — Automatic renewal and switching plans

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** paid, A–G saved, simulation off.

- [ ] 1. Allow at least one real test renewal. Check About and every row before and after foreground return/relaunch.
- [ ] 2. Use the environment's subscription-management UI to switch Monthly → Annual; repeat Annual → Monthly on another run.
- [ ] 3. Note the effective time shown by Apple; check again after the switch takes effect.

**Expected:** no lapse while Apple reports an active entitlement, no duplicate tracked shows, no pausing from a valid renewal, and no historical catch-up burst. Plan changes preserve Plus; do not assume every switch takes effect immediately. Validate that App Store Connect places both plans in the intended subscription group.

### Pass 2 — losing and recovering paid access

#### SK-12 — Cancel renewal without expiring

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** paid A–G, comfortably before expiration.

- [ ] 1. Turn off auto-renew using the environment's subscription-management controls. Locally, use a non-renewing test subscription/renewal control; do not use Refund or deleting transactions as a substitute.
- [ ] 2. Record Apple's entitlement expiration.
- [ ] 3. Return to NextSeason before that time, relaunch, and add another show.

**Expected:** Plus remains Unlimited through the paid period; all shows remain active. Cancellation of renewal alone does not pause anything. [Apple local transaction controls](https://developer.apple.com/documentation/xcode/testing-in-app-purchases-with-storekit-transaction-manager-in-code).

#### SK-13 — Actual expiration with app away

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** SK-12; stop auto-renew and confirm expiration occurs.

- [ ] 1. Leave the app backgrounded while the entitlement expires. Reopen after expiration.
- [ ] 2. Record active and paused names, alert text, row styles, and saved total.
- [ ] 3. Open A; tap D–G in Watchlist; swipe-delete one paused row and Undo.
- [ ] 4. Acknowledge the pause alert, relaunch, and inspect again.

**Expected:** A–C remain active; later saves are retained in Paused — Plus Required. Paused rows hide old season/timestamp information and cannot open detail from Watchlist. Active rows still open. Paused removal/Undo preserves its pause state. No saved show disappears merely because Plus expired. The acknowledged alert does not recur without a new pause event. If Apple has not actually expired the entitlement, this is not a valid expiration test.

#### SK-14 — Expiration while the app is open; foreground/background reconciliation

- [ ] Case performed; outcome, environment and evidence recorded.

Repeat expiration while NextSeason stays visible, then switch away and return. Repeat once with the app closed before expiration, and once with an actual scheduled background refresh if your device delivers one.

**Expected:** a foreground entitlement reread detects the lapse and applies the same three-show policy before ordinary watchlist refresh. The implementation does not promise a timer-driven UI transition at the exact second of expiration while continuously foregrounded. Record that timing rather than expecting it. A background run must reconcile before processing shows. If iOS never schedules a background run, mark that portion Blocked, not Pass.

#### SK-15 — Refund/revocation

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** local Xcode for controlled refund/revocation; repeat through sandbox controls if available.

- [ ] 1. Establish paid A–G. Refund/revoke the active subscription transaction using the manager.
- [ ] 2. Check the running app, then foreground return and relaunch.
- [ ] 3. Attempt a fourth active addition.

**Expected:** once the verified entitlement is revoked, paid access is removed and extra shows pause without deletion. Fourth additions are blocked. No remaining second valid subscription or complimentary grant may mask this case. Turning renewal off is not equivalent to revocation.

#### SK-16 — Billing grace, grace recovery, and billing retry without entitlement

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** real-device sandbox account. First record whether Billing Grace Period is enabled for sandbox in App Store Connect.

- [ ] 1. Purchase Plus. Enable sandbox renewal billing failure before the next renewal through Settings → Developer → Sandbox Account → Manage → Account Settings.
- [ ] 2. When Apple reports a grace state, check About, additions, and all seven shows.
- [ ] 3. Resolve billing before grace ends and allow renewal. Confirm access remains.
- [ ] 4. On a separate run, let grace end without recovery, or test billing retry without a grace entitlement. Return to the app.
- [ ] 5. Resolve billing and confirm valid access returns.

**Expected:** Apple's active/grace entitlement keeps Plus. After no entitled state remains, A–C stay active and extras pause. Recovery resumes all saved rows, with silent catch-up. If grace is not configured, mark the grace-specific branch Not applicable and still test retry/expiration. Do not classify every payment failure as immediate access loss. [Apple billing-test guidance](https://developer.apple.com/documentation/storekit/testing-failing-subscription-renewals-and-in-app-purchases).

#### SK-17 — Resubscribe after lapse and repeated lapse

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** lapsed fixture with three active and extras paused.

- [ ] 1. Buy Monthly or Annual again. Inspect all saved shows as access returns.
- [ ] 2. Pull to refresh; relaunch. Record any notifications during reactivation.
- [ ] 3. Let paid access lapse again.

**Expected:** every saved paused row resumes without duplicates. Catch-up updates old data without announcing changes from the paused interval. A later lapse chooses the three oldest surviving saves again; previous free-period selections are not remembered as a separate preference. Current access-change alerts should not remain after restoration. Controlled-data verification of notification history is SK-27.

#### SK-18 — Restore Purchases: active, inactive, failure, repeated

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. With an active paid account, use Restore Purchases from About; repeat from the Plus sheet if reachable. Relaunch first if needed.
- [ ] 2. Repeat on a fresh account without purchases and on an expired account.
- [ ] 3. Induce a restore failure using local error controls or offline real-device testing, then recover and retry.
- [ ] 4. Tap Restore rapidly twice and repeat a successful restore.

**Expected:** valid access is recovered; restore does not purchase or duplicate shows. No-purchase/expired accounts remain free; no false “Plus restored” claim. Failure gets recoverable feedback and no stuck busy state. Repeating restore is harmless. Automatic entitlement detection may restore access before you tap Restore; record that as automatic detection, not proof that the button changed access.

#### SK-19 — Reinstall and second-device distinction

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** active subscription on a disposable test installation; export its watchlist first if needed.

- [ ] 1. Delete and reinstall NextSeason using the same testing environment/account. Open About and use Restore if necessary.
- [ ] 2. Repeat on a second device with the same purchase account if available.

**Expected:** paid entitlement is recoverable. Restore Purchases does not itself import the old watchlist. A fresh installation/device may have no saved shows; do not mistake that for subscription failure. Device-backup restoration is a separate migration test, not part of purchase restoration. Do not do this on your only valuable watchlist.

### Pass 3 — offline, limits, tips, and beta rules

#### SK-20 — Existing subscriber offline, without crossing expiration

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** real-device sandbox/TestFlight; active paid account with no complimentary grant. Choose a long enough test period and record expiration.

- [ ] 1. Launch online and confirm Unlimited/A–G active.
- [ ] 2. Enable Airplane Mode and explicitly disable Wi-Fi. Foreground-return, then relaunch offline.
- [ ] 3. Check About and Watchlist; do not interpret TVMaze fetch errors as entitlement failure.
- [ ] 4. Restore connectivity, foreground-return, and retry any failed action.

**Expected:** no destructive watchlist loss or false confirmed-lapse alert from a temporary verification problem. Cached verified entitlement should be honored when available. If StoreKit is unverified on cold launch, saved pause flags are preserved but new additions may be limited; record the exact state and messaging. Reconnection converges to valid Plus. A show-detail network failure is separate from StoreKit access. If the subscription actually expires while offline, rerun with a longer period before drawing conclusions.

#### SK-21 — Offline free user, offline expiration, and restore failure

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Relaunch a genuinely free account offline; inspect saved shows and purchase options. Attempt Restore, reconnect, retry.
- [ ] 2. Separately, let a paid subscription expire while disconnected, then reconnect and foreground-return.

**Expected:** offline does not grant free users Plus. Purchase/restore failures are recoverable. After reconnect and a definitive inactive entitlement, extras pause without deletion. No claim that a cached offline state proves current server access; record when the app converges after reconnect.

#### SK-22 — Free slots, paused reactivation, and Undo

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** lapsed A–G.

- [ ] 1. Remove active A using its star, but before confirmation try to add H. Undo A's removal.
- [ ] 2. Confirm removal of A; add paused D through Search/Detail.
- [ ] 3. Attempt H with three active again.
- [ ] 4. Repeat using swipe-delete of an active show, followed by adding H and Undo while the toast exists.
- [ ] 5. With two active shows, tap stars for two different new shows rapidly. Repeat with a slow network, then inspect the saved result after returning to Watchlist.

**Expected:** deferred star removal retains its slot during Undo; a real committed removal frees it. Reactivating D updates its saved row rather than duplicating it. No fourth active row should persist; a blocked addition opens Plus. If the replacement addition completed first, Undo restores the original show as paused, preserving its metadata and leaving the existing active shows unchanged. If Undo won the slot first, the later addition is blocked. Human taps cannot guarantee the precise suspension ordering; SK-28 provides deterministic coverage.

#### SK-23 — Tips for free and paid users

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. As free, purchase Trailer, Pilot, and Hit Show separately. Dismiss each thank-you; buy the same tip again.
- [ ] 2. Cancel a tip, fail a tip, then retry successfully.
- [ ] 3. Relaunch and Restore Purchases. Repeat one tip as paid and one as complimentary.

**Expected:** each successful new tip transaction thanks the user once during its handling; purchases are repeatable consumables. Cancel/failure produces no thank-you. Tips never grant Plus, change pause flags, or consume watchlist slots. Restore does not recreate spent tips or retroactively unlock features. Relaunch must not cause a repeated thank-you loop; the app does not promise a persisted receipt/history screen for tips.

#### SK-24 — Permanent complimentary access

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** a separate previously granted beta installation. Do not use it for SK-12–16.

- [ ] 1. Install the normal non-granting build over the existing beta installation.
- [ ] 2. Relaunch online/offline; check About and add beyond three shows.
- [ ] 3. If this fixture also has a paid subscription, let that subscription expire or revoke it.
- [ ] 4. Retry after a normal foreground return. Optionally check a second device with the same iCloud/Keychain setup, allowing sync time.

**Expected:** recognized permanent complimentary access remains Unlimited independently of purchased entitlement. About identifies complimentary access when there is no active paid subscription. A temporary Keychain problem must not revoke already recognized access. Cross-device discovery may depend on Keychain synchronization; it does not synchronize watchlists. A fresh normal installation with no existing grant must not receive a new complimentary entitlement.

#### SK-25 — Simulate Free Tier: state, restart, purchase, restore, tips

- [ ] Case performed; outcome, environment and evidence recorded.

**Start:** actual paid/complimentary Plus with A–G, in Debug or verified TestFlight.

- [ ] 1. About → Diagnostics → Subscription Testing → enable Simulate Free Tier. Inspect the active notice and simulated capacity in About.
- [ ] 2. Confirm A–C active, extras paused, normal cap enforced, export includes all saves.
- [ ] 3. Restore Purchases, purchase a tip, and cancel/fail a Plus purchase; simulation must remain on.
- [ ] 4. Disable simulation; confirm all saves resume. Enable it again, then relaunch; session-only simulation ends and valid actual access resumes.
- [ ] 5. In a fresh local paid-test fixture, make a successful customer Plus purchase started during simulation. It should end simulation after verified active access.
- [ ] 6. Locally repeat with a pending Plus purchase, approving it later. Verify approval ends the same simulation session. Repeat after toggling simulation off/on before approval; an old session's completion must not turn off the new one.

**Expected:** actual purchased/complimentary entitlement is preserved underneath simulation. Renewals, unrelated transactions, restore, and tips do not end the override. Restart ends it; genuine success from the current simulated purchase can end it. If a currently subscribed account cannot make another customer purchase, use a reset fixture; do not count an automatic renewal as this test. Ordinary free users disabling simulation remain free.

#### SK-26 — Production boundary and user-facing presentation

- [ ] Case performed; outcome, environment and evidence recorded.

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

- [ ] 1. Cold launch with no complimentary grant. Observe loading if visible, then confirmed paid/free presentation. Check that no stale uncertainty footer or upgrade button remains after the settled answer.
- [ ] 2. Use a controlled unverified first-read fixture with no complimentary grant. About must display **Unable to Verify Plus**, hide **Unlock NextSeason Plus**, and omit ordinary three-show capacity. Verify the exact footer: “NextSeason couldn't verify your subscription status. Your saved shows are preserved. Check your connection and try Restore Purchases.” Existing saved tracking state must not be paused merely because verification is uncertain. New additions still follow the existing unverified-access limit; this fix does not grant unlimited access.
- [ ] 3. From that fixture, allow a definitive active answer and use Restore Purchases. About must become Unlimited with the paid footer and no upgrade button. The view must update without reopening About.
- [ ] 4. Repeat with a definitive inactive answer on refresh/foreground return. About must become Up to 3 shows with the ordinary free footer and upgrade button. A confirmed lapse may now pause extras through the existing access policy; distinguish this from uncertainty.
- [ ] 5. Repeat Restore Purchases while the entitlement remains unverified. About must stay Unable to Verify Plus with the upgrade button hidden; completing a restore request is not proof of verified paid access. After the request ends, Restore Purchases becomes usable again. Separately test a thrown restore error and recovery.
- [ ] 6. Repeat loading, unverified, and confirmed-free states with a recognized complimentary grant. About remains Unlimited with the complimentary footer. If both paid and complimentary access are present, the paid footer takes priority.
- [ ] 7. Enable simulation over paid, complimentary, and unverified states. About uses the explicit simulated presentation; turning simulation off restores the actual presentation. Preserve the existing rule that the simulated upgrade button waits for the first StoreKit read to finish.
- [ ] 8. With VoiceOver and large text, check the new status/footer are understandable and readable and the Restore Purchases control remains reachable.

A real unverified entitlement can be hard to force. Airplane Mode may produce a cached verified answer instead. If you cannot produce the state on a device, record that portion **Blocked**, and separately record the controlled-fixture/unit-test evidence from `PlusAccountPresentationTests`. Do not record a successful offline launch as proof that the unverified presentation was exercised. The presentation implementation has been reviewed; visual/device acceptance remains to be recorded.

### Controlled-data checks — complete with developer assistance

These are part of the complete coverage record, but cannot be reliably forced through ordinary shipped-app taps. Do not modify live TVMaze records, use debugger shortcuts that bypass entitlement checks, or treat a fictional notification as production proof.

#### SK-27 — Paused refresh, historical catch-up, and old notification navigation

- [ ] Case performed; outcome, environment and evidence recorded.

Have the developer use controlled TVMaze responses on the current code, or run the existing subscription-downgrade suites and record the exact build/results.

Verify:

- [ ] 1. Pause D–G; publish a new status for an active show and a paused show; run the production refresh. Only active shows fetch/update/notify.
- [ ] 2. Resume Plus after historical changes to paused shows. They get a silent baseline; a genuinely later change notifies once.
- [ ] 3. Fail catch-up, swipe-delete its marked show, refresh while absent, Undo, then refresh. The original mark survives and historical data remains silent. Delete and add a genuinely new row instead; the old mark must not silence it.
- [ ] 4. Tap a notification whose show has become paused, both while running and from a cold launch. It lands on Watchlist without paused detail navigation after access reconciliation.
- [ ] 5. Tap an active show's notification; it opens its detail. Tap one for a removed show; it uses the Search fallback or handles unavailable data without crashing.
- [ ] 6. Change access/pause state while a show's fetch is suspended. No stale response unpauses the row or announces its history.

For a manual old-notification smoke check, Diagnostics → Send Test Notification chooses Lupin if tracked, otherwise a saved row; record the actual selected show. Deliver the notification while the show is active, leave it untapped, cause real lapse or enable simulation, and then tap it. Repeat from a closed app with real inactive entitlement. The diagnostics notification is fictional and intentionally bypasses production change detection: it tests delivery/routing only. It is not proof that paused shows can or cannot generate production alerts.

#### SK-28 — Deterministic free admission and ordinary soft-alert confirmation

- [ ] Case performed; outcome, environment and evidence recorded.

Use the current `WatchlistAdmissionAndDebounceTests.swift` suites, or an equivalent controlled manual fixture, to verify:

- Two different additions both hold stale counts during detail fetches; first saves, second hits the cap.
- Immediate Undo restores an active row while an addition is suspended; addition is rejected when it resumes.
- An undated announcement and an ending each use one fixed TVMaze update timestamp: first non-forced refresh waits, second announces, third does not repeat.
- A first StoreKit check still loading does not pause saves; an unverified first check preserves saved state without granting unverified unlimited additions; unverified after confirmed paid access preserves that answer; subsequent definitive active/inactive results converge correctly.

The competing-add test now describes detail-fetch suspension accurately; it does not separately guarantee both additions waited for StoreKit. If you want that exact ordering proven, record it as a separate coverage item rather than claiming a human rapid-tap test establishes it.

#### SK-29 — Notification permission integration

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Deny notification permission; check the Watchlist banner and About status.
- [ ] 2. Use Enable Notifications/Open Settings to enable it. Return and inspect status.
- [ ] 3. Disable permission after enabling it; return again.
- [ ] 4. With controlled data, discover a change while permission is disabled, then re-enable.

**Expected:** UI reflects current alert settings on return; normal tracking still works; enablement takes the appropriate permission/Settings path. Changes processed while notifications are disabled are not promised as a replay backlog. About explains that iOS decides background timing. A silent manual pull-to-refresh intentionally updates the list without production alerts.

#### SK-30 — Unverified transaction and storefront edge cases

- [ ] Case performed; outcome, environment and evidence recorded.

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

## October fixes — Janine's manual pass

Updated October 19, 2026. Run these cases on the final candidate after the beta walkthrough; do not treat earlier implementation test runs as results for this pass. The existing SK-01–SK-30 cases remain the detailed purchase/lapse script. OC-11 below adds entitlement-ordering integration checks; it does not replace those cases.

### Run order and result recording

- [ ] 1. **Ordinary app pass:** beta walkthrough 1–16, then OC-01–OC-06, OC-10 and OC-13–OC-14. Use the current candidate on iOS 18 and a current iOS device/simulator; include iOS 26 coverage when available for its different system appearance. Record unavailable environments.
- [ ] 2. **Physical-device notification pass:** OC-07–OC-09 and OC-12. Use a normal Debug/TestFlight launch, without UI-testing or profiling arguments. Diagnostics is hidden in the UI-test configuration. Real device notification delivery and animation cannot be established by mounted unit tests.
- [ ] 3. **Purchase pass:** SK-01–SK-30 as applicable, plus OC-11. Use a paid-access fixture without complimentary access, and simulation off except where explicitly requested.
- [ ] 4. **Developer-assisted pass:** OC-15–OC-16 and the controlled verification register. These cases require disposable fixtures or existing test seams. There is no ordinary in-app button to corrupt a snapshot, fail a save, or hold a StoreKit read.
- [ ] 5. **Cleanup:** OC-17; record all remaining Blocked/Not run cases and their required next action.

Plan several sessions rather than one sitting. Background delivery and subscription lifecycle cases may need later observation; there is no guaranteed completion time for those portions.

Use **Pass / Fail / Blocked / Not applicable / Not run** for each OC case and each matrix subcase. Record date, build, device/OS, access state, actual show names/IDs, starting state, result and evidence. Mark a box only after executing the step; a box alone is not a pass. Record natural timing attempts as smoke checks unless the intended overlap actually occurred. If a test exposes a failure, preserve its first evidence before retrying; a later pass does not erase it.

**Fixture:** Keep temporary shows A, B, C and an extra D. Record their actual names. For free-cap tests use exactly three active rows; use SK-25 simulation or a genuinely free account. Keep a separate paid fixture for actual purchase tests. Export any valuable watchlist before disposable-install or recovery work. Never overwrite the only copy of a tester's store.

### OC-01 — Complete pagination, query replacement and returning from detail

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** ordinary app; live network. Use a broad title query that actually exposes Load More; record the query rather than assuming any title always has multiple pages.

- [ ] 1. Record the first visible titles and stars. Use Load More until exhausted or until several pages have loaded. Check that earlier rows remain and no identical result is appended twice.
- [ ] 2. Start another Load More, then replace the query with a distinctly different title. When the newer results settle, scroll and wait for any older work to finish.
- [ ] 3. Clear the field during loading, then search again. Repeat rapid query replacement once.
- [ ] 4. Open a result, return, and switch away/back to Search. Repeat while Load More is pending if you can establish that state.

**Expected:** rows, stars, errors and pagination belong to the current query. Clearing stays idle. Returning from detail preserves the displayed outcome and normal pagination rather than unnecessarily restarting it. No stale page or loading flag takes over. A raw API page may produce more than ten displayed hits; that is intentional complete-page retention, not a failure.

**Limit:** live scrolling cannot prove every mapped hit was retained across sparse provider pages. Exact page-remainder, stale completion and mapping-cache checks are in CV-01.

### OC-02 — Try Again followed by a new query or clearing

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** ordinary app on a disposable test session. Offline/cache behavior varies; use a new uncached query A to obtain an actual failed Search state.

- [ ] 1. Disable networking, search A, and wait for the error with Try Again. Restore connectivity.
- [ ] 2. Tap Try Again, then immediately type a different query B. Wait for B and any older request to finish; inspect results, stars, Load More and alerts.
- [ ] 3. Repeat the setup, but clear the field immediately after Try Again.
- [ ] 4. Retry the same failed query without changing the text once, to confirm ordinary retry still works.

**Expected:** late A success/failure never replaces B or changes its stars/cursor. Clearing leaves idle, without a stale error or permanent loading state. Retrying the unchanged query can recover normally.

**Limit:** if A finishes before the replacement, record an ordinary smoke pass and mark the stale-completion overlap Blocked. Airplane Mode does not reliably hold requests or cause a specific late failure. CV-01 supplies deterministic success, failure, debounce and cache ordering. An old open/track resolution error is a separately recorded follow-up, not proof that retry ownership failed.

### OC-03 — Both removal modes, Undo, OK and timeout

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** ordinary app; temporary A/B. Undo normally lasts about five seconds, or twenty with VoiceOver. Use the visible toast, not a requirement to hit an exact millisecond.

- [ ] 1. Un-star A on Watchlist. Before expiry, tap Undo. Repeat and tap OK; re-add A, then repeat and let the toast expire.
- [ ] 2. Do the star/Undo cycle from Search results and from Search detail.
- [ ] 3. Swipe-delete A from Watchlist and tap Undo. Repeat with OK and with timeout, re-adding between attempts.
- [ ] 4. Remove A and then B before A's toast expires. Undo B. Reopen Watchlist and relaunch after the operations finish.
- [ ] 5. With VoiceOver enabled, use the row's removal action and check that Undo/OK are reachable and the longer window is usable.

**Expected:** star removal is deferred: the row remains saved during Undo, with its pending state shown; OK/timeout commits it. Swipe-delete removes immediately; Undo restores it; OK/timeout only dismisses the toast. Replacement commits the earlier deferred removal and offers Undo for the latest one. Other shows remain untouched; relaunch agrees with the completed choices. Restored rows retain their original ordering metadata. Opening another detail can cancel a deferred removal under the existing navigation rule; use OC-05/OC-09 for those transitions.

### OC-04 — Undo after the freed slot has already been filled (R10)

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** free or simulated-free; exactly A–C active. A and replacement D should be easy to find. This can be difficult in the normal Undo interval; do not fake success if the toast expires first.

- [ ] 1. Swipe-delete A. While its Undo toast still exists, add D, then Undo A. Inspect all saved and active rows.
- [ ] 2. Restore the fixture. Swipe-delete A, Undo first, then attempt D.
- [ ] 3. With one free slot, remove/Undo a paused row. Separately remove an active row using its star and try D before confirming the removal.
- [ ] 4. End simulation or restore real Plus as appropriate; inspect the restored paused row.

**Expected:** if D completed first, A returns **paused**, preserving its metadata; D and the other active rows remain active. If Undo took the slot first, D is blocked by the cap. Already-paused rows stay paused on Undo. A deferred star removal does not free capacity until committed. No fourth active row persists. With actual Plus restored, paused rows resume under the normal policy.

**Limit:** if navigation dismisses the toast or the interval ends, record that sequence as Blocked. Use controlled admission/Undo tests (CV-02) for exact competing-operation orders. Do not extend production timing just to obtain a manual pass.

### OC-05 — Real tab selection with a pending Watchlist removal

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** physical device preferred; ordinary app. This is the real-tap gap from the notification-navigation fix.

- [ ] 1. Open a show detail from Search, leaving that detail on the Search navigation stack.
- [ ] 2. Switch to Watchlist. Un-star temporary B, then tap the Search tab while B's Undo toast is visible.
- [ ] 3. Wait for navigation and saving to settle. Return to Watchlist, then relaunch and check B.
- [ ] 4. Repeat with swipe-delete instead of star removal, and once without any pending removal.

**Expected:** manually choosing Search returns to its results/root. B's Watchlist removal commits when leaving that tab; a reappearing old Search detail must not cancel it. No pending toast remains for the committed operation. Swipe-delete remains deleted. Without a removal, normal return-to-results behavior remains intact.

### OC-06 — Notification permission, deferral and settings return

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** ordinary app. Fresh permission allow/deny branches require separate disposable installations/devices whose actual system state is not determined; reinstalling is not assumed to reset every permission state.

- [ ] 1. On one fresh fixture, add a show, choose Not Now in the in-app prompt, and add another. Confirm the app does not repeatedly prompt. Use About → Notifications to explicitly enable later.
- [ ] 2. On another fresh fixture, choose to enable, then deny the system request. Use the Watchlist banner/About entry to open notification settings; enable alerts and return.
- [ ] 3. Disable notifications again. Also test authorized notifications with banners/alerts disabled if that system configuration is available. Check About, Watchlist and Diagnostics after return.
- [ ] 4. Restore normal alert settings. Do not expect missed historical updates to replay merely because permission is enabled.

**Expected:** the system prompt is shown only when appropriate; denied/already-decided states lead to Settings. Core tracking remains usable. Banner/status and test-action availability reflect current alert settings. Diagnostics notification actions are disabled when visible alerts are unavailable, so their disabled state is not a failed scheduling attempt. First-discovered changes while notifications are disabled are intentionally consumed; verify that production rule through CV-03, not by a disabled Diagnostics button.

### OC-07 — Diagnostics actions and notification wording (R03, R12, R15)

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** normal Debug/TestFlight app, alert permission enabled, temporary saved show. Open ellipsis/About → Diagnostics. Record the show identified by each action; Send Test Notification prefers Lupin if saved, otherwise a saved row. Other simulation actions use the repository's first saved row. Do not assume they all choose the same show.

- [ ] 1. Record the real watchlist row's status and date. Tap Run Simulated Update Scenario: note Step 1 and its decision. Tap again: note Step 2 and scheduling outcome. Tap a third time: it should restart at Step 1.
- [ ] 2. Start Step 1 again. Tap Schedule Pipeline Test Notification, then run the next two-step action. The independent delayed runner must not reset the two-step runner; it should still reach Step 2.
- [ ] 3. Schedule another delayed pipeline notification and return to the Home Screen. Observe delivery after the action's roughly five-to-ten-second delay. Separately test Send Test Notification (about five seconds).
- [ ] 4. Return and inspect the real saved row. Tap Force Refresh Now, first online, then on an uncached offline attempt. Reconnect afterward. Open Diagnostics Help and return; share/export diagnostics through its share control and cancel once.
- [ ] 5. Disable alert permission and confirm notification test actions are disabled. Restore it.

**Expected:** step progression and outcome text match the actual action. “Scheduled” means the system accepted the request, not proof it displayed a banner. Simulations use fictional status data without replacing the user's real saved season status. Force Refresh Now refreshes real rows silently; it does not create production alerts. If fetches genuinely fail, the summary must not imply all succeeded. A cached offline response is not a failed-fetch test. Help and report sharing are readable and dismissible.

**Limits:** fictional diagnostics alerts test delivery/routing, not real provider-change eligibility, retry persistence, paused-show exclusion or deduplication. System scheduling rejection cannot be forced by ordinary UI steps; CV-03 covers it. Do not repeatedly run a successful simulation and call its intentional restart a duplicate-production-alert defect.

### OC-08 — Physical-device notification routing matrix

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** physical device, alerts enabled. Run each row with a fresh test notification and record the actual target A. Ensure live lookup works before untracked-target cases. Test alerts contain fictional status text; compare navigation identity, not that fictional text against real detail status.

**Prepare an old notification:** schedule Send Test Notification while A is saved, allow it to arrive, and leave it untapped in Notification Center. Then change A's saved state as required. Confirm removal has committed; avoid Undo. For a foreground **banner** test, schedule fresh delivery, dismiss Diagnostics/About and establish the starting state before the banner arrives. The existing UI delay is short. If you cannot stage removal and the pending toast in time, mark that subcase Blocked and use a developer-assisted longer-delay fixture; there is no adjustable-delay UI control. Tapping a retained notification from Notification Center is a valid routing check but does not reliably establish the already-active banner animation branch.

| Subcase | Starting state and action | Expected |
|---|---|---|
| N1 | A saved and active; tap from the foreground banner | A's Watchlist detail opens; foreground push animates unless Reduce Motion changes presentation |
| N2 | A active; background normally, then tap a retained alert | Correct Watchlist detail, without the foreground slide-in |
| N3 | A active; close the app only after alert delivery, then tap the retained alert | Cold launch reaches A's detail after access reconciliation |
| N4 | A became paused through real lapse or simulation; tap retained alert | Watchlist root; no paused detail. For cold launch use real inactive access, because simulation ends on restart |
| N5 | A removed; Watchlist selected; tap a foreground banner | Search opens A's detail and stays there after tab side effects settle; no bounce to results/root |
| N6 | A removed; Watchlist selected before backgrounding; tap retained alert | Search detail remains visible, without the foreground push animation |
| N7 | A removed; cold launch from retained alert | Search detail opens if live lookup succeeds; no crash if it fails |
| N8 | A removed; Watchlist selected; start deferred removal of different B, then tap A's banner | A's Search detail persists; B's removal commits and its Undo window ends |
| N9 | Repeat N8 using a background-return tap while B's Undo window is still pending | Same persisted result; no unintended cancellation of B |
| N10 | Repeat N8 using B's swipe-delete Undo toast | B stays deleted; informational Undo toast ends |

After N5/N6/N8–N10, wait for navigation to settle, go back, revisit Watchlist and relaunch. Confirm A was not silently re-added and B has the intended persisted state. Record cold launch, background return and foreground banner as distinct observations; one does not stand in for all three. If the toast expires before the tap in N9, the pending-removal condition was not tested.

### OC-09 — Superseded notification requests and Search-origin removal

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** physical device; two distinct target shows with retained notifications. Use controlled held lookups for exact response ordering (CV-07).

- [ ] 1. Tap A's notification, then B's as soon as practical. Wait for all loading to settle. Repeat from a state where one target is saved and the other is removed.
- [ ] 2. Start a deferred removal of temporary B from **Search detail**. Before its Undo interval expires, tap a notification that opens another unsaved target's Search detail. Revisit B and relaunch.
- [ ] 3. Separately navigate manually while a notification lookup is still loading; record the outcome without inventing a new precedence requirement.

**Expected:** the latest notification request wins, with no late push back to the earlier target. For step 2, opening the new Search detail currently **cancels** the Search-origin deferred removal, so B stays saved. This is the existing detail-opening rule, different from leaving Watchlist in OC-08. Record any pending product decision against that rule; it is not silently changed by this script. Manual navigation versus an outstanding lookup is a recorded follow-up, not a newly specified acceptance rule.

### OC-10 — Provider calendar dates across screens and time zones (R02, R09)

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** ordinary app; select a show with an actual displayed future premiere. Record the source calendar date, not a hard-coded expected date for a live title.

- [ ] 1. Compare the premiere on detail, Watchlist and a fresh CSV export. In the CSV compare the descriptive Next Season column with Next Season Premiere.
- [ ] 2. Change time zone between America/Los_Angeles, UTC and a positive-offset zone, keeping the actual clock/date correct. Reopen detail and Watchlist, and reopen About before preparing a new export in each zone.
- [ ] 3. If the Diagnostics fictional alert contains a date, compare that same fictional date across zones separately from the real show's date. Use CV-04 for a controlled production alert matching a known provider date.
- [ ] 4. Restore time-zone settings.

**Expected:** a provider premiere date retains its calendar day everywhere; only localized formatting changes. Date Added/Updated are real instants and may display differently locally. Status calculation uses UTC calendar days, so a local evening transition at UTC midnight is not itself a defect. Do not advance the real device clock to force a season transition or subscription expiration.

**Incomplete metadata:** later/unnumbered episodes must not be labeled season premieres. The documented R09 episode-1 pointer change can still reverse airing to announced-undated; defer policy changes. Use CV-04 rather than waiting for a live show to reproduce it. If there is no suitable dated show, record this check Blocked, not Pass.

### OC-11 — Entitlement ordering in real purchase/restore flows (item #1)

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** real-device sandbox/TestFlight, normal non-granting build, no complimentary entitlement, simulation off. Repeat relevant purchase branches for Monthly and Annual. Use the full setup and lifecycle expectations in SK-01–SK-30.

- [ ] 1. Cold launch while free, then purchase Plus as the app becomes usable. Briefly switch away/back around purchase completion. Confirm Unlimited, add beyond three, inspect saved active/paused rows, then relaunch.
- [ ] 2. Repeat with Restore Purchases on a valid paid account, switching away/back while restore is pending. Confirm access and saved rows converge correctly without transient false lapse alerts or a stuck busy state.
- [ ] 3. Where supported by the chosen test environment, approve a pending customer purchase while the app is running, then while closed; return/relaunch. Keep local Ask to Buy simulation distinct from actual sandbox availability.
- [ ] 4. With actual Plus and more than three saves, exercise a renewal and a genuine lapse/recovery during foreground transitions (SK-11–SK-17). Observe that real active access is not revoked by an older answer and genuine inactivity eventually pauses extras.
- [ ] 5. In the separate simulation fixture (SK-25), complete a customer Plus purchase or pending approval from that simulation session. Check that active access is applied, the simulation ends and the purchase UI becomes usable. Restore/tips/renewals must not end simulation.

**Expected:** no late flip back to free after confirmed active access, no false pause event, no duplicate transaction handling and no permanently enabled simulation after the qualifying successful purchase. Current uncertainty preserves previously confirmed state; it is not automatically a lapse.

**Limits:** UI timing does not prove scans overlapped. Record actual observations and use CV-06 for controlled stale answers, cancellation, .unverified and stuck reads. A stalled **newest** read is a known limitation: dependent operations can wait until a later refresh commits or the app restarts. Foregrounding does not currently retry stalled initial resolution, and a stalled transaction handler queues later updates. Do not manufacture a “pass” by treating indefinite loading as normal; if a real stall occurs, capture diagnostics/time/account state and report it. Do not force arbitrary timeout-based entitlement changes.

### OC-12 — Foreground/background refresh and truthful results (R08, R11, R12)

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** physical device; normal launch, network available, Background App Refresh enabled. Record Low Power Mode, Focus and alert presentation settings rather than assuming background scheduling or visible banners are guaranteed.

- [ ] 1. Leave NextSeason in the background normally for a later observation; do not force-quit it while testing scheduled background work. Reopen and inspect Diagnostics' last background time, fetch result and notification decision.
- [ ] 2. Return repeatedly within a short interval; verify normal use remains responsive. Foreground refresh is throttled to about fifteen minutes, but entitlement preparation still runs; pull-to-refresh and Force Refresh Now bypass that refresh throttle silently.
- [ ] 3. Turn Background App Refresh off, use Search/Watchlist, then restore the setting. Separately test offline force refresh, reconnect and retry.
- [ ] 4. Compare a background run's diagnostics, persisted Watchlist changes and any actual alerts. Record partial failures honestly. Leave a suitable installation unused for a natural long-absence follow-up only if available; use CV-05 for deterministic multi-day/month gaps.

**Expected:** no lost shows, no alert burst from silently resumed rows, and no success wording concealing a total fetch failure. Scheduled time is an earliest hint, not an appointment. No background sample means **Blocked/not observed**, not a pass. A test banner scheduled for five seconds later does not prove the app performed a background fetch. Neither pull-to-refresh nor Force Refresh Now proves automatic notifying refresh behavior.

### OC-13 — Full export after changes, filtering, pausing and offline use

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** ordinary app; mixed active/paused shows if available, including punctuation/non-ASCII/long titles.

- [ ] 1. Open About and export; save a CSV to Files. Compare the complete saved count and names, IDs, dates and URLs. Missing TVDB IDs are allowed when no mapping exists.
- [ ] 2. Change Watchlist filtering/collapsed sections, export again, and confirm hidden/paused rows are included. Cancel the share sheet once; no saved state should change.
- [ ] 3. Add/remove a temporary show, close and reopen About to prepare a fresh export, and compare the new file. Save exports separately because the normal filename can repeat within a day.
- [ ] 4. Repeat offline using saved rows. Reopen the resulting CSV in a spreadsheet application. Record unavailable viewers or induced export errors as Blocked where appropriate.

**Expected:** export is available without Plus, represents every stored show at preparation time, retains correct CSV cells/Unicode and date-only values, and does not mutate the watchlist. About prepares an export when opened; do not assume an already-open ShareLink rebuilds itself after later mutations. CSV is an export only; there is no import/restore-from-CSV feature.

### OC-14 — Accessibility, appearance and known clipped-title check

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** iOS 18 and a current OS, different screen sizes where available; Light/Dark, default text and largest accessibility text. Restore preferences afterward.

- [ ] 1. In particular, inspect **Severance** detail on iPhone 16/iOS 18.6, or record that exact environment unavailable. Check the title/header at large text sizes and capture any clipped text. Also check long titles on the devices available.
- [ ] 2. With VoiceOver, complete Search → detail → add, Watchlist search, deferred Undo/OK, row removal action, paused row, About export, Plus purchase cancellation/restore and notification settings.
- [ ] 3. Inspect alerts, recovery screens (OC-16), Diagnostics outcome text and Help for clipped buttons, unreachable controls and overlapping sheets. Repeat important controls with Reduce Motion/Increase Contrast and other preferred accessibility settings.
- [ ] 4. On a device using a non-English language or another calendar/locale, check title/date/price layout and readable fallback text; untranslated English alone is not a new localization promise.

**Expected:** meaningful labels/states and actionable focus order, reachable controls at large text sizes, readable toast/section headers on iOS 18 and the newer glass appearance. The known title-clipping audit failure remains open; a prior pass on iPhone 16 Pro does not clear the iPhone 16 finding. Record it as an existing issue if reproduced, and report different failures separately. Do not mark accessibility passed merely because that failure predates these fixes.

### OC-15 — Review prompt and diagnostics boundaries

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** developer-assisted, disposable version/defaults fixture for deterministic eligibility; ordinary app for visual smoke checks.

- [ ] 1. Verify About's Rate NextSeason link opens the intended listing/review destination without submitting a review.
- [ ] 2. Run Diagnostics test notifications and simulated pipelines. They must not consume the production per-version review eligibility.
- [ ] 3. With a controlled **production** qualifying notification, return to active use and inspect review-request eligibility/attempt evidence. Verify at most one app request attempt per marketing version and preserved state across restart.

**Expected:** user navigation stays usable. Apple does not display the in-app review request in TestFlight; use a development build for visual presentation checks. In a shipping app Apple controls whether it appears, so absence alone is not a failure or proof of eligibility. See [Apple’s review-request guidance](https://developer.apple.com/documentation/storekit/requestreviewaction). Use ReviewPromptCoordinatorTests/ReviewPromptStoreTests and recorded attempt state to establish eligibility and deduplication; do not repeatedly reinstall or send fictional alerts to force Apple's UI. App Store listing availability is recorded separately.

### OC-16 — Recovery, upgrade and damaged-row presentation

- [ ] Case performed; outcome, environment and evidence recorded.

**Environment:** developer-assisted **disposable** installation/store. These are planned checks, not an instruction to restart the deferred physical “NextSeason Closed Repeatedly” investigation or corrupt a valuable store. No new fault-injection code is required by this document; use existing test seams or mark the UI fixture Blocked.

- [ ] 1. Install the candidate over a representative earlier TestFlight build with known saved identities, ordering and pause states. Export/compare before and after. Do not reinstall for this upgrade check. Record the source build/schema and any documented pre-release fresh-store exception.
- [ ] 2. In a controlled readable store, damage one saved status snapshot while retaining its identity and another healthy row. Launch, inspect the mixed list, export, repair online and relaunch. See CV-08 for the exact persistence-boundary tests.
- [ ] 3. Show the persistence-open recovery fixture. Inspect “Couldn't Open Your Watchlist”, diagnostics export, recoverable-Watchlist export and Cancel. Confirm exporting/cancelling does not reset anything; compare recoverable identities, allowing explicitly incomplete recovery exports.
- [ ] 4. Only on that disposable fixture, confirm Reset Local Data; check the warning, empty new store, cleared pending/delivered app notifications and ability to add again. Subscription/complimentary access is not the watchlist reset target. CSV export is not automatically imported.
- [ ] 5. Exercise controlled unreadable/zero-row export, export failure, reset failure and failure after a successful reset using existing fixtures. Inspect honest errors, available retry/cancel actions, share sheet and large-text/VoiceOver behavior.
- [ ] 6. Inspect the existing generic crash-loop recovery fixture separately: diagnostics and non-destructive Retry are available; destructive store reset is not offered merely because a generic launch loop was detected.

**Expected:** an individual damaged snapshot does not hide healthy rows, identity or the rest of the list. Repair is silent and durable; failures do not silently erase stored data. Recovery clearly separates retry from irreversible reset and never claims an incomplete export is complete. Record any unavailable fixture as Blocked. A successful automated reader fixture is not a visual recovery-screen pass, and upgrade compatibility needs its actual prior-store fixture.

### OC-17 — Cleanup and final record

- [ ] Case performed; outcome, environment and evidence recorded.

- [ ] 1. Turn simulation off, restore network/time zone/accessibility/notification/background settings and any changed test account or scheme settings. Disable purchase errors, pending/interrupted/billing-failure simulations left by testing.
- [ ] 2. Keep completed case outcomes, original failures, screenshots, CSVs and diagnostics under the tested version/build. List partial matrix rows explicitly; do not collapse “blocked” into “passed”. Remove only temporary shows you intentionally used.
- [ ] 3. Record which full unit/UI runs the owner actually performed, on which OS/build and with which remaining failures. This script does not run or authorize a suite automatically.
- [ ] 4. List remaining sandbox/device checks, known accessibility issue, provider-dependent gaps and accepted limitations. Do not restart deferred investigations or profiling batteries simply to fill a checkbox.

### October result sheet

Use a separate copy per candidate. Add rows for N1–N10, both subscription plans and every OS/environment used.

| Case | Outcome | Build / device / OS / access | Actual state, evidence, issue or blocked reason |
|---|---|---|---|
| OC-01 Pagination/replacement | | | |
| OC-02 Retry then type/clear | | | |
| OC-03 Both Undo modes | | | |
| OC-04 Undo at capacity | | | |
| OC-05 Real manual tab tap/removal | | | |
| OC-06 Permission/settings | | | |
| OC-07 Diagnostics actions | | | |
| OC-08 N1–N10 device routing | | | |
| OC-09 Superseded taps/Search removal | | | |
| OC-10 Date/time zones | | | |
| OC-11 Entitlement integration | | | |
| OC-12 Foreground/background | | | |
| OC-13 Export | | | |
| OC-14 Accessibility | | | |
| OC-15 Review prompt | | | |
| OC-16 Upgrade/recovery | | | |
| OC-17 Cleanup/remaining checks | | | |

### Controlled verification register — not ordinary manual taps

These are the limits of manual verification, not extra hidden UI features. For each row record **current-candidate automated evidence**, **developer-assisted fixture observation**, or **Blocked/Not run**, separately. Reuse relevant existing evidence when it applies; do not rerun broad suites merely to fill the table. If a fixture would require new code, leave that work explicit rather than silently adding it during manual testing.

| ID / area | Required controlled scenario and expected result | Existing starting points |
|---|---|---|
| CV-01 Search (R04–R07, item #3) | Partial first page plus full final page retains every unique mapped hit; stale retry success/failure, clearing, held debounce and mapping filtering cannot overwrite newer results/cursor/cache. Returning to unchanged results preserves Load More. Unavailable bootstrap map shows an honest failure rather than ordinary no matches. Save/resolve failures surface appropriately. | SearchViewModelTests; SearchWatchlistTrackingTests; TheTVDBClientTests; SearchRetryOwnershipReview-2026-10-19.md |
| CV-02 Watchlist (R10) | Both competing add/Undo orders preserve the three-active cap; Undo over capacity restores the original row paused in one write; failed removal/restore is visible and consistent with persisted state; paused state and ordering survive restart. | WatchlistAdmissionAndDebounceTests; WatchlistPendingRemovalTests; SwiftDataWatchlistRepositoryRollbackTests; SubscriptionDowngradeRefreshTests |
| CV-03 Notifications (R03) | Definite scheduling failure retries on next eligible poll, including after reopening an on-disk store; acceptance deduplicates; suppression/unknown do not replay. Failure restore cannot alter paused, removed, re-added or superseded rows. Concurrent refresh skips busy shows. Save-before-schedule termination and failure-to-save-retry are documented loss windows, not promised delivery. First soft change waits, second confirms, third does not repeat. | NotificationDeliveryOutcomeTests; WatchlistDeliveryRetryTests; WatchlistAdmissionAndDebounceTests; R03/R13 matrix scenarios 1–23 |
| CV-04 Dates/status (R02/R09) | A fixed provider date stays the same day in headline, notification and CSV across zones. Missing/contradictory season data and next episode 1/8/unknown use the specified fallback. Exercise UTC day/end-date boundaries. Optional persisted airing → announced-undated → airing sequence counts notifications; keep the documented R09 display reversal separate from any newly demonstrated repeat. | PremiereDateDisplayTests; NextSeasonCalculatorTests; StatusChangeDetectorTests; 2026-10-18-r09-pointer-churn-follow-up.md |
| CV-05 Mapping/refresh (R08/R11/R12) | Resume a capped mapping drain days/weeks later using request-time windows; preserve cursor/horizon and propagation margin. Long-absent stable rows catch up using full map. Failures/cancelled work cannot falsely advance coverage; overlap and clock reset preserve correctness. Empty, total-failure, partial-success and cancellation outcomes map honestly to diagnostics/background completion. Do not change a real device clock or wait a month to simulate this. | ShowIDMappingRefreshServiceTests; ShowIDMappingDatabaseTests; WatchlistRefreshCoverageTests; WatchlistRefreshServiceTests; RefreshSchedulerTests; R08/R11 matrix |
| CV-06 Access (item #1) | Hold old inactive/active scans and release in reverse order; only newest-request results apply. A newer successful scan releases callers even while an older one remains held. Purchase/update finishing and simulation completion await applied access; restore overlap, cancellation, burst requests, .unverified newest result and complimentary grant preserve their contracts. Record newest-stall recovery limitation without simulating a false inactive entitlement. | PurchaseServiceEntitlementOrderingTests; PurchaseServiceTests; FreeTierSimulationTests; SubscriptionDowngradeTests; EntitlementCheckOrderingReview-2026-10-19.md |
| CV-07 Navigation (R14, item #2) | Held A lookup finishes after B; B remains selected. Mounted ContentView preserves Search detail after tab effects, including a held removal commit. Deferred Watchlist removal persists; paused/cold-launch cases reconcile access before routing. These tests complement, not replace, OC-05/OC-08 real-device taps/animation. | ContentViewNotificationNavigationTests; AppNavigationCoordinatorTests; NavigationUITests; NotificationSearchNavigationReview-2026-10-19.md |
| CV-08 Persistence/export (R01/R13) | Force insert/delete/pause/reactivation/refresh/Undo/retry-restoration save failures: rollback and later writes never commit discarded state; inspect fresh contexts and on-disk restart where appropriate. Damage one snapshot: identity survives, mark precedes exposure, repair silently baselines and clears only after successful save. Marks survive absence/Undo, retry failure and restart; re-added rows do not inherit old marks; not-found repair terminates appropriately. Recovery exports retain healthy and damaged identities and handle unreadable stores honestly. | SwiftDataWatchlistRepositoryRollbackTests; WatchlistSnapshotRepairTests; WatchlistRecoveryExportReaderTests; PersistenceRecoveryExportPreparationTests; NextSeasonSchemaTests; AppLaunchStateTests |
| CV-09 Tool evidence (R15–R17) | Simulation Step 1/2/reset and failed retry match outcome; missing/empty/malformed trace, HAR, CPU or console evidence cannot count as performance readiness. Capture lifecycle cleanup is covered by focused script tests. Historical incomplete sessions remain incomplete; run no new device-profiling battery just for this script. | DiagnosticsSimulationsTests; Scripts/tests; 2026-10-16-profiling-investigation.md |

### Source and decision references

- [Original feature-area review](../Reviews/2026-10-12-feature-area-review.md), [approved decisions/analysis](../Reviews/2026-10-12-feature-area-review-analysis.md), [R03/R13 matrix](../Reviews/2026-10-12-r03-r13-behavior-matrix.md), [R08/R11 matrix](../Reviews/2026-10-13-r08-r11-behavior-matrix.md).
- [Entitlement ordering](../Reviews/EntitlementCheckOrderingReview-2026-10-19.md), [notification navigation](../Reviews/NotificationSearchNavigationReview-2026-10-19.md), [Search retry ownership](../Reviews/SearchRetryOwnershipReview-2026-10-19.md), [remaining follow-ups](../Reviews/2026-10-19-follow-ups.md), [known accessibility failure](../Reviews/Known-Test-Failures.md).
- [Free-tier simulation](FreeTierSimulation.md). Diagnostics labels and behavior checked against the current app implementation on October 19, 2026. These are instructions, not test results.
- [TVMaze API](https://www.tvmaze.com/api) documents update-map windows and propagation caching; deterministic timing/window proof uses fixtures. [Apple sandbox account controls](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/) support the assigned billing scenarios; record actual account timing and available controls rather than assuming production durations.

---

## Release coordinator checklist — Janine only

The walkthrough provides broad user-facing regression coverage. Completing it does not, by itself, complete every engineering or production check in the roadmap.

- [ ] Assign coverage across iOS 18, 26, and 27 and different screen sizes, including both system-design generations. Testers use their existing devices; they should not upgrade/downgrade iOS for this task.
- [ ] Track results against a specific final version/build. After fixes, repeat affected tests and connected flows; broader changes may require another full pass.
- [ ] Assign a clean install on a spare device or controlled test environment, including empty Watchlist, initial launch, and first-run permission allow/deny paths. Separately verify upgrade from earlier TestFlight builds with existing data. Do not risk a tester's only Watchlist.
- [ ] Complete OC-01–OC-17 and N1–N10 with individual outcomes. Use the controlled verification register to distinguish fixture evidence from manual passes.
- [ ] Use controlled fixtures/test tooling ([SK-27–SK-30](#controlled-data-checks--complete-with-developer-assistance)) to verify qualifying notification events, long titles, duplicate suppression, removed shows, tap behavior, and background refresh. Natural beta use is supplementary evidence.
- [ ] Use [Assigned StoreKit testing](#assigned-storekit-testing) and its [result sheet](#result-sheet) to record the detailed coverage below.
- [ ] Verify monthly and annual purchasing, cancellation, failures, restore, and each of the three tip products with suitable sandbox accounts ([SK-01–SK-19](#pass-1--purchases-catalog-and-transaction-lifecycle), [SK-23](#sk-23--tips-for-free-and-paid-users)). Complimentary beta access must not mask entitlement failures. TestFlight purchasing does not establish production StoreKit correctness; complete applicable production configuration and launch checks separately.
- [ ] Verify Plus expiration with more than three stored shows ([SK-13–SK-17](#pass-2--losing-and-recovering-paid-access), [SK-22](#sk-22--free-slots-paused-reactivation-and-undo)): preserve all stored shows and their export, and check the specified free-tier behavior. Verify complimentary entitlement persistence using the intended grant and ordinary release configurations.
- [ ] Verify prices come from StoreKit ([SK-02](#sk-02--product-catalog-prices-disclosures-and-links)), product/period presentation matches App Store Connect, legal links work, and Family Sharing is off for both subscriptions.
- [ ] Test persistence recovery and crash-loop prevention using controlled failure injection, including diagnostics export, readable-Watchlist export, reset consequences, and successful relaunch. Do not ask ordinary testers to corrupt storage or trigger resets.
- [ ] Owner: record actual final unit/UI results for the candidate. Review existing Instruments evidence and its gaps separately; do not restart the deferred physical-device investigation or automatically repeat a profiling battery. Perform upgrade/migration checks with representative earlier stores (OC-16).
- [ ] Regenerate the bundled TVDB–TVMaze mapping before release as PROJECT.md requires; verify the candidate actually contains the regenerated artifact. This manual-test document does not regenerate it.
- [ ] Review date/time-zone differences against the intended date model (OC-10). Verify all user-facing error and recovery states and release visibility of diagnostics.
- [ ] Check the final build against screenshots, description, supported OS/device settings, and current feature set. This script intentionally contains no removed theme-switcher test or CSV import test.

Originally prepared from the October 7 readiness roadmap and audited README; consolidated October 19, 2026 against the current code and review records. Exact OS/Xcode controls and fixture availability must be recorded on the tested candidate. Country-specific streaming availability, CSV import and new status policies are outside this script. The deferred physical-device “Closed Repeatedly” investigation remains deferred.
