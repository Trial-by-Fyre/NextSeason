# NextSeason -- Product Evolution Roadmap

## Purpose

This document captures enhancements planned after the initial App Store release. Content has been preserved from the original roadmap and reorganized by release timing rather than topic.

# Core Product Improvements

## Search Improvements

- Support common abbreviations and acronyms if users demonstrate a need.
- Continue refining search quality based on analytics and user feedback.

## Watchlist Management

- **Proposal — paused-show upgrade entry point:** Consider opening the Plus paywall when a user taps a paused Watchlist row. Before implementation, confirm whether successful purchase/restore should then open that show’s details; cancellation should leave the saved show intact. Captured from October 23 discussions; scheduling and design are not yet approved. See [suggestion audit S-01](../Reviews/DiscussionSuggestionAudit-2026-10-26.md).
- **Idea for evaluation — Free-tier usage indicator:** Consider a “Tracking N of 3 free shows” line counting active shows, including those in collapsed sections, while excluding paused shows. Evaluate separately from collapsed-header styling; no design is approved. See [suggestion audit S-02](../Reviews/DiscussionSuggestionAudit-2026-10-26.md).

- User-selectable sorting.
- Support marking which shows the user has fully caught up on.
- **Deferred — post-v1.0 usability:** Consider making collapsed Watchlist section counts more noticeable, e.g. a subtle count capsule beside “Airing Now”, after a show in a collapsed section was overlooked. The existing header count is correct; preserve collapsed state without auto-expanding sections. This is not a v1.0 blocker.
- **Subscription downgrade improvements:** Allow users whose Plus subscription
  expires to choose which three shows remain active, rather than automatically
  retaining the first three. Provide a simple interface for managing those
  selections. (At launch, the three oldest saved shows stay active and the rest
  are paused; restoring Plus reactivates everything.)

Continue to favor fast, predictable title matching over discovery-oriented fuzzy search.

## Watchlist Import and Restore

Allow users to import a previously exported NextSeason watchlist, providing a straightforward way to restore or transfer their data.

### Considerations

- Support importing the watchlist format produced by NextSeason's export feature.
- Use stable show identifiers where possible to match imported shows to current show data.
- Define behavior for:
  - Shows already present in the watchlist
  - Shows that can no longer be found or matched
  - Older export formats
  - Invalid or malformed files
  - Imports that would exceed the current free-tier watchlist limit
- Provide a clear summary of the import result, including shows that could not be restored.
- Preserve compatibility with exports created by earlier versions of NextSeason where practical.

Before implementation, determine whether import is intended primarily as a user-controlled backup/restore mechanism, a way to move data between devices, or both. Reevaluate the appropriate export/import format at that time; CSV may remain sufficient, or a versioned structured format such as JSON may be preferable for reliable restoration.

## Intelligent Monitoring Experience

The long-term vision for NextSeason is to quietly monitor the TV shows users care about and let them know when there is something worth knowing. Future enhancements should reinforce user confidence that the app is actively monitoring on their behalf without encouraging unnecessary engagement.

### Monitoring Confidence

- Display a monitoring summary at the top of the watchlist (for example: "Monitoring 18 shows").
- Show the last successful background refresh time.
- Clearly indicate when everything is up to date.
- Surface when background refresh has not run recently so users understand why updates may be delayed.

### Immediate Value

After adding a show to the watchlist, present a richer status summary instead of a simple confirmation.

Examples:

- Current status (Running, Returning, Ended, etc.).
- Latest known season and premiere information.
- A brief explanation that NextSeason will monitor the show and notify the user when its status changes.

### Update Awareness

- Display a "Since your last visit" summary when tracked shows have changed.
- Maintain unread update indicators until the user has acknowledged the changes.
- Consider an update history so users can review previously announced changes.

These features should complement notifications rather than replace them, ensuring users can easily see what changed even if they missed a notification.

### Apple Platform Integration

Investigate deeper integration with App Intents, Siri, Apple Intelligence, and widgets.

Potential features:

- Siri/App Intents to add or remove shows from the watchlist.
- Siri queries about the status of tracked shows.
- Siri summaries describing what has changed since the user's last visit.
- Home Screen widgets that display monitoring status or recent updates.

These capabilities should operate on the user's watchlist and application data rather than attempting to become a general entertainment news assistant.

## Notification Enhancements

- Global notification preferences.
- Per-show preferences.
- Quiet hours.
- Notification history.
- Additional notification categories.
- Allow users to request a reminder from a show notification when they cannot act on it immediately.
  - Offer convenient intervals such as later today, tomorrow, or this weekend.
  - Consider custom and/or recurring reminder options if useful.
- Support email as an optional notification channel.
  - Allow users to choose push notifications, email, or both.
  - Allow users to opt into email as a fallback when push notification delivery is known to be unavailable.
- Offer optional periodic watchlist status reports.
  - Summarize the current status of tracked shows.
  - Support an appropriate cadence such as weekly or monthly.
  - Deliver useful information directly in the notification or email rather than requiring an app launch.
  - Keep periodic reports opt-in; users should be able to hear from NextSeason only when something changes.

These features should help users remember information they asked NextSeason to track without creating artificial reasons to reopen the app.

Consider adding a dedicated Settings screen as notification, email, and other global preferences become substantial enough to warrant one.

## Streaming Availability

Implement only if users demonstrate meaningful demand.

If sufficient demand exists:

-   Integrate with a dedicated streaming provider.
-   Display current regional availability.
-   Deep-link to supported services.

Do not use TVMaze's crowdsourced provider data.

