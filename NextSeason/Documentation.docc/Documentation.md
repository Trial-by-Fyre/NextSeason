# ``NextSeason``

An iPhone app that tracks TV shows and notifies you when a next season is coming.

## Overview

NextSeason searches TheTVDB, resolves hits to TVMaze for detail and tracking,
saves a local watchlist, and delivers a local notification when
``NextSeasonCalculator`` finds a new next-season status.

This catalog is the in-Xcode map of the app target. Symbol pages come from
in-source comments. See the repository README for current maintenance guides and GitHub Issues for working history.

## Topics

### App launch and navigation

- ``NextSeasonApp``
- ``AppCompositionRoot``
- ``AppLaunchState``
- ``LaunchFailureTracker``
- ``AppNavigationCoordinator``
- ``ContentView``

### Screens

- ``SearchView``
- ``SearchViewModel``
- ``WatchlistView``
- ``WatchlistViewModel``
- ``ShowDetailView``
- ``ShowDetailViewModel``

### Domain model

- ``Show``
- ``Season``
- ``ShowStatus``
- ``NextSeasonStatus``
- ``NextEpisode``
- ``TrackedShow``
- ``TVDBSearchResult``

### Persistence

- ``WatchlistRepository``
- ``SwiftDataWatchlistRepository``
- ``NextSeasonModelContainer``
- ``TrackedShowEntity``

### Data sources

- ``TheTVDBService``
- ``TheTVDBClient``
- ``TVMazeService``
- ``TVMazeClient``
- ``ShowIDMapping``
- ``ShowIDMappingDatabase``

### Refresh and notifications

- ``NextSeasonCalculator``
- ``WatchlistRefreshService``
- ``RefreshScheduler``
- ``StatusChangeDetector``
- ``NotificationService``
- ``NotificationRouting``
- ``ReviewPromptCoordinator``
