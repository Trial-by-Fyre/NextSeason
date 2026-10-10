//
//  WatchlistRefreshService.swift
//  NextSeason
//

import Foundation
import os

/// Human-readable summary of one refresh pass (diagnostics / beta tooling).
struct WatchlistRefreshOutcome: Sendable, Equatable {
    let fetchResult: String
    let notificationDecision: String
}

/// Polls TVMaze for watchlist changes, updates persisted next-season status, and
/// delivers local notifications when `StatusChangeDetector` says a change is
/// worth alerting (PD-008 debounce / dedupe).
///
/// Pipeline for each refresh:
/// 1. Load tracked shows from the repository, excluding paused shows.
/// 2. Unless `force`, ask TVMaze which show IDs changed since the oldest check
///    (`/updates/shows`), then skip shows that neither changed on the server nor
///    need a calendar/status recheck.
/// 3. For each show that needs work: fetch full detail, recompute
///    `NextSeasonStatus`, run `StatusChangeDetector.evaluate`, persist, and
///    optionally deliver a notification.
///
/// Remains `@MainActor` because `WatchlistRepository` is MainActor-bound for
/// SwiftData; network work still runs off the actor while awaiting `TVMazeService`.
@MainActor
final class WatchlistRefreshService {
    private let tvMaze: any TVMazeService
    private let repository: any WatchlistRepository
    private let notifications: any NotificationDelivering
    private let analytics: any AnalyticsTracking
    private let diagnostics: BetaRefreshDiagnostics?
    /// Injectable time source so tests (and diagnostics) can pin the calendar used
    /// for status / policy decisions; production uses `{ .now }`.
    private let clock: @Sendable () -> Date
    /// Last time `refreshAllIfNeeded` actually ran a refresh (foreground throttle).
    private var lastForegroundRefreshAt: Date?

    init(
        tvMaze: any TVMazeService,
        repository: any WatchlistRepository,
        notifications: any NotificationDelivering,
        analytics: any AnalyticsTracking,
        diagnostics: BetaRefreshDiagnostics? = nil,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.tvMaze = tvMaze
        self.repository = repository
        self.notifications = notifications
        self.analytics = analytics
        self.diagnostics = diagnostics
        self.clock = clock
    }

    /// Scene-active / foreground entry point: runs `refreshAll` only when
    /// `RefreshPolicy` says enough time has passed since the last foreground run.
    func refreshAllIfNeeded() async {
        guard
            RefreshPolicy.shouldPerformForegroundRefresh(
                lastRefreshAt: lastForegroundRefreshAt,
                at: clock()
            )
        else {
            AppDiagnosticsLogger.logger(for: .cache).notice("watchlist_refresh_skipped policy")
            return
        }

        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_foreground")
        await refreshAll(force: false)
        lastForegroundRefreshAt = clock()
    }

