# NextSeason

NextSeason is an iPhone app that keeps track of the television shows you care about and lets you know when something changes.

Search for a show, add it to your Watchlist, and NextSeason quietly monitors it in the background. When a new season is announced or premiere information changes, the app can notify you — without requiring a NextSeason account.

NextSeason is developed by [Trial by Fyre, LLC](https://trialbyfyre.com).

## Screenshots

<table>
<tr>
<td align="center">
<strong>Search</strong><br><br>
<img src="Documentation/Post-MVP/Screenshots/Search-Results.png" width="220">
</td>
<td align="center">
<strong>Show Details</strong><br><br>
<img src="Documentation/Post-MVP/Screenshots/Show-Detail.png" width="220">
</td>
<td align="center">
<strong>Watchlist</strong><br><br>
<img src="Documentation/Post-MVP/Screenshots/Watchlist.png" width="220">
</td>
</tr>
</table>

## Features

- Search for television shows using TheTVDB
- Track shows in a local Watchlist
- See current show, season, and next-episode information from TVMaze
- Receive local notifications when tracked show information changes
- Refresh tracked shows using iOS background app refresh
- Search and organize the Watchlist
- Export Watchlist data as CSV
- Recover Watchlist data when the persistent store cannot be opened
- Use the app with VoiceOver-friendly labels, actions, hints, and navigation
- Use the core app without creating a NextSeason account

The free tier can track up to three shows. NextSeason Plus removes that limit through monthly or annual StoreKit subscriptions. The app also supports optional consumable tips that do not unlock features.

## Engineering

NextSeason is written in Swift 6 and SwiftUI and currently targets iOS 18 and later.

The project uses:

- Swift 6
- SwiftUI
- SwiftData
- Swift Concurrency
- MVVM
- StoreKit 2
- BackgroundTasks
- UserNotifications
- XCTest and XCUITest
- SQLite for TheTVDB-to-TVMaze identifier mapping
- TheTVDB API
- TVMaze API
- Aptabase for a small whitelist of anonymous product analytics

The application separates feature views and view models from domain models, persistence, external API clients, purchase handling, notifications, analytics, and background refresh services.

Particular attention has been given to:

- Accessibility
- SwiftData schema evolution and persistence recovery
- Background refresh behavior
- StoreKit purchases and entitlement handling
- Notification behavior
- Failure and recovery paths
- Privacy-conscious analytics
- Testability
- Keeping external API models separate from application domain models

## Search and Data Sources

NextSeason uses TheTVDB and TVMaze for different parts of the application.

**TheTVDB** provides guest search results.

**TVMaze** is used for show details, season and episode information, Watchlist data, and ongoing Watchlist refreshes.

Because the rest of the application is keyed by TVMaze show IDs, search results need to be mapped from TheTVDB IDs into the TVMaze-based model. NextSeason maintains a small SQLite mapping database for this purpose. A bundled snapshot provides the initial mapping, and the app can refresh that mapping opportunistically from TVMaze without blocking launch or search.

This keeps search separate from the application's canonical show data while allowing TheTVDB search results to flow into the TVMaze-based detail and Watchlist features.

## Privacy

NextSeason does not require a user account, and Watchlist data is stored locally on the device.

The app uses Aptabase for a deliberately small whitelist of anonymous product analytics. Remote analytics are limited to structural information such as search query length, result counts, timing, search outcome, and whether a selected search result is already on the Watchlist. Search text and show titles are not sent as analytics parameters.

Most of the app's analytics catalog remains local and is used for diagnostics rather than remote tracking.

More information is available in the [NextSeason Privacy Policy](https://getnextseason.com/privacy.html).

## AI-Assisted Development

NextSeason was developed using an AI-assisted engineering workflow.

AI has been used throughout development for implementation, code review, research, debugging, testing, architectural discussion, and documentation. ChatGPT and coding agents have served as engineering collaborators rather than autonomous owners of the project.

I remain responsible for the product and engineering decisions: defining behavior, choosing architecture, evaluating proposed solutions, reviewing generated code, testing the application, and deciding what ultimately ships.

One reason this repository is public is to make that process visible rather than presenting AI-assisted software development as a black box.

The repository therefore includes design documents, decision history, planning material, and AI development transcripts in addition to the application source.

For more detail, see [AI-Assisted Development Workflow](Documentation/AI-Assisted%20Development%20Workflow.md).

## Testing

NextSeason includes unit and UI tests covering areas such as:

- Search behavior and TheTVDB integration
- Show detail behavior
- Watchlist persistence and tracking
- Watchlist search
- Background refresh scheduling and refresh logic
- Local notifications
- SwiftData schema behavior
- Persistence failure and recovery
- StoreKit purchase and entitlement logic
- Free-tier Watchlist limits
- CSV export
- Analytics behavior
- Accessibility-focused UI behavior and audits
- App navigation and launch behavior

The repository also contains scripts used for profiling, diagnostics, release checks, and build safeguards.

## Repository Documentation

The repository intentionally preserves more of the development process than a typical application repository.

Useful starting points include:

- [MVP Documentation](Documentation/MVP)
- [Post-MVP Documentation](Documentation/Post-MVP)
- [Diagrams](Documentation/MVP/Diagrams)
- [AI Transcripts](Documentation/MVP/AI%20Transcripts)
- [AI-Assisted Development Workflow](Documentation/AI-Assisted%20Development%20Workflow.md)
- [App Store Readiness Roadmap](Documentation/Post-MVP/NextSeason%20-%20App%20Store%20Readiness%20Roadmap.md)
- [Product Evolution Roadmap](Documentation/Post-MVP/NextSeason%20-%20Product%20Evolution%20Roadmap.md)

The historical material is intentionally retained. It shows not only what decisions were made, but how requirements, architecture, and implementation evolved over the course of development. Historical documents and transcripts may therefore describe features or implementation details that are no longer part of the current app.

## Status

NextSeason is currently being prepared for its initial App Store release.

The first release is deliberately focused: it aims to do one thing well — remember the shows a user cares about and quietly let them know when something worth knowing changes.

Future work is documented in the [Product Evolution Roadmap](Documentation/Post-MVP/NextSeason%20-%20Product%20Evolution%20Roadmap.md).

## About

NextSeason is created by **Trial by Fyre, LLC**, an independent developer of apps for Apple platforms.

[NextSeason](https://getnextseason.com) · [Trial by Fyre](https://trialbyfyre.com)
