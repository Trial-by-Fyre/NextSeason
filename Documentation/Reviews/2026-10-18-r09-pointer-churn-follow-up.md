# R09 follow-up: undated season and next-episode pointer changes

Status: follow-up for future evaluation; no implementation change requested.

With no season premiere date, episode 1 dated on or before today can produce
`airing`. If TVMaze then advances its next-episode pointer to episode 2 while
the season premiere remains unknown, the calculator returns `announcedUndated`.
The narrow R09 correction prevents later episodes from supplying a false
premiere date or producing this temporary airing state themselves; it does not
eliminate the episode-1 display reversal.

Current regression coverage:

- `NextSeasonCalculatorTests.episodeOnePremiereDayOscillatesWhenPointerAdvances`
  documents the display sequence.
- `StatusChangeDetectorTests.airingToAnnouncedWhenPointerAdvancesDoesNotNotify`
  verifies that the revert itself does not generate a notification.

These checks do not establish that the complete refresh sequence avoids repeated
alerts. After the stored status reverts, a later return to `airing` could generate
another alert. This is a code-review concern, not a reproduced production defect.
Before claiming notification deduplication across pointer churn, add a refresh-level
sequence test that persists each observation and counts notifications through
`airing → announcedUndated → airing` for the same season.

The reviewer recommended tolerating the display reversal for now. This note does
not record product-owner acceptance of repeated alerts or approve a new status
policy. Any later change to require a dated season row or other evidence before
showing `airing` needs a deliberate product decision and targeted verification.

Keep this follow-up separate from the completed narrow R09 correction. Do not
invent a premiere date from a later episode to resolve it.