### Dependent Future Features

-   Record subscribed services.
-   Highlight available shows.
-   Filter/group by availability.
-   Tailor notifications.


## AI-Assisted Show Insights

Evaluate Apple’s on-device Foundation Models as the primary implementation for concise, privacy-preserving viewing insights.

Potential capabilities:

- Generate a brief "Why you might like this" summary.
- Highlight the types of viewers the show is best suited for.
- Describe tone and pacing in a few concise bullet points.
- Produce consistent, spoiler-free summaries that fit naturally within the existing UI.

Implementation principles:

- Use Apple's on-device Foundation Models when available.
- Cache generated insights so each show is processed only once.
- Gracefully fall back to the standard TVMaze description on unsupported devices or OS versions.
- Clearly identify this as a feature available only on supported versions of iOS, ensuring the app continues to provide a complete experience on older devices.
- Keep AI optional, unobtrusive, and focused on helping users decide whether to add a show to their Watchlist.
- Preserve user privacy by performing generation on-device whenever possible.

## Continuous Improvement

- **Design review proposal — About color consistency:** Review the About page’s text, icons, links, and status colors, especially in Dark Mode, where the assignments can feel arbitrary. Establish a consistent visual hierarchy and meaningful use of color while preserving contrast, accessible status distinctions, and Light Mode readability. No replacement palette is approved. See [suggestion audit S-04](../Reviews/DiscussionSuggestionAudit-2026-10-26.md).
- **Low-priority cleanup proposal:** Use a structured Search failure/retry kind rather than comparing localized error text to decide whether Try Again is available. Preserve restart-only mapping-bootstrap guidance and ordinary retry behavior. See [suggestion audit S-03](../Reviews/DiscussionSuggestionAudit-2026-10-26.md).
- Consult the [recent discussion suggestion audit](../Reviews/DiscussionSuggestionAudit-2026-10-26.md) for existing technical follow-ups saved in review notes, alternatives that were not selected, and the unresolved blocked-add retry correctness concern. Those entries retain their original status; this index does not defer unresolved defects or approve implementation.

- Refine the user experience based on App Store reviews and user feedback.
- Continue improving accessibility.
- **Deferred — low priority: Notifications Are Off banner copy.** At the largest Dynamic Type settings, the banner exceeds the screen height. It scrolls, so its content and controls remain reachable. Shorten the wording while preserving all information and the notification-enablement/settings control. Verify readability and scrolling at ordinary and largest text sizes, including smaller iPhones.
- Improve performance and battery efficiency.
- Reduce maintenance burden through ongoing codebase simplification.

# Platform Features

## iCloud / CloudKit Sync

Use Apple’s cloud infrastructure to synchronize the watchlist and related state across a user’s Apple devices.

-   Synchronize watchlists automatically across devices signed into the user's iCloud account.
-   Synchronize related user-managed state needed for a consistent experience across devices.
-   Support backup and restore.
-   Support device migration.
-   Preserve offline use and reconcile changes when connectivity returns.
-   Prefer CloudKit/iCloud over introducing a separate NextSeason account when Apple’s infrastructure can satisfy the product requirements.

## Apple Platform Expansion

Potential platforms:

Planned after iCloud / CloudKit Sync is implemented:

- iPad
- Mac
- Apple TV companion app

Vision Pro is not currently planned.

## Server-Side Monitoring & Push Notifications

- Move season monitoring to a backend service.
- Monitor each relevant show centrally rather than independently polling the same show for every user who tracks it.
- Detect meaningful season and release-date changes on the server and fan notifications out to users who track the affected show.
- Deliver reliable push notifications through Apple Push Notification service (APNs), even when the app is not running.
- Reduce dependence on background app refresh.
- Keep notification delivery consistent across all of a user’s devices and avoid confusing duplicate notifications.
- Minimize battery impact by performing monitoring on the server whenever possible.
- Design backend monitoring and cloud sync together so the server can determine which users should receive notifications without unnecessarily duplicating or exposing user data.
- Design monitoring to remain useful during long periods when the user does not launch the app.
- Account for iOS potentially offloading NextSeason when Offload Unused Apps is enabled.
  - Do not depend on detecting whether the app has been offloaded; iOS does not provide a reliable offload-state signal.
  - Test remote notification behavior explicitly with NextSeason in the offloaded state.
  - Where the user has opted into email fallback, use email when push delivery is definitively known to be unavailable rather than attempting to infer that the app was offloaded.
- Offer the user the option to receive a regular status update notification showing the current status of all tracked shows, even when nothing has changed.
    - Status update notifications must not count toward review-request eligibility. Continue to base that eligibility on the user’s first show-status-change notification.
  
## Identity & Accounts

Avoid requiring a separate NextSeason account unless it becomes necessary to support iCloud / CloudKit Sync, backend monitoring, or another future feature. Prefer the user's existing Apple/iCloud identity when it can satisfy the product requirements.

# Product Analytics

Transition Diagnostics into a production support feature while retaining diagnostic report generation. Continue using lightweight, privacy-preserving analytics to guide future product decisions.

# Product Principles

-   Remain focused on season tracking.
-   Avoid unnecessary complexity.
-   Favor privacy.
-   Work well without requiring an account.
-   Integrate naturally with Apple's platforms.
-   Earn user trust through reliability.
-   Do one thing exceptionally well before expanding scope.

# Explicit Non-Goals

-   Social networking.
-   User reviews.
-   Episode tracking.
-   Discussion forums.
-   General TV discovery.
-   Recommendation engines.
-   Comprehensive media database features.
