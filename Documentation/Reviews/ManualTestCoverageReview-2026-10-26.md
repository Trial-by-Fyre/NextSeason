# Manual test coverage review — October 26, 2026

Scope: the beta regression and advanced StoreKit guide/checklist pairs. Claude supplied an independent read-only coverage review with 14 findings; the owner authorized resolving it in this chat. This record summarizes dispositions, not the original transcript and not executed app-test results.

Risk: medium documentation change. Incorrect expected results or setup could conceal behavior or create false failures; no app, payment, persistence, or release configuration is changed here. Verification: check proposed expectations against the relevant implementation, preserve earlier case IDs, compare each document pair after formatting normalization, validate local links/anchors, and review the final diff. No app suite is needed for documentation edits.

| Claude finding | Disposition and coverage |
|---|---|
| 1. First-run accessibility affordances unavailable to upgraded users | Corrected walkthrough 13 to be conditional; OC-18 explicitly covers fresh preferences and large-text example/hint UI. |
| 2. Initial selected tab | Added normal cold-launch checks in walkthrough 1/7; OC-18 covers empty state and deletion of the last show. Notification launches are deliberately separate. |
| 3. Persistent collapsed sections and hidden search matches | Added walkthrough 5 collapse/relaunch/search/expand flow. Current behavior preserves collapse and filters header counts; matching collapsed content must not produce No Matches. Confusing presentation is recorded as a usability finding; no auto-expansion product change was approved or implemented. |
| 4. Reselect Search tab | Added walkthrough 3 detail → tap selected Search tab → results/root → ordinary tab-switch navigation. |
| 5. Offline adding | Added a separate offline-add mini-pass to walkthrough 12 so an earlier failed query does not destroy its starting result. Free capacity/Plus is required. Success with cached/full detail is valid; failure must preserve untracked state and recover on retry. Controlled uncached lookup/save failure evidence remains CV-01/CV-08, not inferred from cached success. |
| 6. Paused-row ordinary UI | Added walkthrough 9 conditional simulation branch covering explanation, blocked Watchlist detail, search, CSV, and removal/Undo pause preservation. Uses temporary rows and restores simulation. |
| 7. Optional deterministic notification tap | Added walkthrough 11 Diagnostics smoke with actual named target, active/paused distinction, fictional-content limitation, and delivery/permission prerequisites. It does not establish production refresh/eligibility. |
| 8. Complimentary beta makes volunteer purchases inapplicable | Added volunteer build/install eligibility and explicit handoff of unavailable purchase evidence to advanced StoreKit testing. Volunteers must not erase or override their grant. |
| 9. Scripted first run | Added OC-18 with independent preference, permission and entitlement preconditions, example search, persistent hint dismissal, empty state, Not Now/Enable allow/deny branches, saved/empty launch routing and cleanup. Added run-order assignment and results row. |
| 10. Spare device can inherit grant | Clarified OC-18 and StoreKit paid-device setup: spare/reinstall does not prove clean entitlement. Strict Free tests confirm settled access with overrides off and no received/synchronized grant. First-run UI can be checked with complimentary access if preferences are fresh; these conditions are not conflated. |
| 11. Ambiguous show labels | Focused StoreKit pass uses N for a new show and P for a saved paused show. Full SK-01–SK-30 retain historical A–G labels with explicit case-specific preparation. |
| 12. Control labels and duplicate links | Focused steps now identify the star and Unlock NextSeason Plus. The beta checklist’s run-order link pair retains a genuine guide link and a checklist link. |
| 13. Complimentary-build cleanup/submission | Added release-coordination steps linked to the existing grant policy: remove dedicated scheme/configuration/xcconfig after distribution, retain recognition/guards, run focused configuration checks before distribution/after cleanup, archive normal Release and select that exact new build for submission. No cleanup or archive performed in this documentation task. |
| 14. Analytics privacy disclosure review | Added release-only comparison of actual Aptabase/SDK collection, event properties, privacy policy, and App Store Connect privacy answers, with evidence requirements and Apple source. No assertion that current disclosures match and no account/policy changes made. |

## Implementation evidence used for expectations