    /// Full watchlist refresh used by background tasks, pull-to-refresh, and
    /// `refreshAllIfNeeded`.
    ///
    /// - Parameter force: When true, re-fetches every tracked show instead of
    ///   consulting TVMaze's updates map.
    /// - Parameter deliverNotifications: When false, status is still updated and
    ///   dedupe signatures recorded, but no local notification is scheduled.
    ///   Use for interactive pull-to-refresh where the user can see the list.
    /// - Parameter recordDiagnostics: When true, writes a beta diagnostics sample.
    /// - Returns: A summary of what happened, or `nil` if the run was cancelled.
    @discardableResult
    func refreshAll(
        force: Bool = false,
        deliverNotifications: Bool = true,
        recordDiagnostics: Bool = false
    ) async -> WatchlistRefreshOutcome? {
        AppDiagnosticsLogger.logger(for: .cache)
            .notice(
                "watchlist_refresh_start force=\(force, privacy: .public) notify=\(deliverNotifications, privacy: .public)"
            )
        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_start")
        var fetchResult = String(localized: "Completed")
        // Last per-show notification decision string wins for the outcome summary.
        var lastNotificationDecision = String(
            localized: "No notification (no meaningful change)"
        )
        var refreshedShowCount = 0
        var skippedShowCount = 0

        let trackedShows: [TrackedShow]
        do {
            // Paused shows (Plus lapsed, beyond the free limit) are never fetched
            // or notified; they also don't widen the updates window below.
            trackedShows = try await repository.all().filter { !$0.isPaused }
        } catch {
            if error is CancellationError {
                AppDiagnosticsLogger.logTaskCancel("watchlist_refresh")
                return nil
            }
            analytics.trackNonFatalError(error, context: "watchlist_refresh_load")
            recordBackgroundDiagnosticsIfNeeded(
                recordDiagnostics,
                fetchResult: String(localized: "Failed to load watchlist"),
                notificationDecision: lastNotificationDecision
            )
            return WatchlistRefreshOutcome(
                fetchResult: String(localized: "Failed to load watchlist"),
                notificationDecision: lastNotificationDecision
            )
        }

        guard !trackedShows.isEmpty else {
            AppDiagnosticsLogger.logger(for: .cache).notice(
                "watchlist_refresh_complete empty_watchlist")
            AppDiagnosticsLogger.breadcrumb("watchlist_refresh_complete")
            let outcome = WatchlistRefreshOutcome(
                fetchResult: String(localized: "Skipped: empty watchlist"),
                notificationDecision: lastNotificationDecision
            )
            recordBackgroundDiagnosticsIfNeeded(
                recordDiagnostics,
                fetchResult: outcome.fetchResult,
                notificationDecision: outcome.notificationDecision
            )
            return outcome
        }

        // Map of showID → TVMaze "updated" timestamp. Empty when forcing a full pass.
        let updates: [Int: Date]
        if force {
            updates = [:]
        } else {
            // Grow the updates window with the largest polling gap so a delayed
            // background run still sees every change since we last checked.
            let oldestCheck = trackedShows.map(\.lastCheckedAt).min() ?? clock()
            let period = TVMazeUpdatePeriod.covering(since: oldestCheck, at: clock())
            do {
                updates = try await tvMaze.updatedShows(since: period)
            } catch {
                analytics.trackNonFatalError(error, context: "watchlist_refresh_updates")
                recordBackgroundDiagnosticsIfNeeded(
                    recordDiagnostics,
                    fetchResult: String(localized: "Failed to fetch TVMaze updates"),
                    notificationDecision: lastNotificationDecision
                )
                return WatchlistRefreshOutcome(
                    fetchResult: String(localized: "Failed to fetch TVMaze updates"),
                    notificationDecision: lastNotificationDecision
                )
            }
        }

        for var tracked in trackedShows {
            if !force {
                let serverChanged =
                    updates[tracked.id].map { $0 > tracked.sourceUpdatedAt } ?? false
                // `nextSeason` also depends on the calendar (airing → returning when a
                // season ends, scheduled → airing on premiere). Search-track used to
                // persist `.returningNoSeasonYet` without season data; re-check that
                // case even when TVMaze's `updated` epoch is unchanged.
                let needsRecheck = Self.needsCalendarOrStatusRecheck(tracked.nextSeason)
                guard serverChanged || needsRecheck else {
                    skippedShowCount += 1
                    continue
                }
            }

            do {
                let show = try await tvMaze.show(id: tracked.id, bypassCache: true)
                tracked.isStale = false
                tracked.name = show.name
                tracked.posterMediumURL = show.posterMediumURL
                tracked.summaryHTML = show.summaryHTML
                tracked.tvMazeURL = show.tvMazeURL
                tracked.status = show.status
                tracked.sourceUpdatedAt = show.updatedAt

                // Pure status + notify decision; persistence and delivery follow.
                let newStatus = NextSeasonCalculator.status(for: show, at: clock())
                let evaluation = StatusChangeDetector.evaluate(
                    tracked: tracked, newStatus: newStatus, at: clock())

                try await repository.updateAfterRefresh(evaluation.tracked)
                refreshedShowCount += 1
                lastNotificationDecision = Self.describeNotificationDecision(
                    for: tracked.name,
                    evaluation: evaluation,
                    deliverNotifications: deliverNotifications
                )
                if deliverNotifications, let notification = evaluation.notification {
                    await notifications.deliver(notification)
                }
            } catch is CancellationError {
                AppDiagnosticsLogger.logTaskCancel("watchlist_refresh_show")
                return nil
            } catch TVMazeError.notFound {
                // Show removed from TVMaze: keep the row but flag it stale.
                tracked.isStale = true
                tracked.lastCheckedAt = clock()
                try? await repository.updateAfterRefresh(tracked)
                refreshedShowCount += 1
                lastNotificationDecision = String(
                    localized: "Marked stale: \(tracked.name) not found on TVMaze"
                )
            } catch {
                // Per-show failure: leave this row alone and continue the rest.
                analytics.trackNonFatalError(error, context: "watchlist_refresh_show")
                continue
            }
        }

        if refreshedShowCount == 0, skippedShowCount > 0 {
            fetchResult = String(
                localized: "No TVMaze changes for \(skippedShowCount) tracked show(s)"
            )
        } else {
            fetchResult = String(localized: "Refreshed \(refreshedShowCount) show(s)")
            if skippedShowCount > 0 {
                fetchResult += String(localized: ", skipped \(skippedShowCount) unchanged")
            }
            if force {
                fetchResult += String(localized: " (forced)")
            }
        }

        let outcome = WatchlistRefreshOutcome(
            fetchResult: fetchResult,
            notificationDecision: lastNotificationDecision
        )
        recordBackgroundDiagnosticsIfNeeded(
            recordDiagnostics,
            fetchResult: outcome.fetchResult,
            notificationDecision: outcome.notificationDecision
        )
        AppDiagnosticsLogger.logger(for: .cache).notice("watchlist_refresh_complete")
        AppDiagnosticsLogger.breadcrumb("watchlist_refresh_complete")
        return outcome
    }

    private func recordBackgroundDiagnosticsIfNeeded(
        _ recordDiagnostics: Bool,
        fetchResult: String,
        notificationDecision: String
    ) {
        guard recordDiagnostics else { return }
        diagnostics?.recordBackgroundRefreshCompleted(
            at: clock(),
            fetchResult: fetchResult,
            notificationDecision: notificationDecision
        )
    }

    /// Turns an evaluation into the short string shown in diagnostics outcomes.
    private static func describeNotificationDecision(
        for showName: String,
        evaluation: StatusChangeDetector.Evaluation,
        deliverNotifications: Bool
    ) -> String {
        if let notification = evaluation.notification {
            if deliverNotifications {
                return String(
                    localized: "Delivered for \(showName): \(notification.body)"
                )
            }
            return String(
                localized:
                    "Suppressed for \(showName) (interactive refresh): \(notification.body)"
            )
        }
        if evaluation.tracked.pendingChangeSignature != nil {
            return String(localized: "Pending debounce for \(showName)")
        }
        return String(
            localized: "No notification for \(showName) (no meaningful change)"
        )
    }

    /// Statuses that can change without TVMaze bumping `updated` (calendar drift,
    /// or a previously incomplete `.returningNoSeasonYet` snapshot).
    private static func needsCalendarOrStatusRecheck(_ status: NextSeasonStatus) -> Bool {
        switch status {
        case .airing, .scheduled, .returningNoSeasonYet:
            true
        case .announcedUndated, .ended, .unknown:
            false
        }
    }
}
