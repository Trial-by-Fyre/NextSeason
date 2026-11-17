# NextSeason repository instructions

- Keep changes scoped and reviewable. Briefly explain intended edits. Avoid unrelated formatting, refactors, and new dependencies without approval. Leave commits to the owner unless asked to make them.
- Explain unfamiliar concepts or consequential tradeoffs briefly when they affect a decision. Offer deeper explanation on request. Record durable constraints near the code or in current documentation.
- Follow [the feature development workflow](FEATURE_DEVELOPMENT.md) for substantial changes. Verify with focused tests. The owner decides when to run the full suite. Report results, unresolved gaps, and review status concisely.
- Use GitHub Issues for working history, actionable work, and decisions with future value. Search open and closed issues before posting, identify the agent making the update, and review excerpts and attachments for public disclosure. Use free-form Task, Bug, Discussion, or Note issues with High, Normal, or Low priority. Use milestones for releases or significant initiatives. PRs and Projects are optional. The owner can override the process.
- Target iOS 18 or later and Swift 6.2 or later. Follow the existing SwiftUI/MVVM conventions. Ask before introducing UIKit or AppKit. Use the `Data` suffix for API DTOs and StoreKit's localized display prices.
- Before writing Swift, read the relevant installed skills in `~/.agents/skills/`: `swiftui-pro`, `swiftdata-pro`, `swift-concurrency-pro`, or `swift-testing-pro`. Mention which you used.
- TheTVDB supplies guest search results. Resolve results to TVMaze IDs for details, Watchlist, and refresh. See [the scripts guide](Scripts/README.md#show-id-mapping) for regenerating the bundled mapping before release.
