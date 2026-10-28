# NextSeason — developer/QA acceptance and release coordination

**Updated October 27, 2026. Audience:** developers, technical QA, and the release coordinator. These are not volunteer beta tasks and need not all be performed by Janine. The owner assigns the applicable checks across suitable people/environments and makes release decisions. No app tests or release tasks are pre-marked passed here.

Use the [beta walkthrough](NextSeason-Beta-Regression-Test.md) for everyday behavior and the [advanced StoreKit guide](NextSeason-StoreKit-Manual-Test-Script.md) / [checklist](NextSeason-StoreKit-Manual-Test-Checklist.md) for purchase lifecycle work. Reuse their results instead of repeating them here.

## How to use this list

**AM** retains the earlier **Assigned Manual** IDs so existing notes remain understandable. Each item below is a limited human observation of system/device presentation, not a demand to reproduce every fixed issue manually. Automated tests own exact ordering, internal decisions, persistence errors and timing/failure permutations; see the [engineering coverage notes](../Reviews/BetaRegressionCoverage-2026-10-26.md) for those responsibilities and evidence gaps.

Assign only missing or affected evidence for the candidate. Record **Pass / Fail / Blocked / Not applicable / Not run**, build, device/OS and evidence for each applicable part. An unavailable fixture stays Blocked; an existing unit-test file is not a recorded pass. Do not add new fault-injection code, run full suites, corrupt valuable data, or restart the deferred physical-device launch-loop investigation merely to complete this list.

## AM-01 — Diagnostics presentation smoke check

**Needs:** ordinary development/TestFlight build, saved test show, visible notification permission; About → Diagnostics. Unit/UI tests should cover simulation progression and refresh decision logic. The manual purpose is to see that controls/results are readable and interact with iOS normally.

- [ ] Tap **Schedule Pipeline Test Notification** once and return to the Home Screen within its roughly 5–10-second delay. The action uses a saved show’s name with fictional season data. Record the scheduling result and whether an alert appears (Notification Center is valid evidence). Confirm the real saved show’s status was not replaced. “Scheduled” alone does not establish visible delivery; record permission/Focus restrictions honestly. Reuse volunteer notification-delivery evidence where it establishes the same presentation.
- [ ] In Diagnostics, inspect result text after a normal refresh, open Help, and open/cancel Share Report. Controls/text should be readable and usable. No two-step simulation walkthrough, repeated offline refresh, or manual interleaving exercise is required here. The beta network-recovery result can supply ordinary refresh/reconnect evidence.

A fictional alert does not prove background refresh. If a natural background run is observed during ordinary beta use, inspect its Diagnostics outcome; otherwise record Not observed. Restore changed settings.

## AM-02 — Actual-device notification destinations

**Needs:** physical device, visible alerts and disposable saved data for removed/paused states. Keep foreground, background-return and cold-launch observations distinct across the assigned sessions; reuse the volunteer’s saved-show tap instead of repeating it.

- [ ] Observe a retained alert opening an active saved show’s Watchlist detail, including a cold launch if not already covered. Check that navigation/animation remain usable, respecting Reduce Motion.
- [ ] For a retained alert whose test target was subsequently removed, confirm live lookup opens that show’s Search detail and does not silently re-add it. For a separately available paused target, confirm Watchlist opens without exposing its details. Record unavailable target states Blocked; simulation ends at termination, so it cannot establish a paused cold launch.

Do not recreate the old ten-case routing matrix or try to win races with multiple taps. Controlled/mounted tests cover request ownership; actual-device taps complement them. The [pending-removal tab-switch cancellation observation](../Reviews/WatchlistTabRemovalObservation-2026-10-27.md) still needs rule confirmation and must not be treated as a predetermined failure here.

## AM-03 — Fresh-install and permission screens

**Needs:** disposable installation with genuinely fresh preferences/Watchlist, and separate known system-permission state for permission branches. Reinstall or spare hardware does not establish fresh permission or Free entitlement. For a genuinely Free branch, use a non-granting build with no subscription or stored/synchronized complimentary grant, both overrides OFF, and settled Up to 3 shows. Do not erase real grants; first-run UI can still be inspected with Plus when preferences are fresh.

