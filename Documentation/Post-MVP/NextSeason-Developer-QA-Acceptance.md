# NextSeason — additional manual checks and release coordination

**Updated October 29, 2026.** Use this after the beta walkthrough and StoreKit pass. Reuse results from the same build; do not repeat a check just because it appears in another document. **AM** means **Assigned Manual**; the numbers are retained for earlier notes.

## Owner AM assignment — complete

**October 29, 2026:** Janine reports AM-01 and AM-02 completed and closes her AM assignment. No further AM testing is assigned to her for this pass. This is owner-reported completion, not an independent rerun; the exact tested build/device/OS and individual optional-branch outcomes were not supplied with this completion note.

AM-03 and the prepared recovery portions of AM-04 were not executed as part of this assignment. Their separate engineering evidence gaps remain in the [preparation record](../Reviews/DeveloperQAPreparation-2026-10-29.md); they are not additional tasks for Janine. Existing reported bugs remain open. The procedures below are retained for reference and future candidate use.

## Task disposition

| Item | Your task |
|---|---|
| AM-01 | Completed by Janine, October 29, 2026. |
| AM-02 | Completed by Janine, October 29, 2026; no additional branch results inferred. |
| AM-03 | No task on your current phone. Separate fresh-install/permission preparation belongs to the developer. |
| AM-04 | No further owner task for this pass. Reuse the beta update result where recorded; recovery preparation remains separate developer work. |

Record **Pass / Problem / Skipped**, the build/device/iOS and reasons for any skipped part. The [separate preparation record](../Reviews/DeveloperQAPreparation-2026-10-29.md) keeps the first-run, recovery and paused cold-launch evidence gaps visible. Those are not extra boxes for you to attempt here.

## AM-01 — Check Diagnostics on your phone

**Start:** online, at least one saved show, your existing TestFlight/development installation. Open About (**•••**) → **Diagnostics**.

- [ ] Under **Beta actions**, tap **Force Refresh Now** and wait for **Refreshing…** to finish. This updates the real Watchlist silently; no notification is expected.
- [ ] In **Beta validation**, above the action buttons, read **Last foreground refresh**, **Last foreground fetch result**, and **Last foreground notification decision**. Check that the time/results are visible, readable and understandable. Note confusing wording; you do not need to interpret every technical count or repeat the offline tests.
- [ ] Tap the **question-mark** button at the top left (VoiceOver calls it **Diagnostics help**). Check that the help can be read/scrolled, then return to Diagnostics.
- [ ] Near the bottom, tap **Share Report**, then cancel the iOS share sheet. Verify you return to a usable Diagnostics screen.

**Pipeline notification check, if not already covered:** with notification alerts enabled, tap **Schedule Pipeline Test Notification** once and go to the Home Screen within its roughly 5–10-second delay. Leave any arriving alert in Notification Center until you are ready. Return to Diagnostics and read **Last simulation** in **Beta validation** for the result; confirm the real saved show's status was not replaced. Record an actually delivered alert separately from a scheduling-success message. If Focus/permission prevents visible delivery, note that rather than treating scheduling as proof it arrived.

**Expected:** the controls work, results/help are readable, and cancelling Share Report changes no saved shows. The pipeline action uses fictional season data; it does not prove that iOS scheduled a real background refresh. No two-step **Run Simulated Update Scenario** exercise is required.

## AM-02 — Tap retained notifications on your physical phone

**Start:** alerts enabled and at least one active saved show. Use only a show you are willing to remove for the removal check. Reuse matching beta walkthrough 11 or StoreKit SK-27 results on this build.

### First, create a notification you can tap later

In About → Diagnostics, tap **Send Test Notification**, note the named target in its result, tap **Done**, and go to the Home Screen before the roughly five-second delay ends. The target is **Lupin if saved, otherwise your most recently added show**. Let the alert arrive. **You do not have to tap it immediately:** leave it in Notification Center while you prepare the relevant check below. Send a new alert for each check.

### Active saved show

- [ ] Leave the target saved and active, then tap its notification. Its Watchlist details should open. If you already have that result, reuse it. For an additional closed-app observation, create another alert, close NextSeason completely, then tap the alert; the same active show's details should open.

### Removed show

- [ ] Create a fresh alert and leave it untapped. In NextSeason, remove its target and finish removal with **OK** or let the Undo toast expire. Then open Notification Center and tap the retained alert. The show's **Search details** should open without adding it back to Watchlist. If provider data cannot load, the app should explain that without crashing. If the selected target is valuable, skip this removal check instead of deleting it.

### Paused show, without closing the app

- [ ] With real Plus access and more than three saved shows, create an alert for a target **outside the three oldest saves**. After the alert arrives, leave it untapped, return to About → Diagnostics → Subscription Testing, and turn **Simulate Free Tier ON**. Confirm the target now appears under **Paused — Plus Required**. Tap the retained notification from Notification Center: NextSeason should show Watchlist without opening paused details. Turn Simulate Free Tier **OFF** afterward.

