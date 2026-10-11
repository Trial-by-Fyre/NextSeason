# NextSeason Requirements

This is an iOS app that notifies users when new seasons of TV shows become available.
Users can search for shows to see if a next season release date is available, save shows
to a local watchlist, and be notified when the next season release date becomes available.
User accounts and Sign in with Apple are deferred beyond the MVP
(historical decision PD-001).

- Target iOS 18.0 or later.
- Use Swift 6.2 or later.

## Data Sources

- TheTVDB API — guest search only (paginated series search).
- TVMaze API — canonical show/season provider for detail, watchlist, and refresh
  (resolve TheTVDB hits to TVMaze before entering those flows).
- Bundled TVDB↔TVMaze show ID mapping SQLite database — offline Search filtering
  and TVMaze title/poster overlay on search rows
  (regenerate with [the mapping generator](Scripts/generate-tvdb-tvmaze-show-id-mapping-db.py) before release;
  see [mapping attribution](NextSeason/Resources/ShowIDMapping/ATTRIBUTION.md)).