- [ ] On empty launch, observe Search/welcome and the empty Watchlist. Try an Example searches Severance; completed search hides the example button. Open a result or star it to retire the results hint; confirm the coaching does not reappear on relaunch. Check reachability at normal/large text sizes during this same visit.
- [ ] On the prepared fresh permission fixtures, observe Stay in the Loop after saving. Not Now should not nag on further adding/relaunch, while explicit enable from About can request permission later. On another prepared permission fixture, Enable Notifications reaches Apple’s allow/deny request; tracking remains usable with either choice. Reuse the beta settings-return check rather than repeating it.
- [ ] Confirm normal launch selects Watchlist with saves and Search after all disposable saves are removed and removal completes. The reported brief welcome/Search flash before Watchlist is an open issue, not an accepted transition. Restore settings and record unavailable preparation Blocked.

Automated tests cover individual preference/permission decisions. These checks inspect their first-run presentation and actual system dialogs.

## AM-04 — Upgrade and recovery screens

**Needs:** developer-assisted disposable prior-build stores/recovery fixtures only. Never delete an ordinary tester’s only installation or damage real data. Unit tests cover rollback, locks, corrupt snapshots and exact failure permutations; manual work inspects the UI and a real upgrade.

- [ ] Reuse the beta upgrade smoke, recording its prior build/schema. Compare saved identities/count and a before/after export on a representative earlier installation; inspect ordering/pause state where applicable.
- [ ] With an existing mixed damaged/healthy-row or persistence-open recovery fixture, inspect readable messages, diagnostics/recoverable export and Cancel, including large text/VoiceOver. Exporting/cancelling must not reset data. Check online repair/relaunch if that fixture supports it; unavailable screens remain Blocked, not a new implementation assignment.
- [ ] Only on disposable fixtures, inspect the reset warning and resulting empty usable store/cleared app notifications. In the separate generic crash-loop fixture, inspect non-destructive Retry/diagnostics; a generic loop alone should not offer destructive reset. No manually timed lock/failure battery is required.

## Evidence and cleanup

Keep one result per applicable AM item with partial outcomes/blocked reasons, not a box per theoretical permutation. Preserve existing manual and automated evidence separately. Restore settings/accounts/simulation and retain issue reports. No broad suite or new device-profiling run is authorized by this document.

## Release coordination — owner or assigned release tester

Coordinate these separately from volunteer testing. Assign work across developers/technical QA; the owner makes release decisions. Completing volunteer tests does not by itself complete engineering or production checks.

- [ ] Assign coverage across iOS 18, 26, and 27 and different screen sizes, including both system-design generations. Testers use their existing devices; they should not upgrade/downgrade iOS for this task.
- [ ] Track results against a specific final version/build. After fixes, repeat affected tests and connected flows; broader changes may require another full pass.
- [ ] Assign the applicable AM checks in this document to suitable developers/QA staff; reuse existing candidate evidence and avoid repeating volunteer flows. Do not risk a tester’s only Watchlist.
- [ ] Collect one walkthrough result per assigned device and AM-01–AM-04 where applicable. Reuse overlapping evidence; do not require a second October pass or every timing permutation. Review the [automated coverage notes](../Reviews/BetaRegressionCoverage-2026-10-26.md) separately: existing test code is not a current-candidate pass, and remaining UI/fixture gaps must stay explicit.
- [ ] Before App Store submission, complete the [complimentary-build cleanup and archive checks](NextSeason-StoreKit-Manual-Test-Script.md#storekit-release-coordination); never submit the uploaded granting beta build.
- [ ] Compare the candidate’s actual Aptabase event/property whitelist and SDK collection with the published privacy policy and App Store Connect privacy answers. Record the reviewed build, SDK version/configuration, policy URL/date, and submitted answers; resolve discrepancies before submission. Automated-test builds suppress analytics and cannot establish normal-build collection. This is a release review, not a volunteer manual pass. See [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).
- [ ] Coordinate separately assigned [StoreKit coverage](NextSeason-StoreKit-Manual-Test-Script.md); retain its own results and release gaps.
- [ ] Owner: record actual final unit/UI results for the candidate. Review existing Instruments evidence and its gaps separately; do not restart the deferred physical-device investigation or automatically repeat a profiling battery. Reuse AM-04 for upgrade/migration evidence; do not repeat its steps here.
- [ ] Regenerate the bundled TVDB–TVMaze mapping before release as PROJECT.md requires; verify the candidate actually contains the regenerated artifact. This manual-test document does not regenerate it.
- [ ] Review date/time-zone differences against the intended date model (walkthrough 16). Verify all user-facing error and recovery states and release visibility of diagnostics.
- [ ] Check the final build against screenshots, description, supported OS/device settings, and current feature set. This script intentionally contains no removed theme-switcher test or CSV import test.
