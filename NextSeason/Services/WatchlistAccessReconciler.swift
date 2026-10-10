//
//  WatchlistAccessReconciler.swift
//  NextSeason
//

import Foundation
import Observation
import os

/// Keeps saved shows' `isPaused` flags consistent with effective Plus access.
///
/// State-based, not transition-based: every call compares the *current*
/// confirmed access with the saved rows and applies `WatchlistLimitPolicy`:
/// - Unlimited (Plus, complimentary): resume every paused show.
/// - Free (confirmed lapse or Simulate Free Tier): if more than three shows are
///   active, pause all but the three oldest.
/// - Unknown (StoreKit loading or unverified): do nothing.
///
/// Because the decision only depends on current state, running it repeatedly is
/// harmless, and real entitlement changes, simulation toggles, app restarts, and
/// Watchlist loads all converge through the same code. Calls are serialized and
/// read access when they run, so an older call cannot apply a stale decision.
@Observable
@MainActor
final class WatchlistAccessReconciler {
    enum Outcome: Equatable {
        case unchanged
        case paused(Set<Int>)
        case resumed(Set<Int>)
    }

    static let pausedAlertPendingKey = "watchlistPausedAlertPending"

    /// True after a reconcile newly paused shows, until the user dismisses the
    /// alert. Persisted so a pause applied during background refresh is still
    /// announced on the next launch.
    private(set) var isPausedAlertPending: Bool

    /// Whether to present the pending alert now: only while access is confirmed
    /// free. A flag persisted by an earlier pause is never shown while access is
    /// unknown (cold launch) or after Plus has been restored, so the warning
    /// cannot be stale.
    var shouldPresentPausedAlert: Bool {
        isPausedAlertPending && access() == false
    }

    /// Bumped after any persisted change (and after the post-resume refresh) so
    /// the Watchlist UI can reload from persistence.
    private(set) var changeGeneration = 0

    private let repository: any WatchlistRepository
    private let userDefaults: UserDefaults
    private let access: @MainActor () -> Bool?
    private let waitForAccess: @MainActor () async -> Void
    private let refreshAfterResume: @MainActor () async -> Void
    private var latestRun: Task<Outcome, Never>?

    /// - Parameters:
    ///   - repository: Saved shows whose pause flags are read and written.
    ///   - userDefaults: Persists the pending "shows paused" alert flag.
    ///   - access: Confirmed effective Unlimited access, or `nil` when unknown
    ///     (`PurchaseService.confirmedWatchlistAccess`).
    ///   - waitForAccess: Suspends until the first entitlement read has finished
    ///     (`PurchaseService.waitForInitialEntitlementResolution`).
    ///   - refreshAfterResume: Replaces stale data on resumed shows. Started after
    ///     the resume is persisted and not awaited, so reactivation never depends
    ///     on it succeeding.
    init(
        repository: any WatchlistRepository,
        userDefaults: UserDefaults = .standard,
        access: @escaping @MainActor () -> Bool?,
        waitForAccess: @escaping @MainActor () async -> Void = {},
        refreshAfterResume: @escaping @MainActor () async -> Void = {}
    ) {
        self.repository = repository
        self.userDefaults = userDefaults
        self.access = access
        self.waitForAccess = waitForAccess
        self.refreshAfterResume = refreshAfterResume
        isPausedAlertPending = userDefaults.bool(forKey: Self.pausedAlertPendingKey)
    }

    /// Waits for the first StoreKit answer, then reconciles. Used before decisions
    /// that must see reconciled pause state, such as notification navigation on
    /// cold launch.
    @discardableResult
    func reconcileWhenAccessKnown() async -> Outcome {
        await waitForAccess()
        return await reconcile()
    }

    /// Applies the current access to saved shows. Waits for any earlier run first.
    @discardableResult
    func reconcile() async -> Outcome {
        let previous = latestRun
        let run = Task { @MainActor [weak self] () -> Outcome in
            _ = await previous?.value
            guard let self else { return .unchanged }
            return await self.performReconcile()
        }
        latestRun = run
        return await run.value
    }

    func acknowledgePausedAlert() {
        setPausedAlertPending(false)
    }

    private func performReconcile() async -> Outcome {
        guard let isUnlimited = access() else { return .unchanged }
        do {
            let shows = try await repository.all()
            if isUnlimited {
                // Plus is confirmed; an unread "shows paused" alert no longer
                // applies — even if the paused shows were since deleted.
                if isPausedAlertPending { setPausedAlertPending(false) }
                let ids = WatchlistLimitPolicy.showIDsToResume(in: shows)
                guard !ids.isEmpty else { return .unchanged }
                try await repository.setPaused(false, showIDs: ids)
                AppDiagnosticsLogger.breadcrumb("watchlist_resumed count=\(ids.count)")
                changeGeneration += 1
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.refreshAfterResume()
                    self.changeGeneration += 1
                }
                return .resumed(ids)
            } else {
                let ids = WatchlistLimitPolicy.showIDsToPause(in: shows)
                guard !ids.isEmpty else { return .unchanged }
                try await repository.setPaused(true, showIDs: ids)
                AppDiagnosticsLogger.breadcrumb("watchlist_paused count=\(ids.count)")
                setPausedAlertPending(true)
                changeGeneration += 1
                return .paused(ids)
            }
        } catch {
            AppDiagnosticsLogger.breadcrumb("watchlist_access_reconcile_failed")
            AppDiagnosticsLogger.logger(for: .persistence).error(
                "watchlist_access_reconcile_failed error=\(String(describing: error), privacy: .public)"
            )
            return .unchanged
        }
    }

    private func setPausedAlertPending(_ pending: Bool) {
        isPausedAlertPending = pending
        userDefaults.set(pending, forKey: Self.pausedAlertPendingKey)
    }
}
