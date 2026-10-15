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
/// 2. Unless `force`, ask TVMaze which show IDs changed since the coverage
///    watermark (`/updates/shows`), then skip shows that neither changed on the
///    server nor need a calendar/status recheck.
/// 3. For each show that needs work: confirm it is still active, fetch full
///    detail, re-read the stored row (it may have been paused or updated while
///    the fetch was suspended), recompute `NextSeasonStatus`, run
///    `StatusChangeDetector.evaluate`, persist, and optionally deliver a
///    notification. If delivery definitely fails, put it back as pending so the
///    next poll retries. Shows in `catchUpShowIDs` instead get a silent baseline.
///    A show another refresh is still working on is skipped (`inFlightShowIDs`).
/// 4. Unless `force`, advance the coverage watermark if the saved rows prove
///    every reported change was applied.
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
    /// Persists the coverage watermark; catch-up marks live in `rowMarks`.
    private let userDefaults: UserDefaults
    /// Catch-up marks and damage reports, shared with the SwiftData repository.
    private let rowMarks: WatchlistRowMarks
    /// Shows whose refresh work (fetch, decision, delivery, failure handling) is
    /// in progress. Another refresh skips them rather than deciding concurrently,
    /// so a failed delivery's restore can never overwrite a newer decision
    /// (review finding R03). In-process only: production has one instance of
    /// this service, so this covers every refresh of the user's watchlist.
    private var inFlightShowIDs: Set<Int> = []

    static let catchUpMarksKey = WatchlistRowMarks.catchUpKey
    static let updatesCoveredThroughKey = "watchlistUpdatesCoveredThrough"

    init(
        tvMaze: any TVMazeService,
        repository: any WatchlistRepository,
        notifications: any NotificationDelivering,
        analytics: any AnalyticsTracking,
        diagnostics: BetaRefreshDiagnostics? = nil,
        userDefaults: UserDefaults = .standard,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.tvMaze = tvMaze
        self.repository = repository
        self.notifications = notifications
        self.analytics = analytics
        self.diagnostics = diagnostics
        self.userDefaults = userDefaults
        self.rowMarks = WatchlistRowMarks(userDefaults: userDefaults)
        self.clock = clock
    }

    /// Resumed shows, and rows the repository found with an undecodable snapshot,
    /// still awaiting a silent baseline, keyed by show ID, valued by the saved
    /// row's `dateAdded` (reference-date seconds).
    ///
    /// Persisted so an interrupted or failed catch-up is retried later, and so any
    /// refresh that reaches one of these shows first — including a notifying
    /// foreground or background refresh — baselines it instead of announcing
    /// changes that happened while it was paused. A mark is consumed when its
    /// baseline is written.
    ///
    /// The `dateAdded` ties a mark to one saved row: deleting a show and adding
    /// it again creates a new row (new `dateAdded`), so a leftover mark never
    /// silences the new row's updates. Undoing a delete restores the original
    /// `dateAdded`, so the mark still applies — even if a refresh ran while the
    /// row was deleted, because marks are pruned only when superseded by a new
    /// row, not when their row is temporarily absent.
    private var catchUpMarks: [Int: TimeInterval] {
        get { rowMarks.catchUp }
        set { rowMarks.catchUp = newValue }
    }

    /// IDs of shows that still have a catch-up mark.
    var catchUpShowIDs: Set<Int> { Set(catchUpMarks.keys) }

    /// Every TVMaze change up to this time is reflected in every active saved row.
    /// It decides the next updates window (see `fetchUpdates(at:)`) and advances
    /// only through `advanceUpdatesCoverage`.
    ///
    /// Kept separately from rows' `lastCheckedAt` because rows skipped as
    /// unchanged are never written, so their `lastCheckedAt` ages even when the
    /// app refreshes daily and cannot tell a long absence from a stable show.
    private var updatesCoveredThrough: Date? {
        get {
            guard userDefaults.object(forKey: Self.updatesCoveredThroughKey) != nil else {
                return nil
            }
            return Date(
                timeIntervalSinceReferenceDate: userDefaults.double(
                    forKey: Self.updatesCoveredThroughKey))
        }
        set {
            userDefaults.set(
                newValue?.timeIntervalSinceReferenceDate, forKey: Self.updatesCoveredThroughKey)
        }
    }

    /// Marks resumed shows for a silent baseline. Call before persisting the
    /// resume so no refresh can see them active but unmarked.
    func markForCatchUp(_ shows: [TrackedShow]) {
        guard !shows.isEmpty else { return }
        var marks = catchUpMarks
        for show in shows {
            marks[show.id] = show.dateAdded.timeIntervalSinceReferenceDate
        }
        catchUpMarks = marks
    }

    /// Post-resume catch-up for just the resumed shows. Notifications are not
    /// turned off for the whole run: a still-marked show is baselined silently,
    /// but one whose mark another refresh already consumed is handled normally,
    /// so a genuinely new change found by a delayed catch-up still notifies.
    func catchUp(showIDs: Set<Int>) async {
        await refreshAll(force: true, onlyShowIDs: showIDs)
    }

    /// True when `row` is the same saved row that was marked for catch-up.
    private func needsCatchUp(_ row: TrackedShow) -> Bool {
        catchUpMarks[row.id] == row.dateAdded.timeIntervalSinceReferenceDate
    }

    /// True when the repository found this saved row's snapshot undecodable.
    private func isReportedDamaged(_ row: TrackedShow) -> Bool {
        rowMarks.damageReported[row.id] == row.dateAdded.timeIntervalSinceReferenceDate
    }

    /// Consumes the row's catch-up mark and any damage report, once a write has
    /// left it with a valid saved status.
    private func clearCatchUp(for row: TrackedShow) {
        catchUpMarks[row.id] = nil
        rowMarks.damageReported[row.id] = nil
    }

    /// Scene-active / foreground entry point: runs `refreshAll` only when
    /// `RefreshPolicy` says enough time has passed since the last foreground run.
    ///
    /// - Parameter prepare: Always awaited first, even when the policy then skips
    ///   the refresh. Production re-reads entitlements and reconciles pause state
    ///   here, so the refresh sees reconciled shows rather than pre-lapse state.
    func refreshAllIfNeeded(prepare: @MainActor () async -> Void = {}) async {
        await prepare()
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
    /// - Parameter onlyShowIDs: When set, refreshes just these shows (post-resume
    ///   catch-up) and leaves every other show for ordinary refreshes.
    /// - Returns: A summary of what happened, or `nil` if the run was cancelled.
    @discardableResult
    func refreshAll(
        force: Bool = false,
        deliverNotifications: Bool = true,
        recordDiagnostics: Bool = false,
        onlyShowIDs: Set<Int>? = nil
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
        // Shows whose not-found (stale) flag this pass actually saved; the only
        // evidence a stale row counts as covered (see `isCovered`).
        var staleSavedIDs: Set<Int> = []
        var skippedShowCount = 0

        let trackedShows: [TrackedShow]
        do {
            let savedShows = try await repository.all()
            // Drop a catch-up mark only once its show was added again as a new row
            // (same ID, different `dateAdded`). A mark whose row is merely absent
            // is kept: the deletion may still be undone, which restores the
            // original row, and the mark must still silence that row's history.
            // An absent row's mark is inert, since it matches no other row.
            let marks = catchUpMarks
            if !marks.isEmpty {
                let superseded = Set(
                    savedShows.filter { marks[$0.id] != nil && !needsCatchUp($0) }.map(\.id))
                if !superseded.isEmpty {
                    catchUpMarks = marks.filter { !superseded.contains($0.key) }
                    rowMarks.damageReported = rowMarks.damageReported.filter {
                        !superseded.contains($0.key)
                    }
                }
            }
            // Paused shows (Plus lapsed, beyond the free limit) are never fetched
            // or notified; they also don't widen the updates window below.
            trackedShows = savedShows.filter { show in
                !show.isPaused && (onlyShowIDs?.contains(show.id) ?? true)
            }
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
        let requestTime = clock()
        let updates: [Int: Date]
        if force {
            updates = [:]
        } else {
            do {
                updates = try await fetchUpdates(at: requestTime)
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

        for snapshot in trackedShows {
            // Resumed shows awaiting their baseline are always fetched.
            if !force, !needsCatchUp(snapshot) {
                let serverChanged =
                    updates[snapshot.id].map { $0 > snapshot.sourceUpdatedAt } ?? false
                // `nextSeason` also depends on the calendar (airing → returning when a
                // season ends, scheduled → airing on premiere). Search-track used to
                // persist `.returningNoSeasonYet` without season data; re-check that
                // case even when TVMaze's `updated` epoch is unchanged.
                let needsRecheck = Self.needsCalendarOrStatusRecheck(snapshot.nextSeason)
                // A soft change seen once (PD-008) needs a second poll to confirm.
                // TVMaze's `updated` won't move again for the same data, so without
                // this the pending alert would wait for an unrelated server update.
                let awaitsConfirmation = snapshot.pendingChangeSignature != nil
                guard serverChanged || needsRecheck || awaitsConfirmation else {
                    skippedShowCount += 1
                    continue
                }
            }

            // Skip, rather than wait for, a show another refresh is working on; it
            // makes the decision and handles any delivery failure. A skipped show
            // counts toward coverage only if its saved row proves it (`isCovered`),
            // and a catch-up mark stays for the next refresh to consume.
            guard inFlightShowIDs.insert(snapshot.id).inserted else {
                AppDiagnosticsLogger.breadcrumb("watchlist_refresh_show_busy:\(snapshot.id)")
                continue
            }
            defer { inFlightShowIDs.remove(snapshot.id) }

            do {
                // The snapshot may be stale: a downgrade can pause a show (or the
                // user remove it) while earlier fetches are suspended.
                guard try await activeRow(for: snapshot.id) != nil else { continue }
                let show = try await tvMaze.show(id: snapshot.id, bypassCache: true)
                // Re-read after the fetch, which suspended: skip a show paused or
                // removed meanwhile, and evaluate against the latest signatures so an
                // overlapping refresh's baseline or debounce is not overwritten.
                guard var tracked = try await activeRow(for: snapshot.id) else { continue }
                // Overlapping requests can finish out of order. Never apply a
                // response older than the version already stored (TVMaze `updated`),
                // or it would overwrite a newer baseline and re-announce history.
                guard show.updatedAt >= tracked.sourceUpdatedAt else {
                    AppDiagnosticsLogger.breadcrumb("watchlist_refresh_stale_response:\(show.id)")
                    continue
                }
                tracked.isStale = false
                tracked.name = show.name
                tracked.posterMediumURL = show.posterMediumURL
                tracked.summaryHTML = show.summaryHTML
                tracked.tvMazeURL = show.tvMazeURL
                tracked.status = show.status
                tracked.sourceUpdatedAt = show.updatedAt

                // Pure status + notify decision; persistence and delivery follow.
                let newStatus = NextSeasonCalculator.status(for: show, at: clock())

                // Checked now, not at loop start, so a refresh already running when a
                // show was resumed still baselines it rather than notifying.
                if needsCatchUp(tracked) {
                    let baseline = StatusChangeDetector.baseline(
                        tracked: tracked, newStatus: newStatus, at: clock())
                    try await repository.updateAfterRefresh(baseline)
                    let wasDamaged = isReportedDamaged(tracked)
                    clearCatchUp(for: tracked)
                    refreshedShowCount += 1
                    lastNotificationDecision =
                        wasDamaged
                        ? String(
                            localized:
                                "Repaired \(tracked.name)'s saved status: baseline recorded, no notification"
                        )
                        : String(
                            localized:
                                "Catch-up for \(tracked.name): baseline recorded, no notification"
                        )
                    continue
                }

                let evaluation = StatusChangeDetector.evaluate(
                    tracked: tracked, newStatus: newStatus, at: clock())

                // Saved before scheduling, so termination in between loses the
                // alert (accepted, R03 scenario 14) rather than risking a repeat.
                try await repository.updateAfterRefresh(evaluation.tracked)
                refreshedShowCount += 1
                var delivery: NotificationDeliveryOutcome?
                var retryPending = false
                if let notification = evaluation.notification {
                    delivery =
                        deliverNotifications
                        ? await notifications.deliver(notification) : .suppressed
                    // Only a definite failure is retried; suppressed is consumed,
                    // and unknown may already have alerted.
                    if delivery == .failed {
                        retryPending = await restoreUndelivered(
                            evaluation.tracked,
                            previousLastNotifiedSignature: tracked.lastNotifiedSignature)
                    }
                }
                lastNotificationDecision = Self.describeNotificationDecision(
                    for: tracked.name,
                    evaluation: evaluation,
                    delivery: delivery,
                    deliverNotifications: deliverNotifications,
                    retryPending: retryPending
                )
            } catch is CancellationError {
                AppDiagnosticsLogger.logTaskCancel("watchlist_refresh_show")
                return nil
            } catch TVMazeError.notFound {
                // Show removed from TVMaze: keep the row but flag it stale, unless it
                // was paused or removed while the request was in flight.
                guard var tracked = try? await activeRow(for: snapshot.id) else { continue }
                tracked.isStale = true
                tracked.lastCheckedAt = clock()
                // A damaged row's stale write stores its fallback status as valid
                // JSON, which repairs it. Its repair mark and any pending signature
                // would each force a refetch on every later refresh (and another
                // "not found"), so clear the signature in this same write and the
                // mark once it succeeds. Undamaged rows keep their existing behavior.
                let repairsDamage = isReportedDamaged(tracked)
                if repairsDamage { tracked.pendingChangeSignature = nil }
                if (try? await repository.updateAfterRefresh(tracked)) != nil {
                    staleSavedIDs.insert(tracked.id)
                    if repairsDamage { clearCatchUp(for: tracked) }
                }
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

        // Forced passes (pull-to-refresh, catch-up) never consult the updates map,
        // so they cannot prove coverage; ordinary refreshes advance it.
        if !force, onlyShowIDs == nil {
            await advanceUpdatesCoverage(
                updates: updates, requestTime: requestTime, staleSavedIDs: staleSavedIDs)
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

    /// After a definite delivery failure, makes the saved decision pending again
    /// so the next poll retries. Returns whether the retry was set up; a failed
    /// restore write loses the retry (accepted, R03 scenario 17) and is logged.
    private func restoreUndelivered(
        _ attempt: TrackedShow, previousLastNotifiedSignature: String?
    ) async -> Bool {
        do {
            return try await repository.restoreUndeliveredNotification(
                attempt, previousLastNotifiedSignature: previousLastNotifiedSignature)
        } catch {
            analytics.trackNonFatalError(error, context: "watchlist_restore_undelivered")
            return false
        }
    }

    /// Turns an evaluation and its delivery outcome into the short string shown
    /// in diagnostics. It never claims the user received or saw an alert.
    private static func describeNotificationDecision(
        for showName: String,
        evaluation: StatusChangeDetector.Evaluation,
        delivery: NotificationDeliveryOutcome?,
        deliverNotifications: Bool,
        retryPending: Bool
    ) -> String {
        if let notification = evaluation.notification, let delivery {
            switch delivery {
            case .accepted:
                return String(
                    localized: "Notification scheduled for \(showName): \(notification.body)"
                )
            case .suppressed where !deliverNotifications:
                return String(
                    localized:
                        "Suppressed for \(showName) (interactive refresh): \(notification.body)"
                )
            case .suppressed:
                return String(
                    localized:
                        "Suppressed for \(showName) (alerts not permitted): \(notification.body)"
                )
            case .failed where retryPending:
                return String(
                    localized:
                        "Scheduling failed for \(showName), will retry next refresh: \(notification.body)"
                )
            case .failed:
                return String(
                    localized:
                        "Scheduling failed for \(showName), not retried: \(notification.body)"
                )
            case .unknown:
                return String(
                    localized:
                        "Scheduling outcome unknown for \(showName), not retried: \(notification.body)"
                )
            }
        }
        if evaluation.tracked.pendingChangeSignature != nil {
            return String(localized: "Pending debounce for \(showName)")
        }
        return String(
            localized: "No notification for \(showName) (no meaningful change)"
        )
    }

    /// Requests the TVMaze updates map that covers every change since the
    /// coverage watermark. `since=` is a rolling window ending now, so the full
    /// map is needed when there is no watermark, when the gap exceeds the month
    /// window, or when the watermark is later than now (the clock moved back).
    private func fetchUpdates(at requestTime: Date) async throws -> [Int: Date] {
        guard let coveredThrough = updatesCoveredThrough,
            coveredThrough <= requestTime,
            !TVMazeUpdatePeriod.requiresUnfilteredUpdateMap(since: coveredThrough, at: requestTime)
        else {
            AppDiagnosticsLogger.breadcrumb("watchlist_refresh_updates_unfiltered")
            return try await tvMaze.allUpdatedShows()
        }
        let period = TVMazeUpdatePeriod.covering(since: coveredThrough, at: requestTime)
        return try await tvMaze.updatedShows(since: period)
    }

    /// Advances the coverage watermark after an ordinary pass, but only when the
    /// saved rows prove every change in `updates` was applied.
    ///
    /// Re-reads the repository instead of trusting this pass's own results, so a
    /// failed fetch or write, a skipped older response, or a show another refresh
    /// is still handling leaves the watermark unchanged, and the next pass's
    /// window still reaches back to it.
    private func advanceUpdatesCoverage(
        updates: [Int: Date], requestTime: Date, staleSavedIDs: Set<Int>
    ) async {
        let saved: [TrackedShow]
        do {
            saved = try await repository.all()
        } catch {
            return
        }
        // This read is the last suspension point; the write below never awaits.
        guard !Task.isCancelled else { return }
        let uncoveredCount = saved.filter {
            !$0.isPaused && !Self.isCovered($0, by: updates, staleSavedIDs: staleSavedIDs)
        }.count
        guard uncoveredCount == 0 else {
            AppDiagnosticsLogger.breadcrumb(
                "watchlist_refresh_coverage_unchanged:\(uncoveredCount)")
            return
        }

        // Step back by TVMaze's propagation delay so the next window re-checks
        // changes that were not yet published when this map was served.
        let coveredThrough = requestTime.addingTimeInterval(-TVMazeUpdatePeriod.propagationDelay)
        // Keep the later value, so an older pass finishing after a newer one
        // cannot move it back. A saved value later than the current clock can
        // only mean the clock moved backwards, so replace it. A newer pass's
        // value is never later than the clock, so it is kept.
        if let current = updatesCoveredThrough, current <= clock() {
            updatesCoveredThrough = max(current, coveredThrough)
        } else {
            updatesCoveredThrough = coveredThrough
        }
    }

    /// True when `row` already reflects the change `updates` reports for it.
    private static func isCovered(
        _ row: TrackedShow, by updates: [Int: Date], staleSavedIDs: Set<Int>
    ) -> Bool {
        guard let changedAt = updates[row.id] else { return true }
        if row.sourceUpdatedAt >= changedAt { return true }
        // Not found on TVMaze: covered only if this pass saved the stale flag
        // itself. An earlier pass's flag is not evidence, and its `lastCheckedAt`
        // cannot be trusted either: after a clock reset it may be in the future.
        return row.isStale && staleSavedIDs.contains(row.id)
    }

    /// The stored row when the show is still saved and not paused.
    private func activeRow(for showID: Int) async throws -> TrackedShow? {
        guard let row = try await repository.trackedShow(showID: showID), !row.isPaused else {
            return nil
        }
        return row
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
