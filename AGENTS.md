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

## Development and Learning

AI-assisted development in this project should optimize for both shipping high-quality
software and helping the project owner retain an understanding of the codebase.

When making changes:

- Routine boilerplate, familiar patterns, and easily referenced API syntax can be
  implemented without extensive explanation.

- Before introducing a significant new concept, architectural pattern, framework, or
  unfamiliar Swift technique, explain what problem it solves, why it is appropriate
  here, and any important alternatives or tradeoffs.

- For significant app-specific logic or architecture, explain the reasoning behind the
  implementation, not merely what the code does.

- Distinguish between:
  1. Concepts and design decisions that should be understood and retained.
  2. Syntax or API details that can reasonably be looked up when needed.
  3. Swift/iOS knowledge that a senior iOS engineer may reasonably be expected to recall
     during an interview.

- Explicitly flag items in the third category as useful interview knowledge.

- Do not quiz the project owner on concepts that have not first been explained. After a
  significant change, a brief teach-back may be useful, but focus on the concept rather
  than exact syntax.

- For non-obvious architectural decisions, unusual workarounds, or constraints that a
  future maintainer might question, leave an appropriate durable explanation in the
  repository, such as documentation, a decision-log entry, or a concise code comment.

Keep this lightweight. Do not turn routine development into a tutorial or slow down
straightforward work unnecessarily.

## AI Instructions

- Do not create unnecessary abstractions.
- Keep files under 500 lines when possible.
- Before writing Swift, read the relevant Swift skill file(s) first and note
  which were used: `swiftui-pro` (SwiftUI views), `swiftdata-pro` (SwiftData /
  persistence), `swift-concurrency-pro` (async/await, actors), `swift-testing-pro`
  (tests).
