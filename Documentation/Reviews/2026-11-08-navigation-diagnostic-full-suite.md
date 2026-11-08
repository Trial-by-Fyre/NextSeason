# NextSeason nightly tests: FAILED: 2 failing test(s): 1 possibly new, 1 listed known

Run: 2026-11-08 09:56:10 to 10:31:35 (35m 25s), started manually
Revision: 63166f98a92c25cb23e1be590c60b549757e0fe6 on branch main, "Merge branch 'more-post-testing-bug-fixes'", committed 2026-11-07 10:09:00 -0800 (base revision; manual working-copy snapshot includes uncommitted changes)
Toolchain: Xcode 27.0 Build version 27A266a; macOS 27.2 (26B123)
Warning: Manual diagnostic run: tests use a snapshot of the current working copy, including uncommitted changes.
Build: ok in 0m 41s

## iOS 18.6, iPhone 16 Pro (runtime 22G86): FAILED
Elapsed 8m 15s (tests 8m 09s), 783 passed, 1 failed, 1 skipped; xcodebuild exit 65
Result bundle: ios-18.6.xcresult; log: ios-18.6.log; screen at start: unlocked

1. AccessibilityAuditUITests/testWatchlistSearchNoResultsPassAccessibilityAudit()
   Listed known failure (testWatchlistSearchNoResultsPassAccessibilityAudit (unresolved Dynamic Type issues on iOS 18)). Matched by test and environment only; confirm the message matches the recorded symptom.
   History: no previous result for this iOS version
   Message: failed - Accessibility audit found 2 issue(s) on Watchlist search no results: Dynamic Type font sizes are partially unsupported Type: XCUIAccessibilityAuditType(rawValue: 65536) Element: unknown Label:  User will not be able to change the font size of this element  Dynamic Type font sizes are partially unsupported Type: XCUIAccessibilityAuditType(rawValue: 65536) Element: unknown Label:  User will...

## iOS 26.5, iPhone 17 Pro (runtime 23F77): FAILED
Elapsed 9m 37s (tests 9m 30s), 783 passed, 1 failed, 1 skipped; xcodebuild exit 65
Result bundle: ios-26.5.xcresult; log: ios-26.5.log; screen at start: unlocked

1. AccessibilityAuditUITests/testPopulatedWatchlistPassesAccessibilityAudit()
   Possibly new: not in the known-failures list.
   History: no previous result for this iOS version
   Message: failed - Search should return “Severance” (id: search.result.371980). Search field value: “Search TV shows”.

## iOS 27.0, iPhone 18 Pro Max (runtime 24A434): PASSED
Elapsed 16m 45s (tests 16m 41s), 784 passed, 0 failed, 1 skipped; xcodebuild exit 0
Result bundle: ios-27.0.xcresult; log: ios-27.0.log; screen at start: unlocked

## Navigation timeout investigation

`ContentViewNotificationNavigationTests/manualSwitchToSearchReturnsToRoot()` passed on all three iOS versions with the cancellation-only diagnostics included. The intermittent timeout remains unresolved; this run did not exercise the diagnostic failure path. Each version also passed all 737 Swift Testing tests. No additional reruns were performed after the full matrix.

The iOS 26.5 failure occurred during the populated-Watchlist accessibility test's Search setup, before the accessibility audit could run. The expected Severance row did not appear and the search field reported its placeholder. Its cause is unconfirmed; do not classify it as an accessibility violation or a known intermittent failure on this evidence alone.

This manual run used the existing nightly runner's build, simulator reset, and three-version test sequence through a temporary adapter, with a saved snapshot of the working copy instead of a committed checkout. It included the diagnostic change and existing project/scheme edits. Normal scheduled nightly scripts were not modified. The screen was unlocked, unlike the locked November 8 scheduled run; this is an environment difference, not an established cause.

Raw logs, result bundles, and run metadata: [run folder](/tmp/NextSeason-full-nightly-diagnostics/results/runs/2026-11-08_095610). Source snapshot and working-copy patch: `/tmp/NextSeason-full-nightly-diagnostics/`.

## Focused iOS 26.5 reproduction check

On November 8, the owner requested a reproduction check of `AccessibilityAuditUITests/testPopulatedWatchlistPassesAccessibilityAudit()`. Using the same built test bundle and the same iPhone 17 Pro / iOS 26.5 simulator, reset before the check, all three focused repetitions passed (24.203 s, 13.197 s, 13.710 s). The failure was not reproduced; these passes do not establish that it was pre-existing, harmless, or fixed. No app or test code was changed for this check.

The original failure screenshot and accessibility hierarchy show Search still in its idle state with an empty search field after the Try an Example tap. An Apple Intelligence notification banner is visible in the screenshot. The recorded tap coordinates (201.17, 587.33) match the button frame in the saved hierarchy (139, 573.33, 124.33, 28); no misplaced tap is established. Whether the banner or another launch/input timing condition affected delivery is unconfirmed. The accessibility audit itself was never reached in the failing run.

Focused result bundle: [reproduction results](/tmp/NextSeason-26.5-populated-audit-reproduction.xcresult). Original exported evidence: [failure evidence](/tmp/NextSeason-26.5-audit-failure-evidence). No further reruns or broader suite were started.

## Second full nightly matrix, November 8

At the owner's request, repeated the entire nightly matrix using the same saved source snapshot and temporary nightly adapter, without app or test changes between runs. The build passed. Run `2026-11-08_112555` completed from 11:25:55 to 11:56:54 Pacific (30m 59s).

| Version | Passed | Failed | Skipped | Result |
| --- | ---: | ---: | ---: | --- |
| iOS 18.6 | 783 | 1 | 1 | Only the listed Watchlist no-results Dynamic Type accessibility failure |
| iOS 26.5 | 784 | 0 | 1 | Passed, including the populated-Watchlist accessibility test |
| iOS 27.0 | 784 | 0 | 1 | Passed |

The iOS 26.5 Search setup failure did not recur in this full-suite repeat, following three passing focused repetitions. Its cause remains unconfirmed; no fix was applied. The navigation timeout test also passed on all three versions; that intermittent issue remains unresolved. No further reruns were started.

[Second full-run summary](/tmp/NextSeason-full-nightly-diagnostics/results/runs/2026-11-08_112555/summary.md) and [result bundles and logs](/tmp/NextSeason-full-nightly-diagnostics/results/runs/2026-11-08_112555).
