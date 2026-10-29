# Developer/QA checks needing a separate setup

**Recorded October 29, 2026. Status: preparation and evidence gaps, not a manual assignment for Janine's existing phone.** This record accompanies the [executable additional checks](../Post-MVP/NextSeason-Developer-QA-Acceptance.md). Existing AM IDs are retained for traceability.

## Disposition

The owner has no physical device without complimentary Plus and has no instructions or prepared data for AM-04 recovery screens. Do not ask her to erase a grant, uninstall her real Watchlist, corrupt a store, or manufacture a crash loop. Removing these preparations from her personal list does not pass, waive or defer the engineering requirements automatically.

| Area | Preparation / evidence responsibility | Current limit |
|---|---|---|
| AM-03 first-run coaching | Developer prepares a disposable installation with fresh app preferences and Watchlist; inspect welcome/example/results hint at ordinary and large text sizes. A fresh simulator can provide simulator UI evidence. | Complimentary entitlement itself does not prevent inspecting first-run coaching. Reinstalling a used phone does not prove fresh permission or erase a synchronized grant. Do not reset the owner's real installation. |
| AM-03 notification prompts | Establish a known not-yet-requested system permission state and fresh in-app deferral state on a disposable installation. Separate Not Now / later About enable / Apple allow / Apple deny results. | No fresh physical-device permission state was established for this owner pass. Simulator observations must be identified separately from physical-device observations. |
| AM-03 genuinely Free first launch | A normal non-granting build, no paid subscription or stored/synchronized complimentary grant, both overrides OFF; confirm settled Free before the test. | Existing complimentary physical phones do not establish this state. A Free simulator may supply simulator-only evidence. The existing paid/complimentary launch checks remain separate. |
| AM-02 paused cold launch | Deliver and retain an alert while its later-saved target is active; allow an actual subscription to expire with no complimentary access masking it; confirm target paused; terminate and tap alert. | Simulate Free Tier is session-only. It works on a physical TestFlight phone but cannot prepare this cold-launch state. No suitable owner phone is available for this branch. |
| AM-04 recovery presentation | Developer prepares disposable mixed damaged/healthy-row, persistence-open failure and generic crash-loop scenarios, each with written launch/reset directions before assigning manual work. Check readable recovery/diagnostics/export/cancel/reset UI and persistence outcomes. | The old checklist named these states without supplying an executable setup. No runnable owner procedure is currently provided. Do not corrupt real data to reach them. |

## Original AM-03/AM-04 requirements retained for engineering

The text below preserves coverage requirements from the prior document. It is a reference for preparing a future executable procedure, not instructions for Janine to complete unsupported steps. Test-file existence is not candidate-pass evidence; identify missing UI coverage and actual execution results separately.

## AM-03 — Fresh-install and permission screens

**Needs:** disposable installation with genuinely fresh preferences/Watchlist, and separate known system-permission state for permission branches. Reinstall or spare hardware does not establish fresh permission or Free entitlement. For a genuinely Free branch, use a non-granting build with no subscription or stored/synchronized complimentary grant, both overrides OFF, and settled Up to 3 shows. Do not erase real grants; first-run UI can still be inspected with Plus when preferences are fresh.

- On empty launch, observe Search/welcome and the empty Watchlist. Try an Example searches Severance; completed search hides the example button. Open a result or star it to retire the results hint; confirm the coaching does not reappear on relaunch. Check reachability at normal/large text sizes during this same visit.
- On the prepared fresh permission fixtures, observe Stay in the Loop after saving. Not Now should not nag on further adding/relaunch, while explicit enable from About can request permission later. On another prepared permission fixture, Enable Notifications reaches Apple’s allow/deny request; tracking remains usable with either choice. Reuse the beta settings-return check rather than repeating it.
- Confirm normal launch selects Watchlist with saves and Search after all disposable saves are removed and removal completes. The reported brief welcome/Search flash before Watchlist is an open issue, not an accepted transition. Restore settings and record unavailable preparation Blocked.

Automated tests cover individual preference/permission decisions. These checks inspect their first-run presentation and actual system dialogs.

## AM-04 — Upgrade and recovery screens

**Needs:** developer-assisted disposable prior-build stores/recovery fixtures only. Never delete an ordinary tester’s only installation or damage real data. Unit tests cover rollback, locks, corrupt snapshots and exact failure permutations; manual work inspects the UI and a real upgrade.

- Reuse the beta upgrade smoke, recording its prior build/schema. Compare saved identities/count and a before/after export on a representative earlier installation; inspect ordering/pause state where applicable.
- With an existing mixed damaged/healthy-row or persistence-open recovery fixture, inspect readable messages, diagnostics/recoverable export and Cancel, including large text/VoiceOver. Exporting/cancelling must not reset data. Check online repair/relaunch if that fixture supports it; unavailable screens remain Blocked, not a new implementation assignment.
- Only on disposable fixtures, inspect the reset warning and resulting empty usable store/cleared app notifications. In the separate generic crash-loop fixture, inspect non-destructive Retry/diagnostics; a generic loop alone should not offer destructive reset. No manually timed lock/failure battery is required.

## Existing evidence starting points

- First-run/permission decisions: `AppLaunchStateTests`, `NotificationAuthorizationPolicyTests`; inspect actual coverage before claiming a branch is proven.
- Notification navigation/access: `ContentViewNotificationNavigationTests`, `SubscriptionDowngradeTests`, and `IgnoreComplimentaryPlusTests`.
- Recovery/export/reset: `AppLaunchStateTests`, `LaunchFailureTrackerTests`, `WatchlistSnapshotRepairTests`, `WatchlistRecoveryExportReaderTests`, and `PersistenceRecoveryExportPreparationTests`.
- The ordinary update-preserves-Watchlist observation remains in beta walkthrough 1 / AM-04; reuse results on the same candidate rather than repeat it.

No app code, device state, permission state or grants changed for this documentation revision. No app tests or new recovery scenarios ran. Risk: medium documentation clarification; verification checks retained AM requirements, actionable button/field names, local links and release-coordinator references. Recovery and first-run gaps remain for release assessment, not silently accepted limitations.
