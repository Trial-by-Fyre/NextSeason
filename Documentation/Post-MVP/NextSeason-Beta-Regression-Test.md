# NextSeason: beta regression and release testing

**Updated October 27, 2026.** A printable/checkable copy is [here](NextSeason-Beta-Regression-Checklist.md).

- [Beta tester walkthrough](#beta-tester-walkthrough)
- [What to record and send](#what-to-record-and-send)
- [Volunteer purchase checks](#volunteer-purchase-checks)

## Beta tester walkthrough

Allow roughly 30–45 minutes, plus normal use over the next day or two. Perform each flow once. Mark each test **Pass**, **Problem**, or **Skipped**, with a reason for skips. If something goes wrong, continue with other areas when possible.

## What to record and send

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

## Before you start

1. Record your iPhone model, iOS version, and NextSeason version/build shown in TestFlight.
2. If you already have NextSeason, note or screenshot your Watchlist **before** updating. Install the latest requested TestFlight build over the existing app.
3. Start with an internet connection. Keep a note of any iPhone settings you change so you can restore them afterward.
4. Record your **starting access state**. Tap **•••** at the top left of Search or Watchlist to open About. Under NextSeason Plus, **Up to 3 shows** means you are on the **Free** tier; **Unlimited** means you have **Plus** (a subscription or complimentary beta access). If you have Plus, test 9 explains how to check the free limit without cancelling anything.
5. Use **The Rookie** (for show details and any displayed future premiere), **The Good Place** (ended), and **The Woman in the House Across the Street from the Girl in the Window** (long title). A **test show** means a show you add only for this walkthrough and are happy to remove afterward; the app does not mark it specially. Use The Good Place for removal checks if you do not want to keep it. If you already save a suggested show and want to keep it, leave it intact and use another suggested show you are happy to remove, or skip the removal step. On Free, only three active shows fit; you can search/open other titles without saving them. Keep **The Rookie saved until test 16**; do not choose it for any removal/free-slot check. If you cannot save it without removing a show you want to keep, use an existing saved show with a future premiere for test 16, or skip that test if none is available. Live metadata changes, so use the dates/status actually shown.
6. **Do not delete the app or reset its data for this walkthrough.** Your Watchlist is stored locally. Clean-install testing is a separately assigned task.

Use the corresponding control if a button's wording differs slightly from this script. If you cannot find a feature, report that rather than guessing.

## 1. Update and launch

1. Open NextSeason after installing the update.
2. Check your previous Watchlist against your note or screenshot.
3. Switch between Search and Watchlist several times.
4. Open a show, go back, leave the app for the Home Screen, and return.
5. With at least one saved show, close NextSeason from the app switcher and reopen it normally, without tapping a notification. Verify it opens on Watchlist; this also covers the relaunch portion of test 7. Empty-watchlist launch is a separately assigned first-run check.

**Expected:** The app opens without crashing or becoming stuck. Your existing shows remain. Navigation works, and returning to the app leaves it usable. No unexpected recovery or reset screen appears.

## 2. Search for shows

Perform these from the Search tab.  These are search-only checks; do not add every result to Watchlist.

1. Search for **The Rookie** by its full title.
2. Search for **Rookie** to try part of that title.
3. Search for **Star Trek** and scroll down to Load More Results. Note the last couple of titles on the page, then tap **Load More Results** and check that those titles remain without duplicates. Tap **Star Trek: Enterprise** if available (otherwise another Star Trek result), then go back; results and further loading should remain. Provider result counts can vary.
4. Search for **Columbo**, an older show.
5. Search for **Marvel’s Agents of S.H.I.E.L.D.**, then **Marvels Agents of SHIELD**, to compare searches with and without punctuation.
6. Search for **zzqxvnonexistentshow** (or any other string of gibberish), which should have no matching show.
7. Clear the search field, then search for **The Good Place**.
8. Change the search from **The Good Place** to **Severance**. Verify that the results update to match Severance

**Expected:** Results match the query, scroll normally, and open the selected show. No-results searches give understandable feedback. Clearing or replacing a query works. Report missing titles, confusing duplicates or incorrect destinations; not every alternate spelling/punctuation variant is guaranteed to match. These titles are present in the bundled mapping, but live search/provider changes can still affect results.

## 3. Open show details

1. In the **Search tab**, search for **The Rookie**, then tap its result row to open the show’s details.
2. Scroll to the bottom and back up.
3. Check its title, overview, and any displayed season or episode information.
4. In the Search tab, search for **The Good Place**, tap its result row, and check that its status is ended.
5. Search for `The Woman in the House`, open **The Woman in the House Across the Street from the Girl in the Window**, and check its row in Search and its details for clipped text or overlapping controls.
6. Tap **View on TVMaze**, then return to NextSeason.
7. While viewing a show’s details opened from Search, tap the already-selected Search tab again. Verify it returns to the Search results/root without a blank screen. Open another result, then switch to Watchlist and back to confirm navigation still works.

**Expected:** Each result opens the correct show. Information is readable, scrolling and back navigation work, and missing dates are presented clearly. The long title wraps rather than overlapping the star or other controls. View on TVMaze opens that show's TVMaze page. An ended show should not misleadingly promise another season.

## 4. Add shows and check the Watchlist

**Start:** any access state. On Free, stay within three **active** shows; test 9 covers the limit. If all three active shows are ones you want to keep, skip new additions and use an existing active show for steps 2–4. Do not buy Plus or delete valued shows to perform this test.

1. Add The Rookie by tapping its empty star in Search.
2. Open Watchlist and find it.
3. Open its details from Watchlist.
4. Return to Search and find the same show again. Its star should be filled.
5. Add **The Good Place** and the long-title show from setup, using a Search-tab result’s star or its Show Details star. If you already have a full Free watchlist of shows you want to keep, skip these additions rather than deleting them.
6. Scroll through the Watchlist, including past section headings.

**Expected:** Added shows appear once, their stars reflect their tracked state, and the state agrees between Search, details, and Watchlist. Tapping a filled star never adds a duplicate. Section headings remain readable as rows scroll beneath them. Grouping agrees with the status/date information displayed for each show.

## 5. Search your Watchlist

1. Open the Watchlist search control.
2. Enter part of a tracked show's title.
3. Enter a title or nonsense that does not match your Watchlist.
4. Clear the field and close search.
5. If you have shows in two or more sections, choose a show X and collapse its section by tapping the header. Close and reopen the app; confirm that section stays collapsed. Search Watchlist for X, inspect the matching section header/count, then expand it and confirm X appears. Clear the search and restore your preferred section expansion.

**Expected:** Search filters saved shows, including paused shows. A previously collapsed section stays collapsed during search; expand its matching header to see its rows. A matching collapsed section must not be reported as “No Matches.” Report unclear counts or hidden-match presentation separately as usability findings rather than assuming search automatically expands sections. A genuinely unmatched query shows No Matches. Clearing or closing search restores the full Watchlist without removing shows or resetting section preferences. If you cannot arrange two sections without disturbing your real shows, mark that branch Skipped.

## 6. Remove, Undo and re-add a show

Use an **active test show you are happy to remove**, such as The Good Place if you added it for testing. Expand its Watchlist section if necessary. If every active show is one you want to keep, skip these removals. A paused show is not a substitute for this active-show check.

1. On Watchlist, tap that show’s filled star. Before continuing, note whether you noticed a message offering a way to cancel removal, and where you looked for it.
2. The message is a **toast at the bottom of the screen**, with Undo and OK. Tap Undo or the show’s star again; the show stays. Repeat once and finish removal with OK or let the toast expire (about five seconds, longer with VoiceOver).
3. Tap the **Search tab** (not Watchlist’s search field), search for that show, and tap its empty star to re-add it. Check it appears once in Watchlist. If Free access blocks the add because all active slots are occupied, record that limit and skip re-adding; no purchase or removal of another valued show is required.
4. Switch to Watchlist, swipe-delete the active test show, and tap Undo; it returns once. Repeat without Undo and confirm it stays removed after switching tabs. If it could not be re-added in step 3, skip this step.

**Expected:** Undo keeps/restores one saved show; completed removals remain removed and other shows are unaffected. Stars agree across Search, details and Watchlist. Report if the toast was hard to notice, even if it worked once you found it. No blank navigation or unexpected cancellation when leaving Watchlist. Exact add/Undo races and save failures belong to automated tests.

## 7. Keep data between sessions

1. Screenshot or note the current Watchlist.
2. Leave NextSeason and use another app briefly, then return.
3. Close NextSeason from the app switcher and reopen it normally. With saved shows, verify it opens on Watchlist. Reuse test 1’s result if you already checked this with the same saved list.
4. If convenient, restart your iPhone and open NextSeason again. Note the first screen as well as where it settles; report any brief welcome/Search screen before Watchlist, ideally with a screen recording if easy to capture. Do not keep restarting just to reproduce it.

**Expected:** The Watchlist remains intact after each step. Ordinary closing and reopening does not trigger a recovery screen. If a Search or welcome screen briefly appears before Watchlist, mark **Problem**; this is an open issue under investigation, even if Watchlist eventually appears.

## 8. Export your Watchlist

1. Open About (**•••**) and tap **Export Watchlist**.
2. Cancel the share sheet.
3. Confirm that your Watchlist is unchanged.
4. Export again and save the CSV to Files.
5. Open it in Numbers, Excel, or another spreadsheet app, if available.
6. Compare names, count, IDs and dates with your full Watchlist, including collapsed sections and paused shows. Check a punctuation/non-ASCII title if available. After another planned add/remove, reopen About and export again to confirm the file reflects the changed list; this can be combined with test 12’s offline export.

**Expected:** The share sheet works and canceling is harmless. The CSV contains the **complete stored Watchlist**. It includes show names and TVMaze IDs, with TVDB IDs where available. Titles containing punctuation remain in their correct cells. Export does not require Plus. Reopen About to prepare a fresh export after changes; CSV is export-only and cannot be imported (for now). If you cannot open the CSV, report that part as skipped.

## 9. Free limit and Plus

**Start:** check About. If you have:

- **Up to 3 shows:** you are already Free. If you have fewer than three active shows, add test shows until three are active. Paused shows do not count toward the limit. Do not remove real shows to prepare this test.
- **Unlimited:** do not cancel anything. Open About → **Diagnostics** → **Subscription Testing** and turn on **Simulate Free Tier**. About now shows **Up to 3 shows (simulated)**. An alert **Some Shows Are Paused** may say Plus is no longer active. This is the simulation: tap OK; your real Plus access is unchanged. With more than three saves, the three oldest shows remain active automatically and the rest move to **Paused — Plus Required**; nothing is deleted. No removal is needed to obtain three active shows. If you have fewer than three saves, add test shows until three are active.

If simulating the free tier produced paused shows, perform the paused-row checks below; otherwise skip to the main free-limit steps. Keep simulation ON through both parts until main step 6.

### Paused-row checks

**Start:** Simulate Free Tier is ON, three shows are active and at least one is paused. If this starting state is unavailable, mark this branch Skipped.

1. Confirm the three oldest saved shows stay active and the others appear under **Paused — Plus Required**, with an explanation that they remain saved but are not tracked.
2. Tap the body of a paused row, avoiding its star. Details must not open from Watchlist.
3. Search Watchlist for that paused show; its paused row must appear. Clear the search, then export and verify the paused show is included in the CSV.
4. If you have a **paused test show**, swipe-delete it and tap Undo. Verify it returns exactly once and stays paused. If every paused show is valuable, mark only this removal/Undo step Skipped; do not delete a real show for the test.
5. Leave Simulate Free Tier **ON** and continue to the main free-limit steps. Removing a paused show does not free an active slot, and removing an active show does not automatically reactivate a paused one.

### Main free-limit steps

1. With exactly three active shows, use the **Search tab** to find **Columbo** (or **Severance** if Columbo is already saved) and try adding it as another active show. Use a result that is not already saved.
2. Check that the Plus screen opens and has a usable Cancel control. Optional assigned purchase checks are at the end of the walkthrough.
3. Dismiss it without buying and check that your Watchlist still has the same three active shows.
4. Only if one of those three **active** shows is a test show you are happy to remove, remove it and complete the removal with OK or timeout, then add a different untracked show. Verify the new show appears once and there are three active shows again. Removing a **paused** show frees no slot. If all three active shows are ones you want to keep, mark this step **Skipped**; do not delete a real show for testing.
5. Open Plus from About using **Unlock NextSeason Plus**, then dismiss it.
6. If you turned on Simulate Free Tier, turn it **OFF** now. About shows **Unlimited** again and all remaining paused shows reactivate. Try adding one **not-yet-saved** show from the Search tab; it should succeed even when you already have three or more saved shows. It need not be the fourth saved show. Leave it saved only if you want to keep it.

**Expected:** Trying to exceed three active shows while Free opens Plus without adding the new show. Dismissing leaves the original three intact. If main step 4 is performed, a completed removal of an active show frees a slot for one addition; paused shows are not automatically promoted. Both routes to Plus work. Turning simulation off restores Plus without losing remaining saved shows. A skipped removal check is not a failure or a pass. **End state:** Simulate Free Tier is off.

## 10. Notification permission

1. Open About and note the **Notifications** status (Enabled or Disabled).
2. If NextSeason asks for notification permission during normal use, for example after you add a show, record when it appears and your choice. Do not reinstall just to trigger it.
3. In iPhone Settings → Notifications → NextSeason, turn **Allow Notifications** off. Return to NextSeason.
4. Check Watchlist for the **Notifications Are Off** banner and About for **Disabled**.
5. Tap **Open Settings** on the banner. Turn notifications back on and return to NextSeason.
6. Restore your preferred notification setting.

**Expected:** The banner and About status update when you return from Settings. If you chose Not Now in the in-app prompt, ordinary adding/relaunch must not nag; About → Notifications remains available to enable later. Fresh allow/deny branches are assigned once in the first-run check. Open Settings opens NextSeason's notification settings. Denying permission does not cause a crash or repeated system permission requests.

## 11. Background refresh and real notifications — opportunistic

No waiting session is required. Leave **Background App Refresh** on for NextSeason and use the app normally over the next few days. Leave it in the background rather than repeatedly closing it from the app switcher.

- If a show's **Updated** time changes without you refreshing, or a real show-update notification arrives, note it. For a notification, screenshot it, check that the text is understandable, tap it, and record where the app opens.
- Report duplicate notifications or a notification for a show you removed.

**Expected:** iOS decides when background work runs, and a notification needs a qualifying show change. **Nothing happening is not a failure**; mark this test skipped unless you observe something.

### Optional notification-tap check — TestFlight with Diagnostics available

This uses fictional notification text to check delivery and navigation, not a real season update. Run only if you are comfortable using Diagnostics; otherwise mark Skipped.

1. With notifications and visible alerts enabled and at least one active saved show, open About → Diagnostics → **Send Test Notification**. Note the named show in the outcome text (Lupin if saved, otherwise your most recently added show).
2. Tap **Done** in Diagnostics, then go to the Home Screen before the roughly five-second delivery delay ends. Tap the notification banner, or the delivered alert in Notification Center.
3. Verify NextSeason opens that show’s Watchlist details. Return to the list and verify saved data is unchanged. If the chosen show is paused, expect Watchlist without opening paused details; do not count it as an active-show pass. You do not need to repeat this for different app-start or saved-show states.

**Expected:** the active saved identity matches the destination, regardless of the fictional season text. If permissions, Focus, or system delivery prevent an alert, record Skipped/Not observed with the reason. This does not prove background refresh, provider-change detection, or production notification eligibility.

## 12. Offline and network recovery

Start online with saved shows. For the optional add, Free users need a free slot: remove only an **active test** show and finish the removal. If every active show is valuable, skip the add portion; removing a paused show frees no slot.

1. Online, refresh Watchlist and open a show’s details. In the Search tab, leave an untracked test Search result visible without opening its details; record its name.
2. Turn on Airplane Mode with Wi-Fi off. Try each action below and note **Worked**, **Error**, or **Did not finish**. Some actions can use saved/cached data and work normally; they are not required to fail. Keep a note of the show or search text for anything that needs retrying:
   - In the Search tab, add the retained untracked result, **only if you prepared a free slot or have Plus**; otherwise mark this action Skipped.
   - Search for a title you have not searched today, for example **Murder, She Wrote** if unused.
   - Use Watchlist’s search to find a saved show.
   - Open a saved show’s details, noting whether the Next Season information loads or shows an error.
   - Pull down on Watchlist to refresh and note any failure message.
   - Export Watchlist from About and save it to Files.
3. Turn Airplane Mode off, restore Wi-Fi/mobile data, and wait until you have a connection. Use your notes from step 2:
   - Refresh Watchlist again and check that it completes normally.
   - Retry only the other actions marked **Error** or **Did not finish**. For Search, repeat the same query or tap Try Again if shown; for details, reopen the same show or use its Try Again control. Retry a failed Watchlist search/export too, and report if it still fails.
   - If adding failed, retry that same show and confirm it is saved exactly once. If adding already worked offline, **do not tap its filled star again**—that would remove it.
   - Actions marked **Worked** or **Skipped** need no repeat. If everything except refresh worked offline, just repeat refresh.
4. Open the offline CSV if a viewer is available and compare it with the saved list. Reuse test 8’s sharing/content checks; restore your network settings.

**Expected:** Saved shows and local Watchlist search/export remain available offline. Uncached requests or adding may fail with understandable feedback and usable retry; a failed add leaves an empty star and no partial row. Cached/full-detail success is valid but does not cover the failure branch. Refresh must not falsely report a total failure as success; cached offline refresh may succeed. No lost data, duplicate rows, crash or indefinite loading; reconnecting recovers without restarting. Exact stale-result, cancellation and save-failure regressions are covered by automated verification.

## 13. Readability and appearance

1. Check Search, show details, Watchlist, and About in your normal appearance.
2. In **Settings → Appearance** (iOS 27), or **Settings → Display & Brightness** (iOS 26 and earlier), switch between Light and Dark appearance and revisit those screens.
3. In Settings → Accessibility → Display & Text Size → Larger Text, turn on Larger Accessibility Sizes and drag to the largest size. Check those screens and Plus, if accessible.
4. With large text, check that the Search field stays visible and results/details can be scrolled. You have already searched, so **Try an Example should no longer appear**; its first-run appearance is checked separately, not here. If the results hint is still shown, check that it scrolls with the list. On Watchlist, a "No Matches" or empty-Watchlist message appears below the Notifications Are Off banner rather than on top of it. Also try scrolling, tapping stars, and dismissing sheets.
5. If comfortable, briefly enable Increase Contrast, **Show Borders** (called Button Shapes on iOS 18), Reduce Transparency, and Reduce Motion, checking the main screens after changes.
6. Restore your preferred settings.

**Known issue:** the Severance detail title may be clipped on iPhone 16 / iOS 18.6. See [known failures](../Reviews/Known-Test-Failures.md).

**Expected:** Text and controls remain readable and reachable. Important text does not overlap or disappear. Watchlist section headers stay readable. States such as tracked/untracked can be distinguished without relying only on color. Report confusing wording or truncated English text, including on phones using another system language.

## 14. VoiceOver — optional if comfortable using it

1. Enable VoiceOver using your usual method. If unfamiliar with it, skip this test.
2. Navigate Search, read a result, and open its details.
3. Find the star control and check whether its label/action describes adding or removing the show correctly.
4. Navigate Watchlist, its search control, and the available row actions.
5. Open and dismiss About/export and any assigned Plus sheet with VoiceOver; check focus and controls remain usable on return. Purchase/restore outcomes are covered in the assigned StoreKit pass. Turn VoiceOver off if desired.

**Expected:** Controls have meaningful labels and their states are announced correctly. Navigation order makes sense. You can search, track a show, and return without becoming trapped. Report the exact screen/control for any unclear announcement.

## 15. About, links, and credits

1. Open About and check the version and build channel.
2. Under **Help & Legal**, open **Support**, **Privacy Policy**, and **Terms of Use** in turn, returning to the app each time.
3. Under **Credits**, open **Show data provided by TVMaze** and **Search metadata provided by TheTVDB**.
4. On Search results, scroll to the bottom and tap TheTVDB credit.
5. In **About**, tap **Rate NextSeason**. Do not submit a review.
6. If the Support page offers an email link, check its destination and cancel without sending.

**Expected:** Support opens the NextSeason support page on getnextseason.com, and Privacy Policy opens the NextSeason privacy policy. Terms of Use opens Apple's standard license agreement, which NextSeason uses. The TVMaze credit opens tvmaze.com, and both TheTVDB credits open thetvdb.com. Support email is addressed to `support@getnextseason.com`. Return navigation works. If an App Store/review link cannot resolve before launch, record the destination and error so Janine can distinguish listing availability from a broken link.

## 16. Time-zone/date check with The Rookie

**Show:** The Rookie, tracked, or another saved show with a displayed future premiere. Use the date the app shows for this test. If choosing another show, record its name, ID, and date. If no future premiere is available, mark this test Skipped.

Use the selected show throughout the following steps, substituting its name for The Rookie if necessary.

1. Note the premiere date in the selected show’s details and Watchlist row, then compare it with a fresh export’s Next Season description and premiere-date column.
2. Open Settings → General → Date & Time. If you see **Set Time Zone Automatically**, turn only that switch off and leave **Set Time Automatically** on. If you instead see a single **Set Automatically** switch (the older layout), turn it off. Tap **Time Zone City** or **Time Zone**, whichever appears, and choose **Singapore**. Change only the time zone—not the date or clock fields. Return to NextSeason and check the selected show’s details and Watchlist row.
3. Change the time zone to **Honolulu**. Return to NextSeason and check again.
4. Turn the same automatic setting back on: **Set Time Zone Automatically**, or **Set Automatically** on the single-switch layout. Confirm the correct local time is restored. If there is a separate **Set Time Automatically** switch, leave it on throughout. If the setting is unavailable or locked, skip the time-zone changes rather than altering restrictions.

If the date doesn't change in the app until you close and reopen it, note that.

**Expected:** The displayed premiere stays on the same calendar day in both time zones, even if the actual broadcast falls on a different local day in Singapore. Only date formatting may change. **Updated** times are real moments and may display differently. Status calculations use UTC days. Keep the device clock correct, and restore automatic time zone. Use the same displayed provider date across details, Watchlist and the fresh CSV. Notification date wording can be checked when an actual alert is observed; do not wait for a provider change to finish this test.


### Purchase checks

Allow about 15 minutes. Use the TestFlight build; purchases are not charged and do not require signing in with a Sandbox Apple Account. If you already have Plus or prefer not to make a test purchase, mark this section Skipped.

**Start:** About shows **Up to 3 shows**, with Simulate Free Tier OFF, and your Watchlist has **exactly three active shows**. Earlier steps may have removed test shows; add untracked test shows such as The Good Place or the long-title show if needed. Existing paused saves do not count toward the active limit. If About shows **Unlimited** because of complimentary beta access, purchases cannot be checked on this device. Mark the checklist **Not applicable** and stop; do not try to remove complimentary access.

1. From the Search tab, try adding **another not-yet-saved show** beyond the three active shows. On the Plus screen, check that Monthly and Annual show a price and period, and that Terms of Use and Privacy Policy open.
2. Tap Monthly or Annual, then **cancel** Apple's purchase sheet. The app stays usable, Plus is not unlocked, and the attempted show is not added.
3. Buy the **same** plan and confirm Apple’s purchase sheet says ‘For testing purposes only’ and ‘You will not be charged’, then complete the purchase. If it does not, stop and ask Janine. After purchase, About shows **Unlimited** and the originally blocked show is added automatically, exactly once. Do not tap its star again.
4. Close NextSeason from the app switcher, reopen it, and check that About still shows Unlimited and all shows remain.
5. In About, tap **Restore Purchases**. Access stays Unlimited and no shows are duplicated.
6. Optionally buy one tip in About. A thank-you appears once, and access is unchanged.

**Expected:** Prices come from Apple's sheet and agree with the app. Cancelling grants nothing; purchasing unlocks Plus without Restore. Tips never unlock features. Report the plan you bought, any error text, and the time. Expiration, renewal, refunds, billing problems, and offline purchase cases are covered in the [separate StoreKit guide](NextSeason-StoreKit-Manual-Test-Script.md); you do not need to test them.

---

## Completion and results

Send your results using the guidance at the top. Record skipped checks and keep the first evidence of a problem even if a retry succeeds.

Restore simulation OFF and any network, time-zone, accessibility, notification, or account settings you changed. Remove only test shows you intentionally added; preserve screenshots, CSVs, and issue notes.
