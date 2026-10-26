# NextSeason: beta regression and release testing — checklist

Checklist companion to `NextSeason-Beta-Regression-Test.md`, synchronized October 26, 2026. Check steps only after performing them and recording outcomes; a check means covered, not necessarily passed. Keep Blocked/Not run steps unchecked. Use a fresh copy per candidate build.

This is the master test plan, not a record of tests already passed. Choose the section for your assignment:

- [ ] [Beta tester walkthrough](#beta-tester-walkthrough) — the main 30–45-minute walkthrough and follow-up normal use.
- [ ] [October fixes — Janine's manual pass](#october-fixes--janines-manual-pass) — the consolidated October checks, device routing matrix, results sheet and controlled-verification register.
- [ ] [Separate StoreKit testing](NextSeason-StoreKit-Manual-Test-Checklist.md) — purchases, entitlements, lifecycle, tips, and controlled-data cases; use its matching checklist when assigned.
- [ ] [Release coordinator checklist — Janine only](#release-coordinator-checklist--janine-only) — release coverage and checks beyond the walkthrough.

**Updated October 26, 2026.** Janine: use walkthrough 1–16 for broad coverage, the October pass for the recent fixes, and the separate StoreKit guide for applicable purchase/lapse branches. Follow the October run order and record results against one candidate build. This is a plan; no case is pre-marked passed. A printable/checkable copy is [plain guide](NextSeason-Beta-Regression-Test.md).

## Beta tester walkthrough

Thank you for helping test NextSeason before release! A **regression test** means checking that the app's existing features still work after the latest changes. You don't need technical knowledge: follow the steps below and tell me where the app behaves differently from the expected result.

Allow roughly 30–45 minutes for the main walkthrough, plus normal use over the next day or two. Mark each numbered test **Pass**, **Problem**, or **Skipped**. For skipped tests, include the reason. If something goes wrong, keep testing the other areas when possible.

## Before you start

- [ ] 1. Record your iPhone model, iOS version, and NextSeason version/build shown in TestFlight.
- [ ] 2. If you already have NextSeason, note or screenshot your Watchlist **before** updating. Install the latest requested TestFlight build over the existing app.
- [ ] 3. Start with an internet connection. Keep a note of any iPhone settings you change so you can restore them afterward.
- [ ] 4. Record your **starting access state**. Tap **•••** at the top left of Search or Watchlist to open About. Under NextSeason Plus, **Up to 3 shows** means you are on the **Free** tier; **Unlimited** means you have **Plus** (a subscription or complimentary beta access). If you have Plus, test 9 explains how to check the free limit without cancelling anything.
- [ ] 5. Use these temporary test shows, which you can remove afterward: **The Rookie** (ongoing, with an announced premiere), an ended show you know, and **The Woman in the House Across the Street from the Girl in the Window** (long title). On the Free tier, keep to three tracked shows in total until test 9. Live TV information changes, so don't expect a particular premiere date except where a test gives one.
- [ ] 6. **Do not delete the app or reset its data for this walkthrough.** Your Watchlist is stored locally. Clean-install testing is a separately assigned task.

Use the corresponding control if a button's wording differs slightly from this script. If you cannot find a feature, report that rather than guessing.

## 1. Update and launch

- [ ] 1. Open NextSeason after installing the update.
- [ ] 2. Check your previous Watchlist against your note or screenshot.
- [ ] 3. Switch between Search and Watchlist several times.
- [ ] 4. Open a show, go back, leave the app for the Home Screen, and return.

**Expected:** The app opens without crashing or becoming stuck. Your existing shows remain. Navigation works, and returning to the app leaves it usable. No unexpected recovery or reset screen appears.

## 2. Search for shows

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

- [ ] 1. Open **The Rookie** from Search.
- [ ] 2. Scroll to the bottom and back up.
- [ ] 3. Check its title, overview, and any displayed season or episode information.
- [ ] 4. Open an ended show and check its status.
- [ ] 5. Search for `The Woman in the House`, open **The Woman in the House Across the Street from the Girl in the Window**, and check its row in Search and its details for clipped text or overlapping controls.
- [ ] 6. Tap **View on TVMaze**, then return to NextSeason.

**Expected:** Each result opens the correct show. Information is readable, scrolling and back navigation work, and missing dates are presented clearly. The long title wraps rather than overlapping the star or other controls. View on TVMaze opens that show's TVMaze page. An ended show should not misleadingly promise another season.

## 4. Add shows and check the Watchlist

**Start:** any access state. On the Free tier, stay within three tracked shows in total; test 9 covers the limit.

- [ ] 1. Add The Rookie by tapping its empty star in Search.
- [ ] 2. Open Watchlist and find it.
- [ ] 3. Open its details from Watchlist.
- [ ] 4. Return to Search and find the same show again. Its star should be filled.
- [ ] 5. Add your other test shows, from a Search row or from Show Details.
- [ ] 6. Scroll through the Watchlist, including past section headings.

**Expected:** Added shows appear once, their stars reflect their tracked state, and the state agrees between Search, details, and Watchlist. Tapping a filled star never adds a duplicate. Section headings remain readable as rows scroll beneath them. Grouping agrees with the status/date information displayed for each show.

## 5. Search your Watchlist

- [ ] 1. Open the Watchlist search control.
- [ ] 2. Enter part of a tracked show's title.
- [ ] 3. Enter a title or nonsense that does not match your Watchlist.
- [ ] 4. Clear the field and close search.

**Expected:** Matching tracked shows appear. No matches are communicated clearly. Clearing or closing search restores the full Watchlist without removing any shows.

## 6. Remove, Undo and re-add a show

On Watchlist, the star is a toggle. Tapping a filled star starts a removal: the star empties, the row stays in place, and a toast offers **Undo** and **OK** for about five seconds (twenty with VoiceOver). Until the toast ends, tapping the same star again cancels the removal.

- [ ] 1. Tap the filled star of a **temporary test show**. Check that the star empties and the toast appears. Tap the same star again; the star fills and the show stays.
- [ ] 2. Tap the star again, then tap **Undo** in the toast. The show stays, with a filled star.
- [ ] 3. Tap the star again, then tap **OK**, or wait for the toast to disappear. The row leaves Watchlist.
- [ ] 4. Search for that show. Its star is empty. Tap it to re-add the show, then check that it appears on Watchlist once.
- [ ] 5. Swipe left on the same row and delete it. The row disappears immediately. Tap **Undo**; it returns once.
- [ ] 6. Swipe-delete it again and tap **OK** or let the toast expire. Re-add it from Search if you want to keep it.

**Expected:** Star removal is only saved after OK or timeout; until then, Undo or a second star tap keeps the show. Swipe-delete removes the row immediately, and Undo restores it. After a completed removal the show is absent from Watchlist and unstarred in Search; after Undo it is saved once. Other shows are unaffected. A star removal started from Search or Show Details finishes when you next open Watchlist. Janine's extended checks are OC-03–OC-05.

## 7. Keep data between sessions

- [ ] 1. Screenshot or note the current Watchlist.
- [ ] 2. Leave NextSeason and use another app briefly, then return.
- [ ] 3. Close NextSeason from the app switcher and reopen it.
- [ ] 4. If convenient, restart your iPhone and open NextSeason again.

**Expected:** The Watchlist remains intact after each step. Ordinary closing and reopening does not trigger a recovery screen.

## 8. Export your Watchlist

- [ ] 1. Open About (**•••**) and tap **Export Watchlist**.
- [ ] 2. Cancel the share sheet.
- [ ] 3. Confirm that your Watchlist is unchanged.
- [ ] 4. Export again and save the CSV to Files.
- [ ] 5. Open it in Numbers, Excel, or another spreadsheet app, if available.
- [ ] 6. Compare the exported show names and count with your full Watchlist, including any collapsed sections and paused shows.

**Expected:** The share sheet works and canceling is harmless. The CSV contains the **complete stored Watchlist**. It includes show names and TVMaze IDs, with TVDB IDs where available. Titles containing punctuation remain in their correct cells. Export does not require Plus. If you cannot open the CSV, report that part as skipped.

## 9. Free limit and Plus

**Start: Free, with exactly three active shows.** Check About:

- [ ] **Up to 3 shows:** you are already Free. Add or remove temporary shows until exactly three are on your Watchlist.
- [ ] **Unlimited:** do not cancel anything. Open About → **Diagnostics** → **Subscription Testing** and turn on **Simulate Free Tier**. About now shows **Up to 3 shows (simulated)**. If you have more than three shows, your three oldest stay active and the rest move to **Paused — Plus Required**. Nothing is deleted. Remove temporary shows until exactly three are active.

- [ ] 1. Try adding a fourth show from Search.
- [ ] 2. Check that the Plus screen opens and has a usable Cancel control. Catalog, price, legal-disclosure and purchase checks belong in the separate StoreKit tests.
- [ ] 3. Dismiss it without buying and check that your Watchlist still has the same three active shows.
- [ ] 4. Remove one temporary show, then add a different show to return to three.
- [ ] 5. Open Plus from About using **Unlock NextSeason Plus**, then dismiss it.
- [ ] 6. If you turned on Simulate Free Tier: turn it off. About shows **Unlimited** again, paused shows return to their normal sections, and you can add a fourth show.

**Expected:** Adding a fourth show opens Plus without adding the show. Dismissing leaves the original three intact. After removing one, another can be added. Both routes to Plus work. Turning simulation off restores Plus without losing any shows. **End state:** Simulate Free Tier is off.

### Separately assigned purchase testing

Purchase testing has moved to the [StoreKit test guide](NextSeason-StoreKit-Manual-Test-Checklist.md) and its [checklist](NextSeason-StoreKit-Manual-Test-Checklist.md). It is not part of this beta walkthrough.

## 10. Notification permission

- [ ] 1. Open About and note the **Notifications** status (Enabled or Disabled).
- [ ] 2. If NextSeason asks for notification permission during normal use, for example after you add a show, record when it appears and your choice. Do not reinstall just to trigger it.
- [ ] 3. In iPhone Settings → Notifications → NextSeason, turn **Allow Notifications** off. Return to NextSeason.
- [ ] 4. Check Watchlist for the **Notifications Are Off** banner and About for **Disabled**.
- [ ] 5. Tap **Open Settings** on the banner. Turn notifications back on and return to NextSeason.
- [ ] 6. Restore your preferred notification setting.

**Expected:** The banner and About status update when you return from Settings. Open Settings opens NextSeason's notification settings. Denying permission does not cause a crash or repeated system permission requests.

## 11. Background refresh and real notifications — opportunistic

No special steps. Leave **Background App Refresh** on for NextSeason and use the app normally over the next few days. Leave it in the background rather than repeatedly closing it from the app switcher.

- [ ] If a show's **Updated** time changes without you refreshing, or a real show-update notification arrives, note it. For a notification, screenshot it, check that the text is understandable, tap it, and record where the app opens.
- [ ] Report duplicate notifications or a notification for a show you removed.

**Expected:** iOS decides when background work runs, and a notification needs a qualifying show change. **Nothing happening is not a failure**; mark this test skipped unless you observe something.

## 12. Offline and network recovery

Work through the three phases in order. Make sure you have at least two tracked shows.

**Connected**

- [ ] 1. Search for a show and open its details. Return to Search.
- [ ] 2. On Watchlist, use its search to find a tracked show, then clear and close the search.
- [ ] 3. Open a tracked show's details from Watchlist, then return.
- [ ] 4. Pull down on Watchlist to refresh it.

**Offline:** turn on Airplane Mode and make sure Wi-Fi is off.

- [ ] 5. **Search:** search for a title you have not searched for today.
- [ ] 6. **Watchlist search:** search your Watchlist for a tracked show.
- [ ] 7. **Show details:** open a tracked show from Watchlist.
- [ ] 8. **Pull to refresh:** pull down on Watchlist.

**Recovery:** turn off Airplane Mode, or turn Wi-Fi back on, and wait for a connection.

- [ ] 9. **Search:** tap **Try Again** if it is shown, or search again.
- [ ] 10. **Show details:** reopen the show; tap **Try Again** if its Next Season section shows an error.
- [ ] 11. **Pull to refresh:** pull down on Watchlist again.

**Expected:** While connected, everything loads normally. Offline, Search shows an understandable error with Try Again, although a title you searched recently may still appear from cache. Watchlist search still works because it uses saved shows. Show details still shows the saved title, and its Next Season section either shows saved information or an error with Try Again. Pull to refresh shows a brief "Couldn't refresh your Watchlist" notice. No shows are lost, nothing crashes, and no screen stays loading indefinitely. After recovery, Search, Try Again, and pull to refresh all succeed without restarting the app.

## 13. Readability and appearance

- [ ] 1. Check Search, show details, Watchlist, and About in your normal appearance.
- [ ] 2. Switch the iPhone between Light and Dark appearance and revisit those screens.
- [ ] 3. In Settings → Accessibility → Display & Text Size → Larger Text, turn on Larger Accessibility Sizes and drag to the largest size. Check those screens and Plus, if accessible.
- [ ] 4. With large text, check that the Search field stays visible, the Search welcome text and Try an Example button scroll into view, and the first-results hint scrolls with the results. On Watchlist, a "No Matches" or empty-Watchlist message appears below the Notifications Are Off banner rather than on top of it. Also try scrolling, tapping stars, and dismissing sheets.
- [ ] 5. If comfortable, briefly enable Increase Contrast, **Show Borders** (called Button Shapes on iOS 18), Reduce Transparency, and Reduce Motion, checking the main screens after changes.
- [ ] 6. Restore your preferred settings.

**Expected:** Text and controls remain readable and reachable. Important text does not overlap or disappear. Watchlist section headers stay readable. States such as tracked/untracked can be distinguished without relying only on color. Report confusing wording or truncated English text, including on phones using another system language.

## 14. VoiceOver — optional if comfortable using it

- [ ] 1. Enable VoiceOver using your usual method. If unfamiliar with it, skip this test.
- [ ] 2. Navigate Search, read a result, and open its details.
- [ ] 3. Find the star control and check whether its label/action describes adding or removing the show correctly.
- [ ] 4. Navigate Watchlist, its search control, and the available row actions.
- [ ] 5. Open and dismiss a menu or sheet, then turn VoiceOver off if desired.

**Expected:** Controls have meaningful labels and their states are announced correctly. Navigation order makes sense. You can search, track a show, and return without becoming trapped. Report the exact screen/control for any unclear announcement.

## 15. About, links, and credits

- [ ] 1. Open About and check the version and build channel.
- [ ] 2. Under **Help & Legal**, open **Support**, **Privacy Policy**, and **Terms of Use** in turn, returning to the app each time.
- [ ] 3. Under **Credits**, open **Show data provided by TVMaze** and **Search metadata provided by TheTVDB**.
- [ ] 4. On Search results, scroll to the bottom and tap TheTVDB credit.
- [ ] 5. Tap **Rate NextSeason**. Do not submit a review.
- [ ] 6. If the Support page offers an email link, check its destination and cancel without sending.

**Expected:** Support opens the NextSeason support page on getnextseason.com, and Privacy Policy opens the NextSeason privacy policy. Terms of Use opens Apple's standard license agreement, which NextSeason uses. The TVMaze credit opens tvmaze.com, and both TheTVDB credits open thetvdb.com. Support email is addressed to `support@getnextseason.com`. Return navigation works. If an App Store/review link cannot resolve before launch, record the destination and error so Janine can distinguish listing availability from a broken link.

## 16. Time-zone/date check with The Rookie

**Show:** The Rookie, tracked. When this script was updated on October 21, 2026, TVMaze listed its season 9 premiere as **January 6, 2027** (9 PM Eastern). That date comes from TVMaze and has not been confirmed with the network. If the app shows a different date or none, record what it shows. A different date is not a failure; use the date the app shows as the expected date for this test. If no date is shown, mark this test skipped.

- [ ] 1. Note the premiere date shown in The Rookie's details and its Watchlist row.
- [ ] 2. In Settings → General → Date & Time, turn off **Set Automatically** and choose **Singapore**. Return to NextSeason and check The Rookie's details and Watchlist row.
- [ ] 3. Change the time zone to **Honolulu**. Return to NextSeason and check again.
- [ ] 4. Turn **Set Automatically** back on, and confirm the iPhone shows your correct local time.

If the date doesn't change in the app until you close and reopen it, note that.

**Expected:** The premiere stays on the same calendar day in both time zones, even though the episode airs on January 7 in Singapore local time. Only date formatting may change. **Updated** times are real moments and may display differently. Status calculations use UTC days. Keep the device clock correct, and restore automatic time zone. Janine's exact cross-surface checks are OC-10.

## Send your results

Please send your completed test numbers, including passes and skips, so I know what was covered. Use TestFlight feedback or your usual feedback channel with me.

For each problem, include:

- [ ] Test number and a short description.
- [ ] iPhone model, iOS version, and NextSeason version/build.
- [ ] Whether you have free, subscription, or complimentary beta access.
- [ ] Exact steps, including the show title/search text where relevant.
- [ ] What you expected and what happened instead.
- [ ] Screenshot or screen recording if possible.
- [ ] Whether it happens again, and approximately when it occurred.

If the app crashes, loses shows, becomes stuck, or unexpectedly asks to reset local data, report that promptly. Do not reset or reinstall before reporting it.

Example: **Test 5 — Problem.** Searching my Watchlist for “Trek” showed no matches even though Star Trek: Enterprise is tracked. Clearing the field brought it back. Happened twice. [Device/iOS/build; screenshot.]


---

## October fixes — Janine's manual pass

Updated October 26, 2026. Run these cases on the final candidate after the beta walkthrough; do not treat earlier implementation test runs as results for this pass. StoreKit SK-01–SK-30, the recent-fix regression pass, and OC-11 now live in the separate StoreKit documents. OC-11 below is a cross-reference only.

### Run order and result recording

- [ ] 1. **Ordinary app pass:** beta walkthrough 1–16, then OC-01–OC-06, OC-10 and OC-13–OC-14. Use the current candidate on iOS 18 and a current iOS device/simulator; include iOS 26 coverage when available for its different system appearance. Record unavailable environments.
- [ ] 2. **Physical-device notification pass:** OC-07–OC-09 and OC-12. Use a normal Debug/TestFlight launch, without UI-testing or profiling arguments. Diagnostics is hidden in the UI-test configuration. Real device notification delivery and animation cannot be established by mounted unit tests.
- [ ] 3. **Separate purchase assignment:** use the [StoreKit guide](NextSeason-StoreKit-Manual-Test-Checklist.md) or [StoreKit checklist](NextSeason-StoreKit-Manual-Test-Checklist.md); record purchase results there.
- [ ] 4. **Developer-assisted pass:** OC-15–OC-16 and the controlled verification register. These cases require disposable fixtures or existing test seams. There is no ordinary in-app button to corrupt a snapshot, fail a save, or hold a StoreKit read.
- [ ] 5. **Cleanup:** OC-17; record all remaining Blocked/Not run cases and their required next action.

Plan several sessions rather than one sitting. Background delivery and subscription lifecycle cases may need later observation; there is no guaranteed completion time for those portions.

Use **Pass / Fail / Blocked / Not applicable / Not run** for each OC case and each matrix subcase. Record date, build, device/OS, access state, actual show names/IDs, starting state, result and evidence. Mark a box only after executing the step; a box alone is not a pass. Record natural timing attempts as smoke checks unless the intended overlap actually occurred. If a test exposes a failure, preserve its first evidence before retrying; a later pass does not erase it.

**Fixture:** Keep temporary shows A, B, C and an extra D. Record their actual names. For free-cap tests use exactly three active rows; use the simulation instructions in walkthrough 9 or a genuinely free account. Purchase fixtures are covered separately in the StoreKit guide. Export any valuable watchlist before disposable-install or recovery work. Never overwrite the only copy of a tester's store.

### OC-01 — Complete pagination, query replacement and returning from detail

**Environment:** ordinary app; live network. Use a broad title query that actually exposes Load More; record the query rather than assuming any title always has multiple pages.

- [ ] 1. Record the first visible titles and stars. Use Load More until exhausted or until several pages have loaded. Check that earlier rows remain and no identical result is appended twice.
- [ ] 2. Start another Load More, then replace the query with a distinctly different title. When the newer results settle, scroll and wait for any older work to finish.
- [ ] 3. Clear the field during loading, then search again. Repeat rapid query replacement once.
- [ ] 4. Open a result, return, and switch away/back to Search. Repeat while Load More is pending if you can establish that state.

**Expected:** rows, stars, errors and pagination belong to the current query. Clearing stays idle. Returning from detail preserves the displayed outcome and normal pagination rather than unnecessarily restarting it. No stale page or loading flag takes over. A raw API page may produce more than ten displayed hits; that is intentional complete-page retention, not a failure.

**Limit:** live scrolling cannot prove every mapped hit was retained across sparse provider pages. Exact page-remainder, stale completion and mapping-cache checks are in CV-01.

### OC-02 — Try Again followed by a new query or clearing

**Environment:** ordinary app on a disposable test session. Offline/cache behavior varies; use a new uncached query A to obtain an actual failed Search state.

- [ ] 1. Disable networking, search A, and wait for the error with Try Again. Restore connectivity.
- [ ] 2. Tap Try Again, then immediately type a different query B. Wait for B and any older request to finish; inspect results, stars, Load More and alerts.
- [ ] 3. Repeat the setup, but clear the field immediately after Try Again.
- [ ] 4. Retry the same failed query without changing the text once, to confirm ordinary retry still works.

**Expected:** late A success/failure never replaces B or changes its stars/cursor. Clearing leaves idle, without a stale error or permanent loading state. Retrying the unchanged query can recover normally.

**Limit:** if A finishes before the replacement, record an ordinary smoke pass and mark the stale-completion overlap Blocked. Airplane Mode does not reliably hold requests or cause a specific late failure. CV-01 supplies deterministic success, failure, debounce and cache ordering. An old open/track resolution error is a separately recorded follow-up, not proof that retry ownership failed.

### OC-03 — Both removal modes, Undo, OK and timeout

**Environment:** ordinary app; temporary A/B. Undo normally lasts about five seconds, or twenty with VoiceOver. Use the visible toast, not a requirement to hit an exact millisecond.

- [ ] 1. Un-star A on Watchlist. Before expiry, tap Undo. Repeat and tap OK; re-add A, then repeat and let the toast expire.
- [ ] 2. Do the star/Undo cycle from Search results and from Search detail.
- [ ] 3. Swipe-delete A from Watchlist and tap Undo. Repeat with OK and with timeout, re-adding between attempts.
- [ ] 4. Remove A and then B before A's toast expires. Undo B. Reopen Watchlist and relaunch after the operations finish.
- [ ] 5. With VoiceOver enabled, use the row's removal action and check that Undo/OK are reachable and the longer window is usable.

**Expected:** star removal is deferred: the row remains saved during Undo, with its pending state shown; OK/timeout commits it. Swipe-delete removes immediately; Undo restores it; OK/timeout only dismisses the toast. Replacement commits the earlier deferred removal and offers Undo for the latest one. Other shows remain untouched; relaunch agrees with the completed choices. Restored rows retain their original ordering metadata. Opening another detail can cancel a deferred removal under the existing navigation rule; use OC-05/OC-09 for those transitions.

### OC-04 — Undo after the freed slot has already been filled (R10)

**Environment:** free or simulated-free; exactly A–C active. A and replacement D should be easy to find. This can be difficult in the normal Undo interval; do not fake success if the toast expires first.

- [ ] 1. Swipe-delete A. While its Undo toast still exists, add D, then Undo A. Inspect all saved and active rows.
- [ ] 2. Restore the fixture. Swipe-delete A, Undo first, then attempt D.
- [ ] 3. With one free slot, remove/Undo a paused row. Separately remove an active row using its star and try D before confirming the removal.
- [ ] 4. End simulation or restore real Plus as appropriate; inspect the restored paused row.

**Expected:** if D completed first, A returns **paused**, preserving its metadata; D and the other active rows remain active. If Undo took the slot first, D is blocked by the cap. Already-paused rows stay paused on Undo. A deferred star removal does not free capacity until committed. No fourth active row persists. With actual Plus restored, paused rows resume under the normal policy.

**Limit:** if navigation dismisses the toast or the interval ends, record that sequence as Blocked. Use controlled admission/Undo tests (CV-02) for exact competing-operation orders. Do not extend production timing just to obtain a manual pass.

### OC-05 — Real tab selection with a pending Watchlist removal

**Environment:** physical device preferred; ordinary app. This is the real-tap gap from the notification-navigation fix.

- [ ] 1. Open a show detail from Search, leaving that detail on the Search navigation stack.
- [ ] 2. Switch to Watchlist. Un-star temporary B, then tap the Search tab while B's Undo toast is visible.
- [ ] 3. Wait for navigation and saving to settle. Return to Watchlist, then relaunch and check B.
- [ ] 4. Repeat with swipe-delete instead of star removal, and once without any pending removal.

**Expected:** manually choosing Search returns to its results/root. B's Watchlist removal commits when leaving that tab; a reappearing old Search detail must not cancel it. No pending toast remains for the committed operation. Swipe-delete remains deleted. Without a removal, normal return-to-results behavior remains intact.

### OC-06 — Notification permission, deferral and settings return

**Environment:** ordinary app. Fresh permission allow/deny branches require separate disposable installations/devices whose actual system state is not determined; reinstalling is not assumed to reset every permission state.

- [ ] 1. On one fresh fixture, add a show, choose Not Now in the in-app prompt, and add another. Confirm the app does not repeatedly prompt. Use About → Notifications to explicitly enable later.
- [ ] 2. On another fresh fixture, choose to enable, then deny the system request. Use the Watchlist banner/About entry to open notification settings; enable alerts and return.
- [ ] 3. Disable notifications again. Also test authorized notifications with banners/alerts disabled if that system configuration is available. Check About, Watchlist and Diagnostics after return.
- [ ] 4. Restore normal alert settings. Do not expect missed historical updates to replay merely because permission is enabled.

**Expected:** the system prompt is shown only when appropriate; denied/already-decided states lead to Settings. Core tracking remains usable. Banner/status and test-action availability reflect current alert settings. Diagnostics notification actions are disabled when visible alerts are unavailable, so their disabled state is not a failed scheduling attempt. First-discovered changes while notifications are disabled are intentionally consumed; verify that production rule through CV-03, not by a disabled Diagnostics button.

### OC-07 — Diagnostics actions and notification wording (R03, R12, R15)

**Environment:** normal Debug/TestFlight app, alert permission enabled, temporary saved show. Open ellipsis/About → Diagnostics. Record the show identified by each action; Send Test Notification prefers Lupin if saved, otherwise a saved row. Other simulation actions use the repository's first saved row. Do not assume they all choose the same show.

- [ ] 1. Record the real watchlist row's status and date. Tap Run Simulated Update Scenario: note Step 1 and its decision. Tap again: note Step 2 and scheduling outcome. Tap a third time: it should restart at Step 1.
- [ ] 2. Start Step 1 again. Tap Schedule Pipeline Test Notification, then run the next two-step action. The independent delayed runner must not reset the two-step runner; it should still reach Step 2.
- [ ] 3. Schedule another delayed pipeline notification and return to the Home Screen. Observe delivery after the action's roughly five-to-ten-second delay. Separately test Send Test Notification (about five seconds).
- [ ] 4. Return and inspect the real saved row. Tap Force Refresh Now, first online, then on an uncached offline attempt. Reconnect afterward. Open Diagnostics Help and return; share/export diagnostics through its share control and cancel once.
- [ ] 5. Disable alert permission and confirm notification test actions are disabled. Restore it.

**Expected:** step progression and outcome text match the actual action. “Scheduled” means the system accepted the request, not proof it displayed a banner. Simulations use fictional status data without replacing the user's real saved season status. Force Refresh Now refreshes real rows silently; it does not create production alerts. If fetches genuinely fail, the summary must not imply all succeeded. A cached offline response is not a failed-fetch test. Help and report sharing are readable and dismissible.

**Limits:** fictional diagnostics alerts test delivery/routing, not real provider-change eligibility, retry persistence, paused-show exclusion or deduplication. System scheduling rejection cannot be forced by ordinary UI steps; CV-03 covers it. Do not repeatedly run a successful simulation and call its intentional restart a duplicate-production-alert defect.

### OC-08 — Physical-device notification routing matrix

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

**Environment:** physical device; two distinct target shows with retained notifications. Use controlled held lookups for exact response ordering (CV-07).

- [ ] 1. Tap A's notification, then B's as soon as practical. Wait for all loading to settle. Repeat from a state where one target is saved and the other is removed.
- [ ] 2. Start a deferred removal of temporary B from **Search detail**. Before its Undo interval expires, tap a notification that opens another unsaved target's Search detail. Revisit B and relaunch.
- [ ] 3. Separately navigate manually while a notification lookup is still loading; record the outcome without inventing a new precedence requirement.

**Expected:** the latest notification request wins, with no late push back to the earlier target. For step 2, opening the new Search detail currently **cancels** the Search-origin deferred removal, so B stays saved. This is the existing detail-opening rule, different from leaving Watchlist in OC-08. Record any pending product decision against that rule; it is not silently changed by this script. Manual navigation versus an outstanding lookup is a recorded follow-up, not a newly specified acceptance rule.

### OC-10 — Provider calendar dates across screens and time zones (R02, R09)

**Environment:** ordinary app; use **The Rookie** (TVMaze 32938). On October 21, 2026, TVMaze listed its season 9 premiere as 2027-01-06 at 21:00 Eastern (airstamp 2027-01-07 02:00 UTC). That date has not been confirmed with the network. Recheck the date the app shows before testing and record it as the source date; if it has changed or disappeared, use another show with a displayed future premiere rather than this date.

- [ ] 1. Compare the premiere on detail, Watchlist and a fresh CSV export. In the CSV compare the descriptive Next Season column with Next Season Premiere.
- [ ] 2. Turn off Set Automatically in Date & Time and test **Singapore** (UTC+8, where the airing falls on the next local day) and **Honolulu** (UTC−10), keeping the actual clock/date correct. Reopen detail and Watchlist, and reopen About before preparing a new export in each zone.
- [ ] 3. If the Diagnostics fictional alert contains a date, compare that same fictional date across zones separately from the real show's date. Use CV-04 for a controlled production alert matching a known provider date.
- [ ] 4. Turn Set Automatically back on and confirm the correct local time.

**Expected:** a provider premiere date retains its calendar day everywhere; only localized formatting changes. Date Added/Updated are real instants and may display differently locally. Status calculation uses UTC calendar days, so a local evening transition at UTC midnight is not itself a defect. Do not advance the real device clock to force a season transition or subscription expiration.

**Incomplete metadata:** later/unnumbered episodes must not be labeled season premieres. The documented R09 episode-1 pointer change can still reverse airing to announced-undated; defer policy changes. Use CV-04 rather than waiting for a live show to reproduce it. If there is no suitable dated show, record this check Blocked, not Pass.

### OC-11 — Moved to StoreKit testing

The purchase/restore entitlement-ordering steps now live in [StoreKit OC-11](NextSeason-StoreKit-Manual-Test-Checklist.md#oc-11--entitlement-ordering-in-real-purchaserestore-flows-item-1). Record their results in that document. The ID is retained so earlier test records remain understandable.

### OC-12 — Foreground/background refresh and truthful results (R08, R11, R12)

**Opportunistic:** run this alongside other sessions rather than as a scheduled test. iOS decides when background work runs.

**Environment:** physical device; normal launch, network available, Background App Refresh enabled. Record Low Power Mode, Focus and alert presentation settings rather than assuming background scheduling or visible banners are guaranteed.

- [ ] 1. Leave NextSeason in the background normally for a later observation; do not force-quit it while testing scheduled background work. Reopen and inspect Diagnostics' last background time, fetch result and notification decision.
- [ ] 2. Return repeatedly within a short interval; verify normal use remains responsive. Foreground refresh is throttled to about fifteen minutes, but entitlement preparation still runs; pull-to-refresh and Force Refresh Now bypass that refresh throttle silently.
- [ ] 3. Turn Background App Refresh off, use Search/Watchlist, then restore the setting. Separately test offline force refresh, reconnect and retry.
- [ ] 4. Compare a background run's diagnostics, persisted Watchlist changes and any actual alerts. Record partial failures honestly. Leave a suitable installation unused for a natural long-absence follow-up only if available; use CV-05 for deterministic multi-day/month gaps.

**Expected:** no lost shows, no alert burst from silently resumed rows, and no success wording concealing a total fetch failure. Scheduled time is an earliest hint, not an appointment. No background sample means **Not observed**, not a pass or a failure. A test banner scheduled for five seconds later does not prove the app performed a background fetch. Neither pull-to-refresh nor Force Refresh Now proves automatic notifying refresh behavior.

### OC-13 — Full export after changes, filtering, pausing and offline use

**Environment:** ordinary app; mixed active/paused shows if available, including punctuation/non-ASCII/long titles.

- [ ] 1. Open About and export; save a CSV to Files. Compare the complete saved count and names, IDs, dates and URLs. Missing TVDB IDs are allowed when no mapping exists.
- [ ] 2. Collapse Watchlist sections, export again, and confirm collapsed and paused rows are included. Cancel the share sheet once; no saved state should change.
- [ ] 3. Add/remove a temporary show, close and reopen About to prepare a fresh export, and compare the new file. Save exports separately because the normal filename can repeat within a day.
- [ ] 4. Repeat offline using saved rows. Reopen the resulting CSV in a spreadsheet application. Record unavailable viewers or induced export errors as Blocked where appropriate.

**Expected:** export is available without Plus, represents every stored show at preparation time, retains correct CSV cells/Unicode and date-only values, and does not mutate the watchlist. About prepares an export when opened; do not assume an already-open ShareLink rebuilds itself after later mutations. CSV is an export only; there is no import/restore-from-CSV feature.

### OC-14 — Accessibility, appearance and known clipped-title check

**Environment:** iOS 18 and a current OS, different screen sizes where available; Light/Dark, default text and largest accessibility text. Restore preferences afterward.

- [ ] 1. In particular, inspect **Severance** detail on iPhone 16/iOS 18.6, or record that exact environment unavailable. Check the title/header at large text sizes and capture any clipped text. Also check long titles on the devices available.
- [ ] 2. With VoiceOver, complete Search → detail → add, Watchlist search, deferred Undo/OK, row removal action, paused row, About export, Plus purchase cancellation/restore and notification settings.
- [ ] 3. Inspect alerts, recovery screens (OC-16), Diagnostics outcome text and Help for clipped buttons, unreachable controls and overlapping sheets. Repeat important controls with Reduce Motion/Increase Contrast and other preferred accessibility settings.
- [ ] 4. On a device using a non-English language or another calendar/locale, check title/date/price layout and readable fallback text; untranslated English alone is not a new localization promise.

**Expected:** meaningful labels/states and actionable focus order, reachable controls at large text sizes, readable toast/section headers on iOS 18 and the newer glass appearance. The known title-clipping audit failure remains open; a prior pass on iPhone 16 Pro does not clear the iPhone 16 finding. Record it as an existing issue if reproduced, and report different failures separately. Do not mark accessibility passed merely because that failure predates these fixes.

### OC-15 — Review prompt and diagnostics boundaries

**Environment:** developer-assisted, disposable version/defaults fixture for deterministic eligibility; ordinary app for visual smoke checks.

- [ ] 1. Verify About's Rate NextSeason link opens the intended listing/review destination without submitting a review.
- [ ] 2. Run Diagnostics test notifications and simulated pipelines. They must not consume the production per-version review eligibility.
- [ ] 3. With a controlled **production** qualifying notification, return to active use and inspect review-request eligibility/attempt evidence. Verify at most one app request attempt per marketing version and preserved state across restart.

**Expected:** user navigation stays usable. Apple does not display the in-app review request in TestFlight; use a development build for visual presentation checks. In a shipping app Apple controls whether it appears, so absence alone is not a failure or proof of eligibility. See [Apple’s review-request guidance](https://developer.apple.com/documentation/storekit/requestreviewaction). Use ReviewPromptCoordinatorTests/ReviewPromptStoreTests and recorded attempt state to establish eligibility and deduplication; do not repeatedly reinstall or send fictional alerts to force Apple's UI. App Store listing availability is recorded separately.

### OC-16 — Recovery, upgrade and damaged-row presentation

**Environment:** developer-assisted **disposable** installation/store. These are planned checks, not an instruction to restart the deferred physical “NextSeason Closed Repeatedly” investigation or corrupt a valuable store. No new fault-injection code is required by this document; use existing test seams or mark the UI fixture Blocked.

- [ ] 1. Install the candidate over a representative earlier TestFlight build with known saved identities, ordering and pause states. Export/compare before and after. Do not reinstall for this upgrade check. Record the source build/schema and any documented pre-release fresh-store exception.
- [ ] 2. In a controlled readable store, damage one saved status snapshot while retaining its identity and another healthy row. Launch, inspect the mixed list, export, repair online and relaunch. See CV-08 for the exact persistence-boundary tests.
- [ ] 3. Show the persistence-open recovery fixture. With developer assistance, also exercise a readable store briefly locked as SwiftData closes: when the lock clears within the two-second reader timeout, recoverable shows must not be misreported as missing. Record this branch Blocked if the lock fixture is unavailable. Inspect “Couldn't Open Your Watchlist”, diagnostics export, recoverable-Watchlist export and Cancel. Confirm exporting/cancelling does not reset anything; compare recoverable identities, allowing explicitly incomplete recovery exports.
- [ ] 4. Only on that disposable fixture, confirm Reset Local Data; check the warning, empty new store, cleared pending/delivered app notifications and ability to add again. Subscription/complimentary access is not the watchlist reset target. CSV export is not automatically imported.
- [ ] 5. Exercise controlled unreadable/zero-row export, export failure, reset failure and failure after a successful reset using existing fixtures. Inspect honest errors, available retry/cancel actions, share sheet and large-text/VoiceOver behavior.
- [ ] 6. Inspect the existing generic crash-loop recovery fixture separately: diagnostics and non-destructive Retry are available; destructive store reset is not offered merely because a generic launch loop was detected.

**Expected:** an individual damaged snapshot does not hide healthy rows, identity or the rest of the list. Repair is silent and durable; failures do not silently erase stored data. Recovery clearly separates retry from irreversible reset and never claims an incomplete export is complete. Record any unavailable fixture as Blocked. A successful automated reader fixture is not a visual recovery-screen pass, and upgrade compatibility needs its actual prior-store fixture.

### OC-17 — Cleanup and final record

- [ ] 1. Turn simulation off, restore network/time zone/accessibility/notification/background settings and any changed test account or scheme settings. Disable purchase errors, pending/interrupted/billing-failure simulations left by testing.
- [ ] 2. Keep completed case outcomes, original failures, screenshots, CSVs and diagnostics under the tested version/build. List partial matrix rows explicitly; do not collapse “blocked” into “passed”. Remove only temporary shows you intentionally used.
- [ ] 3. Record which full unit/UI runs the owner actually performed, on which OS/build and with which remaining failures. This script does not run or authorize a suite automatically.
- [ ] 4. List remaining sandbox/device checks, known accessibility issue, provider-dependent gaps and accepted limitations. Do not restart deferred investigations or profiling batteries simply to fill a checkbox.

### October result sheet

Use a separate copy per candidate. Add rows for N1–N10 and every OS/environment used. Record subscription-plan results in the separate StoreKit documents.

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
| OC-11 Moved to StoreKit document | See separate results | | |
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
| CV-06 Access (moved) | See the [StoreKit controlled verification register](NextSeason-StoreKit-Manual-Test-Checklist.md#controlled-verification-register). Record access evidence there. | ID retained for earlier records. |
| CV-07 Navigation (R14, item #2) | Held A lookup finishes after B; B remains selected. Mounted ContentView preserves Search detail after tab effects, including a held removal commit. Deferred Watchlist removal persists; paused/cold-launch cases reconcile access before routing. These tests complement, not replace, OC-05/OC-08 real-device taps/animation. | ContentViewNotificationNavigationTests; AppNavigationCoordinatorTests; NavigationUITests; NotificationSearchNavigationReview-2026-10-19.md |
| CV-08 Persistence/export (R01/R13) | Force insert/delete/pause/reactivation/refresh/Undo/retry-restoration save failures: rollback and later writes never commit discarded state; inspect fresh contexts and on-disk restart where appropriate. Damage one snapshot: identity survives, mark precedes exposure, repair silently baselines and clears only after successful save. Marks survive absence/Undo, retry failure and restart; re-added rows do not inherit old marks; not-found repair terminates appropriately. Recovery exports retain healthy and damaged identities, tolerate a brief database lock that clears within the two-second reader timeout, and handle unreadable stores honestly. | SwiftDataWatchlistRepositoryRollbackTests; WatchlistSnapshotRepairTests; WatchlistRecoveryExportReaderTests; PersistenceRecoveryExportPreparationTests; NextSeasonSchemaTests; AppLaunchStateTests |
| CV-09 Tool evidence (R15–R17) | Simulation Step 1/2/reset and failed retry match outcome; missing/empty/malformed trace, HAR, CPU or console evidence cannot count as performance readiness. Capture lifecycle cleanup is covered by focused script tests. Historical incomplete sessions remain incomplete; run no new device-profiling battery just for this script. | DiagnosticsSimulationsTests; Scripts/tests; 2026-10-16-profiling-investigation.md |

### Source and decision references

- [ ] [Original feature-area review](../Reviews/2026-10-12-feature-area-review.md), [approved decisions/analysis](../Reviews/2026-10-12-feature-area-review-analysis.md), [R03/R13 matrix](../Reviews/2026-10-12-r03-r13-behavior-matrix.md), [R08/R11 matrix](../Reviews/2026-10-13-r08-r11-behavior-matrix.md).
- [ ] [Entitlement ordering](../Reviews/EntitlementCheckOrderingReview-2026-10-19.md), [notification navigation](../Reviews/NotificationSearchNavigationReview-2026-10-19.md), [Search retry ownership](../Reviews/SearchRetryOwnershipReview-2026-10-19.md), [remaining follow-ups](../Reviews/2026-10-19-follow-ups.md), [known accessibility failure](../Reviews/Known-Test-Failures.md).
- [ ] [Free-tier simulation](FreeTierSimulation.md). Diagnostics labels and behavior checked against the current app implementation on October 19, 2026; the walkthrough, About links and time-zone instructions were rechecked on October 21, 2026. These are instructions, not test results.
- [ ] [TVMaze API](https://www.tvmaze.com/api) documents update-map windows and propagation caching; deterministic timing/window proof uses fixtures. [Apple sandbox account controls](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/) support the assigned billing scenarios; record actual account timing and available controls rather than assuming production durations.

---

## Release coordinator checklist — Janine only

The walkthrough provides broad user-facing regression coverage. Completing it does not, by itself, complete every engineering or production check in the roadmap.

- [ ] Assign coverage across iOS 18, 26, and 27 and different screen sizes, including both system-design generations. Testers use their existing devices; they should not upgrade/downgrade iOS for this task.
- [ ] Track results against a specific final version/build. After fixes, repeat affected tests and connected flows; broader changes may require another full pass.
- [ ] Assign a clean install on a spare device or controlled test environment, including empty Watchlist, initial launch, and first-run permission allow/deny paths. Separately verify upgrade from earlier TestFlight builds with existing data. Do not risk a tester's only Watchlist.
- [ ] Complete the applicable OC-01–OC-17 cases and N1–N10 with individual outcomes; OC-11 results belong in the separate StoreKit document. Use the controlled verification register to distinguish fixture evidence from manual passes.
- [ ] Coordinate separately assigned [StoreKit coverage](NextSeason-StoreKit-Manual-Test-Checklist.md); retain its own results and release gaps.
- [ ] Test persistence recovery and crash-loop prevention using controlled failure injection, including diagnostics export, readable-Watchlist export, reset consequences, and successful relaunch. Do not ask ordinary testers to corrupt storage or trigger resets.
- [ ] Owner: record actual final unit/UI results for the candidate. Review existing Instruments evidence and its gaps separately; do not restart the deferred physical-device investigation or automatically repeat a profiling battery. Perform upgrade/migration checks with representative earlier stores (OC-16).
- [ ] Regenerate the bundled TVDB–TVMaze mapping before release as PROJECT.md requires; verify the candidate actually contains the regenerated artifact. This manual-test document does not regenerate it.
- [ ] Review date/time-zone differences against the intended date model (OC-10). Verify all user-facing error and recovery states and release visibility of diagnostics.
- [ ] Check the final build against screenshots, description, supported OS/device settings, and current feature set. This script intentionally contains no removed theme-switcher test or CSV import test.

Originally prepared from the October 7 readiness roadmap and audited README; consolidated October 19, 2026 against the current code and review records. Exact OS/Xcode controls and fixture availability must be recorded on the tested candidate. Country-specific streaming availability, CSV import and new status policies are outside this script. The deferred physical-device “Closed Repeatedly” investigation remains deferred.
