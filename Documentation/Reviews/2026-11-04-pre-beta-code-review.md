# Pre-beta code review — November 4, 2026

Review only: no application code was changed. Findings below are based on tracing
the current source and inspecting relevant tests and existing review dispositions.
They have not been independently reproduced in the running app in this review.

The review concentrated on app composition/recovery, persistence, purchase and
entitlement handling, watchlist admission/removal/reactivation, refresh and
notification decisions, search, show detail, mapping maintenance, and export.
This is not a guarantee that every possible defect has been found.

## Important — fix before release

### R1. Search and Show Detail can reactivate a paused show without a silent baseline

**Locations:** `NextSeason/Features/Watchlist/WatchlistTracking.swift:80–94`,
`NextSeason/Persistence/SwiftDataWatchlistRepository.swift:80–85`.
Compare `NextSeason/Features/Watchlist/WatchlistViewModel.swift:269–284` and
`NextSeason/Services/WatchlistRefreshService.swift:417–436`.

The Watchlist reactivation path marks the saved row for silent catch-up before
unpausing it, and starts a fresh catch-up afterward. Search and Show Detail use
the ordinary `toggle` → `add` route without the `reactivating` argument or
`willReactivate` callback. The repository nevertheless recognizes a paused row
and reactivates it. Those entry points therefore bypass the mark.

A concrete failure sequence is:

1. A saved show is paused, and another show is removed to free a slot.
2. Search or Show Detail has older show data, for example a cached response saying
   the show is returning without a date.
3. The user taps its empty star. The row becomes active with that older status and
   no catch-up mark.
4. A notifying refresh gets the current scheduled premiere. The ordinary change
   detector sends a premiere notification even though that news predates resuming
   tracking. The Watchlist entry point would absorb it silently.

**Why release priority:** avoiding historical alerts is an existing behavior,
explicitly protected in the Watchlist path. The same saved show should have that
protection regardless of which screen resumes it. This does not indicate lost
watchlist data or an incorrect charge.

**Suggested fix:** make detecting and marking an existing paused row part of the
shared reactivation operation used by every entry point. Mark before the write;
retain the mark after a failed fetch so an ordinary refresh can complete the
baseline. Preserve the row identity and free-tier admission checks.

**Focused verification needed:** exercise Search and Show Detail separately with
older cached detail versus current bypass-cache detail; confirm no historical
alert, then confirm a genuinely later change does notify. Also cover a failed
initial catch-up and removal during the detail fetch. Existing Watchlist-screen
reactivation tests do not establish these other routes.

## Less important — can wait until V2

### R2. Mapping replacement is two separate commits

**Location:** `NextSeason/Services/ShowIDMapping/ShowIDMappingDatabase.swift:144–158`.

`applyMapping` deletes the previous mapping and then inserts the replacement,
without a SQLite transaction. If insertion fails, or the process ends between
the statements, a previously searchable show loses its mapping. Search filters
out unmapped results. A later successful mapping refresh can repair it, but
the refresh failure does not preserve the previous row.

**Suggested fix:** wrap the delete and replacement in one transaction, rolling
back on failure. A focused test should force replacement failure after deletion
and verify that the original mapping remains. This concerns the replaceable
search database, not the user's saved watchlist, which is why I would defer it.

### R3. Network cancellation is converted into an ordinary refresh failure

**Locations:** `NextSeason/Services/TVMazeClient.swift:190–194`,
`NextSeason/Services/TheTVDBClient.swift:197–201`,
`NextSeason/Services/WatchlistRefreshService.swift:470–502`.

Both clients wrap every `URLError` as a provider network error, including
`.cancelled`. The refresh service's `catch is CancellationError` then cannot
recognize that cancellation. Its general failure branch counts a failed show
and continues the loop; there is no cancellation check at the top of that loop.
An expired background refresh can consequently keep attempting remaining
shows and logging network errors after its work was cancelled.

**Suggested fix:** normalize task cancellation at the client boundary and check
cancellation between shows. Preserve real network-error reporting. Verify that
cancelling a held request stops the pass without fetching subsequent shows.
Search already guards much of its state against cancelled tasks, reducing the
visible impact there.

### R4. Custom motion does not consult Reduce Motion

**Locations:** `NextSeason/Features/Watchlist/UndoToast.swift:96–103,151`,
`NextSeason/Features/Watchlist/WatchlistView.swift:440`, and animated row changes
in `NextSeason/Features/Watchlist/WatchlistViewModel.swift`.

The toast explicitly combines fading with a vertical offset, and list changes
request animation unconditionally. No app source reads the Reduce Motion
preference. VoiceOver timing is handled separately and does not cover this
setting.

**Suggested fix:** use the accessibility preference to choose an opacity-only
toast transition and reduce custom movement in list changes. Verify on a device
with Reduce Motion on and off; this review did not establish how much animation
the system already suppresses in each supported iOS version.

### R5. Reduce the effort needed to understand the largest files and their assumptions

**Locations:** `NextSeason/Features/Watchlist/WatchlistView.swift` (701 lines),
`NextSeason/Services/Purchases/PurchaseService.swift` (749), and
`NextSeason/Services/WatchlistRefreshService.swift` (695).

These files each collect several responsibilities. That makes changes harder
to review, but their size alone is not a release defect. In V2, extract coherent
pieces when touching the area: Watchlist presentation, purchase diagnostics/test
controls, or refresh outcome formatting are reasonable candidates. Avoid a large
pre-release restructuring solely to satisfy a line-count guideline.

The code is already well commented. Additional comments should be selective:

- At `WatchlistTracking.add`, document that final admission and persistence rely
  on repository implementations not suspending internally. The current comment
  explains this locally; put the same contract on `WatchlistRepository` so future
  implementations cannot easily miss it.
- Where comments cite `R03`, `R09`, `R12`, or decision IDs, include the relevant
  repository document path when the behavior is surprising. Existing prose is
  useful, but finding the associated acceptance decision currently takes a search.
- Explain the SQLite destructor sentinel used by `bindText` in
  `ShowIDMappingDatabase`: it requests that SQLite copy the supplied string.
  The `unsafeBitCast(-1, ...)` expression otherwise looks arbitrary.

## Existing release context

- Removing/disabling the temporary beta **granting** path after distribution is
  already planned. Keep recognition of previously stored complimentary access.
  This review did not remove either path.
- The November 3 pending Annual/local Xcode scenario has an explicit owner-approved
  deferral in `StoreKitPendingPlanChange-2026-11-03.md`. It is not a new blocker.
- The disabled notification-navigation timing test and the Watchlist no-results
  accessibility audit retain their recorded deferrals. The separate show-detail
  title accessibility finding remains recorded as open; no new pass is claimed.
- Regenerating the bundled mapping before release remains a project requirement,
  separate from these code findings.

## Verification limits

No automated tests or full-suite run were performed. Simulator discovery was
attempted with the installed Xcode selected explicitly, but this session could
not connect to CoreSimulator. No simulator settings, transaction history, or
device data were changed. The findings are source-level conclusions; R1 needs
the focused regression verification described above before its fix is accepted.

Existing modifications to `Documentation/Reviews/Known-Test-Failures.md` and
`NextSeason.xcodeproj/project.pbxproj` were left untouched. Only this review
document was added.