- `NextSeason/Services/AppNavigationCoordinator.swift`: `resolveInitialTab` chooses based on saved identities, except notification routing; `NextSeason/Utilities/TabBarReselectHandler.swift` handles reselection.
- `NextSeason/Utilities/FirstRunPreferences.swift`, `FirstRunCopy.swift`, and `NextSeason/Features/Search/SearchView.swift`: completed first search and dismissed hint are persistent, independent preferences; example query is Severance.
- `NextSeason/Features/Watchlist/WatchlistView.swift`, `WatchlistViewModel.swift`, `WatchlistPreferences.swift`, and `PausedWatchlistSection.swift`: filtered groups retain collapse preferences; paused rows are separate/noncollapsible and retain search visibility.
- `NextSeason/Features/Watchlist/WatchlistTracking.swift` and `NextSeason/Services/TVMazeClient.swift`: tracking can use an already detailed show, otherwise fetches details; network cache behavior can change the outcome of an offline attempt.
- `NextSeason/Features/Debug/DiagnosticsView.swift`: delayed fictional alert uses Lupin if saved, otherwise the most recently added saved identity (repository order); testers must inspect the chosen target.
- `NextSeason/Services/NotificationService.swift` and `NextSeason/Features/Watchlist/WatchlistNotificationPrompt.swift`: successful add may arm the in-app prompt; deferral persists and explicit enable can request permission later.
- `Documentation/Post-MVP/Complimentary Plus Beta Grant.md`: authoritative project cleanup/submission requirements; no new release policy introduced.
- `NextSeason/Services/AnalyticsService.swift` and [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/): normal configured builds may send whitelisted remote events, automated tests suppress transmission; disclosure review includes third-party SDK practices.

## Remaining execution and review limits

The four revised documents address all 14 supplied findings as documentation changes. Claude independently re-reviewed the revised documents and confirmed all 14 initial findings resolved. The follow-up identified one medium and three low documentation issues; their corrections are recorded below. Those latest corrections have been self-reviewed, not independently re-reviewed. Code inspection is not a device pass and agreement with current implementation does not establish product usability or exhaustive completeness.

- Record actual candidate/device/OS/account results. Missing fixtures remain Blocked/Not run; unavailable volunteer branches are Skipped/Not applicable with reasons. No manual test has been marked passed here.
- Background scheduling and natural provider-change notifications remain opportunistic. Diagnostics proves a narrower delivery/routing path.
- Pending approvals, verification uncertainty, stale success, billing states, recovery screens and precise races still require appropriate local/sandbox/custom fixtures or separately recorded automated evidence.
- Production Diagnostics visibility requires applicable release/production evidence; TestFlight alone is insufficient. Submission selection, configuration cleanup and analytics disclosure review remain unperformed release tasks.
- The known Severance title-clipping issue remains open; no acceptance or deferral decision is changed by this documentation update.
- Date checks use a currently displayed future premiere, replacing The Rookie once unsuitable; historical provider dates are not asserted as current facts.

## Follow-up independent review and corrections

The owner supplied Claude’s read-only re-review in this chat. It confirmed code alignment, audience separation, pair synchronization and links; no app tests were run. Readiness was conditional on the medium walkthrough-9 issue. These four follow-up corrections are now documented in both beta formats; StoreKit wording was unaffected.

| Finding | Correction and verification |
|---|---|
| Medium: walkthrough 9 simulation/removal/order could cause false failures or removal of valuable shows | Simulation automatically leaves three oldest shows active. Removed unnecessary removal setup, moved paused checks before main numbered steps, kept simulation on until main step 6, and restricted capacity removal to an active temporary show with completed removal. Valuable-only active slots cause Skipped. Paused removal does not free a slot; active removal does not promote a paused row. Checked against WatchlistAccessReconciler and existing admission policy. |
| Low: walkthrough 12 offline-add capacity/setup/retry | Connected step 4 prepares a slot by removing only an active temporary show if necessary; otherwise the branch is Skipped. Removed the overwritten result setup, retained a separate mini-pass to load the result immediately before going offline, and added numbered recovery step 13 with separate failed/cached-success/skipped outcomes. |
| Low: OC-18 hint has no dismiss control | Step 3 now dismisses by starring a result or opening its details; code’s existing hint callbacks support those actions. |
| Low: test-notification fallback order | Walkthrough 11 and OC-07 now say Lupin if saved, otherwise the most recently added saved show, matching repository.all() reverse dateAdded sorting. The actual named target remains the routing reference. |

Verification after follow-up: normalized beta guide/checklist wording matches, all four documents’ local links/anchors resolve, and formatting checks pass. No device tests, unit/UI runs, configuration cleanup, archives, privacy disclosure approval, or release acceptance occurred. The known accessibility issue and unexecuted candidate coverage remain open. These corrections address the supplied review’s document-readiness condition; they do not mark app cases passed or establish release readiness.
