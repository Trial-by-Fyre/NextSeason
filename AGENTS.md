//
//  AGENTS.md
//  NextSeason
//
//  Created by Janine Ohmer on 6/12/26.
//

# Agent guide for Swift and SwiftUI

This is an iOS app that notifies users when new seasons of TV shows become available. Users can search for shows to see if a next season release date is available, save shows to a local watchlist, and be notified when the next season release date becomes available. User accounts and Sign in with Apple are deferred beyond the MVP (see `DecisionLog.md` PD-001).


## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SwiftData, and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines.


## Core instructions

- Target iOS 18.0 or later.
- Swift 6.2 or later, using modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.
- Use async/await.

## Data Sources

- TheTVDB API — guest search only (paginated series search)
- TVMaze API — canonical show/season provider for detail, watchlist, and refresh
 (resolve TheTVDB hits to TVMaze before entering those flows)
- Bundled TVDB↔TVMaze show ID mapping SQLite database — offline Search filtering
 and TVMaze title/poster overlay on search rows
 (regenerate with `Scripts/generate-tvdb-tvmaze-show-id-mapping-db.py` before release;
 see `NextSeason/Resources/ShowIDMapping/ATTRIBUTION.md`)

## Coding Style

- Prefer simple, maintainable code.
- Optimize for readability over cleverness.
- Include previews when practical.
- Add comments for non-obvious logic.
- Naming: for data-transfer types (DTOs that mirror API JSON), use the `Data`
  suffix in code, e.g. `ShowData`, `SeasonData`, `SearchResultData`. The term
  "DTO" may still be used in documentation.

## AI Instructions

- Explain major architectural decisions.
- Do not create unnecessary abstractions.
- Keep files under 500 lines when possible.
- Before writing Swift, read the relevant Swift skill file(s) first and note
  which were used: `swiftui-pro` (SwiftUI views), `swiftdata-pro` (SwiftData /
  persistence), `swift-concurrency-pro` (async/await, actors), `swift-testing-pro`
  (tests).


## Cloud Agent (Linux) environment

Cloud Agents run on Linux, where the iOS app **cannot be built or run** —
SwiftUI, SwiftData, StoreKit, and UIKit are Apple-only frameworks that require
macOS + Xcode. The `Scripts/*.sh` device-profiling helpers (`xctrace`,
`devicectl`) are likewise macOS-only.

`.cursor/environment.json` (via `.cursor/install.sh`) provisions the Linux
tooling that *is* usable on a Cloud Agent:

- **Swift 6.2 toolchain** — run `swift format lint --configuration .swift-format
  --recursive NextSeason NextSeasonShared NextSeasonTests NextSeasonUITests` to
  lint sources, and `swiftc -parse` for syntax checks of platform-agnostic code.
- **Python 3** (already in the base image) — the `Scripts/*.py` helpers are
  standard-library only, e.g. regenerating the show-ID mapping DB with
  `Scripts/generate-tvdb-tvmaze-show-id-mapping-db.py`.