**If the target cannot safely be paused:** the three oldest saves remain active. If the selected target is one of them, do not remove valued shows or rearrange your real data to force the case; mark only this paused check Skipped and record the target/reason.

**“Simulate Free Tier” is a switch on your physical TestFlight phone, not the iPhone simulator on your Mac.** Keep NextSeason running in the background during this paused check. Closing the app turns the switch OFF. A paused **cold launch** requires actual subscription expiration without complimentary access and is tracked separately for developer preparation; it is not an additional task on your complimentary phone.

## AM-03 — First-run screens: separate developer preparation

**No action required on your existing phone.** Do not uninstall NextSeason, erase a grant or reset your real Watchlist to make it look new.

Complimentary access does not itself prevent testing first-run coaching. A developer can prepare a separate fresh simulator/installation for those screens and known notification-permission states. Genuinely Free first-launch evidence is a separate branch, and simulator results must be labeled as such. The [preparation record](../Reviews/DeveloperQAPreparation-2026-10-29.md) retains these requirements and their missing evidence; this document does not count them as completed.

## AM-04 — Ordinary update result; recovery checks are developer work

**Build that adds Watchlist broadcaster names:** testers delete and reinstall instead of updating, so there is no supported in-place update result for that candidate. Record AM-04 as not applicable for it rather than reusing an earlier result, and install it fresh on your own phone before AM-01 as well.

- [ ] If beta walkthrough 1 already checked that an update preserved your Watchlist on this candidate, reference that result and the previous/new build numbers if known. **No additional action is needed.** If you have not checked an update yet, record that evidence as missing; do not uninstall/reinstall to imitate an update.

The remaining AM-04 material concerns deliberately damaged data and recovery screens. It is **not a procedure for you to perform**: the earlier version did not supply a safe way to create those states. Their requirements remain in the [developer preparation record](../Reviews/DeveloperQAPreparation-2026-10-29.md). A developer must supply a disposable setup and actual instructions before assigning any manual recovery work.

## Evidence and cleanup

Keep results with your beta/StoreKit notes, including any reused results and skipped reasons. Restore Simulate Free Tier OFF and any settings you changed. You do not need another full walkthrough or to manufacture background execution, permission prompts, damaged data, or a crash loop for this document.

## Release coordination — owner or assigned release tester

Coordinate these separately from volunteer testing. Assign work across developers/technical QA; the owner makes release decisions. Completing volunteer tests does not by itself complete engineering or production checks.

- [ ] Assign coverage across iOS 18, 26, and 27 and different screen sizes, including both system-design generations. Testers use their existing devices; they should not upgrade/downgrade iOS for this task.
- [ ] Track results against a specific final version/build. After fixes, repeat affected tests and connected flows; broader changes may require another full pass.
- [ ] Assign AM-01/AM-02 and reuse AM-04’s ordinary upgrade result. Separately assign the [AM-03/recovery/paused cold-launch preparations](../Reviews/DeveloperQAPreparation-2026-10-29.md) to a developer; no unavailable setup is Janine’s personal manual task. Keep missing evidence explicit and do not risk a tester’s only Watchlist.
- [ ] Collect one walkthrough result per assigned device, the applicable executable AM checks, and the separately recorded first-run/recovery evidence or preparation gaps. Reuse overlapping evidence; do not require a second October pass or every timing permutation. Review the [automated coverage notes](../Reviews/BetaRegressionCoverage-2026-10-26.md) separately: existing test code is not a current-candidate pass, and remaining UI/fixture gaps must stay explicit.
- [ ] Before App Store submission, complete the [complimentary-build cleanup and archive checks](NextSeason-StoreKit-Manual-Test-Script.md#storekit-release-coordination); never submit the uploaded granting beta build.
- [ ] Compare the candidate’s actual Aptabase event/property whitelist and SDK collection with the published privacy policy and App Store Connect privacy answers. Record the reviewed build, SDK version/configuration, policy URL/date, and submitted answers; resolve discrepancies before submission. Automated-test builds suppress analytics and cannot establish normal-build collection. This is a release review, not a volunteer manual pass. See [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- [ ] Coordinate separately assigned [StoreKit coverage](NextSeason-StoreKit-Manual-Test-Script.md); retain its own results and release gaps.
- [ ] Owner: record actual final unit/UI results for the candidate. Review existing Instruments evidence and its gaps separately; do not restart the deferred physical-device investigation or automatically repeat a profiling battery. Reuse the ordinary update result in AM-04; separately assess earlier-schema migration/recovery evidence where needed. Do not treat an ordinary update smoke check as proof of recovery behavior.
- [ ] Regenerate the bundled TVDB–TVMaze mapping before release as PROJECT.md requires; verify the candidate actually contains the regenerated artifact. This manual-test document does not regenerate it.
- [ ] Review date/time-zone differences against the intended date model (walkthrough 16). Verify all user-facing error and recovery states and release visibility of diagnostics.
- [ ] Check the final build against screenshots, description, supported OS/device settings, and current feature set. This script intentionally contains no removed theme-switcher test or CSV import test.
