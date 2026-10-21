//
//  WatchlistPendingRemoval.swift
//  NextSeason
//

import Foundation

/// Holds a watchlist removal undo window, shared by the watchlist list, show
/// detail, and search flows.
///
/// Two presentation modes:
/// - **Deferred** (star / detail / search): row stays until the window ends or
///   the user confirms; persistence runs on commit.
/// - **Immediate** (swipe-to-delete): persistence runs right away and the toast
///   is informational; Undo restores the show.
@Observable
@MainActor
final class WatchlistPendingRemoval {
    private enum Mode {
        case deferred
        case immediate
    }

    private(set) var pendingRemoval: TrackedShow?

    /// The show whose deferred removal is still in its undo window. Its row is
    /// still saved and active, but it is about to leave, so free-tier
    /// reconciliation must not spend one of the free slots on it.
    var deferredRemovalShowID: Int? {
        pendingMode == .deferred ? pendingRemoval?.id : nil
    }

    /// Set when deferred persistence fails after the undo window ends.
    private(set) var removalErrorMessage: String?

    /// Increments whenever `lastOutcome` changes so SwiftUI can observe outcomes.
    private(set) var outcomeGeneration = 0
    private(set) var lastOutcome: PendingRemovalOutcome?

    static var undoWindowSeconds: TimeInterval {
        AccessibilityPreferences.undoRemovalWindowSeconds()
    }

    private let repository: any WatchlistRepository
    private let analytics: any AnalyticsTracking
    private let purchases: PurchaseService
    private var commitRemovalTask: Task<Void, Never>?
    private var pendingRemovalSource: WatchlistActionSource?
    private var pendingMode: Mode = .deferred
    private var outcomeHandlers: [@MainActor (PendingRemovalOutcome) -> Void] = []

    /// Test override for the undo window; nil uses the accessibility-aware default.
    var undoWindowSecondsOverride: TimeInterval?

    private var undoWindowSeconds: TimeInterval {
        undoWindowSecondsOverride ?? Self.undoWindowSeconds
    }

    init(
        repository: any WatchlistRepository,
        analytics: any AnalyticsTracking,
        purchases: PurchaseService = .preview
    ) {
        self.repository = repository
        self.analytics = analytics
        self.purchases = purchases
    }

    /// Registers a handler invoked on every significant pending-removal transition.
    func addOutcomeHandler(_ handler: @escaping @MainActor (PendingRemovalOutcome) -> Void) {
        outcomeHandlers.append(handler)
    }

    func clearRemovalError() {
        removalErrorMessage = nil
    }

    /// Removes `tracked` from persistence only after the undo window expires or
    /// `commitPendingRemovalIfNeeded()` runs.
    func requestRemoval(
        _ tracked: TrackedShow,
        source: WatchlistActionSource
    ) {
        commitRemovalTask?.cancel()
        AppDiagnosticsLogger.logTaskCancel("undo_removal_timer")
        removalErrorMessage = nil

        // Only one undo window at a time: finalize the previous show so its
        // removal is not lost when the user untracks another.
        finalizeReplacedPendingRemoval()

        pendingMode = .deferred
        pendingRemovalSource = source
        performRequestRemoval(tracked)
    }

    /// Persists removal immediately, then shows the undo toast. Undo restores
    /// the show to the repository; OK / timeout only dismisses the toast.
    ///
    /// Callers should update list UI synchronously before invoking this so
    /// `List` + `.onDelete` stay consistent.
    func requestImmediateRemoval(
        _ tracked: TrackedShow,
        source: WatchlistActionSource
    ) {
        commitRemovalTask?.cancel()
        AppDiagnosticsLogger.logTaskCancel("undo_removal_timer")
        removalErrorMessage = nil

        finalizeReplacedPendingRemoval()

        pendingMode = .immediate
        pendingRemovalSource = source
        pendingRemoval = tracked

        AppDiagnosticsLogger.logTaskStart("immediate_removal")
        commitRemovalTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.remove(showID: tracked.id)
                self.analytics.track(.watchlistRemoved(source: source, showID: tracked.id))
                self.emitOutcome(.committed(showID: tracked.id))
            } catch {
                self.analytics.trackNonFatalError(error, context: "watchlist_remove")
                self.removalErrorMessage = WatchlistTracking.updateFailedMessage
                self.clearPendingPresentation()
                self.emitOutcome(.failed(showID: tracked.id))
                AppDiagnosticsLogger.logTaskComplete("immediate_removal")
                return
            }

            // Informational toast window — dismiss only; already persisted.
            try? await Task.sleep(for: .seconds(self.undoWindowSeconds))
            guard !Task.isCancelled else {
                AppDiagnosticsLogger.logTaskCancel("immediate_removal")
                return
            }
            guard self.pendingRemoval?.id == tracked.id else { return }
            self.clearPendingPresentation()
            AppDiagnosticsLogger.logTaskComplete("immediate_removal")
        }
    }

    /// Switches a deferred removal to immediate mode: persists it now and keeps
    /// the toast up, so Undo restores the show the same way it does after a swipe.
    ///
    /// For returning to the Watchlist after removing a show elsewhere (Show
    /// Details, Search). Deferred mode keeps the row in place only for the screen
    /// whose star was tapped. On the Watchlist the row would otherwise linger
    /// until the undo window timed out. The toast restarts its full window.
    func persistDeferredRemovalKeepingUndo() {
        guard pendingMode == .deferred, let tracked = pendingRemoval else { return }
        let source = pendingRemovalSource ?? .watchlist
        commitRemovalTask?.cancel()
        commitRemovalTask = nil
        // Clear first so `requestImmediateRemoval` does not also finalize this
        // same show as a replaced deferred removal.
        clearPendingPresentation()
        requestImmediateRemoval(tracked, source: source)
    }

    /// Cancels a deferred removal, or restores an immediately deleted show.
    @discardableResult
    func undoRemoval() async -> TrackedShow? {
        commitRemovalTask?.cancel()
        commitRemovalTask = nil
        guard let tracked = pendingRemoval else { return nil }
        let showID = tracked.id
        let mode = pendingMode

        if mode == .immediate {
            do {
                try await restore(tracked)
            } catch {
                analytics.trackNonFatalError(error, context: "watchlist_restore")
                removalErrorMessage = WatchlistTracking.updateFailedMessage
                return nil
            }
        }

        clearPendingPresentation()
        emitOutcome(.undone(showID: showID))
        return tracked
    }

    /// Dismisses the toast when navigating away. Deferred removals are cancelled
    /// (still persisted, so the show stays tracked). Immediate removals keep the
    /// delete and only hide the toast.
    func dismissPendingRemovalForNavigation() {
        guard let tracked = pendingRemoval else { return }
        let showID = tracked.id
        let mode = pendingMode
        commitRemovalTask?.cancel()
        commitRemovalTask = nil
        clearPendingPresentation()
        if mode == .deferred {
            emitOutcome(.cancelled(showID: showID))
        }
    }

    /// Forces any in-flight undoable removal to its terminal state (e.g. before
    /// refresh or leaving a screen where the toast would otherwise outlive the
    /// context). Deferred: persists. Immediate: dismisses toast only.
    func commitPendingRemovalIfNeeded() async {
        await commitPendingRemoval(cancelTimer: true)
    }

    /// OK button entry point: cancels the undo timer and dismisses the toast on
    /// the tap turn, then persists in a follow-up task.
    ///
    /// Prefer this over `Task { await commitPendingRemovalIfNeeded() }` from a
    /// button action so a delayed MainActor hop cannot leave the toast visible
    /// until the timer fires.
    func confirmPendingRemoval() {
        guard let work = beginCommit(cancelTimer: true) else { return }
        Task { [weak self] in
            await self?.persistRemoval(
                work.tracked,
                source: work.source,
                outcome: .committed(showID: work.showID)
            )
        }
    }

    private func finalizeReplacedPendingRemoval() {
        guard let pending = pendingRemoval else { return }
        let previous = pending
        let previousSource = pendingRemovalSource ?? .watchlist
        let previousMode = pendingMode
        clearPendingPresentation()

        if previousMode == .deferred {
            Task { [weak self] in
                await self?.persistRemoval(
                    previous,
                    source: previousSource,
                    outcome: .replaced(showID: previous.id)
                )
            }
        }
        // Immediate replacements are already persisted; nothing to do.
    }

    private func performRequestRemoval(_ tracked: TrackedShow) {
        pendingRemoval = tracked

        AppDiagnosticsLogger.logTaskStart("undo_removal_timer")
        commitRemovalTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.undoWindowSeconds))
            guard !Task.isCancelled else {
                AppDiagnosticsLogger.logTaskCancel("undo_removal_timer")
                return
            }
            // Do not cancel this task from inside `commitPendingRemoval` — a
            // cancellation-aware repository would otherwise abort the remove.
            await self.commitPendingRemoval(cancelTimer: false)
            AppDiagnosticsLogger.logTaskComplete("undo_removal_timer")
        }
    }

    private func commitPendingRemoval(cancelTimer: Bool) async {
        guard let work = beginCommit(cancelTimer: cancelTimer) else { return }
        await persistRemoval(
            work.tracked,
            source: work.source,
            outcome: .committed(showID: work.showID)
        )
    }

    /// Snapshot of a deferred removal that still needs persistence.
    private struct CommitWork {
        let tracked: TrackedShow
        let source: WatchlistActionSource
        let showID: Int
    }

    /// Cancels the undo timer (when requested) and clears toast presentation.
    /// Returns work to persist for deferred mode; `nil` when there is nothing
    /// left to write (no pending item, or immediate-mode dismiss-only).
    private func beginCommit(cancelTimer: Bool) -> CommitWork? {
        if cancelTimer {
            commitRemovalTask?.cancel()
        }
        commitRemovalTask = nil

        guard let tracked = pendingRemoval else { return nil }

        if pendingMode == .immediate {
            clearPendingPresentation()
            return nil
        }

        let source = pendingRemovalSource ?? .watchlist
        let showID = tracked.id

        // End the undo window as soon as commit begins so Undo cannot race with
        // an in-flight `repository.remove`.
        //
        // Note for future cloud / suspending persistence: clearing `pendingRemoval`
        // here means Search/Detail may refresh while the show is still persisted
        // and briefly treat it as tracked again. A richer model that distinguishes
        // `.pending` from `.committing(showID:)` would keep both states untracked
        // for effective-tracking until delete finishes. Not needed for the local
        // SwiftData repository, which completes remove before observation resumes.
        clearPendingPresentation()

        return CommitWork(tracked: tracked, source: source, showID: showID)
    }

    private func persistRemoval(
        _ tracked: TrackedShow,
        source: WatchlistActionSource,
        outcome: PendingRemovalOutcome
    ) async {
        // After the undo window ends, finish persistence even if the SwiftUI /
        // lifecycle task that started commit is cancelled (tab switch, refresh).
        await Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.repository.remove(showID: tracked.id)
                // Defensive: also covers the replace-pending path which persists a
                // prior show without going through `commitPendingRemoval`.
                if self.pendingRemoval?.id == tracked.id {
                    self.clearPendingPresentation()
                }
                self.analytics.track(.watchlistRemoved(source: source, showID: tracked.id))
                self.emitOutcome(outcome)
            } catch {
                // This task is unstructured, so caller cancellation should not
                // reach here. Any failure (including unexpected cancellation)
                // surfaces so the user can retry.
                self.analytics.trackNonFatalError(error, context: "watchlist_remove")
                self.removalErrorMessage = WatchlistTracking.updateFailedMessage
                if self.pendingRemoval?.id == tracked.id {
                    self.clearPendingPresentation()
                }
                self.emitOutcome(.failed(showID: tracked.id))
            }
        }.value
    }

    /// Re-inserts a previously tracked show, preserving next-season and refresh
    /// fields and its original `dateAdded` (so it is the same saved row again).
    private func restore(_ tracked: TrackedShow) async throws {
        await purchases.waitForInitialEntitlementResolution()
        let activeCount = try await repository.activeShowIDs().count
        let isPaused =
            tracked.isPaused
            || !WatchlistLimitPolicy.canAddShow(
                currentCount: activeCount,
                isUnlimited: purchases.isUnlimitedWatchlist
            )
        try await repository.restoreRemoved(tracked, isPaused: isPaused)
    }

    private func clearPendingPresentation() {
        pendingRemoval = nil
        pendingRemovalSource = nil
        pendingMode = .deferred
    }

    private func emitOutcome(_ outcome: PendingRemovalOutcome) {
        lastOutcome = outcome
        outcomeGeneration += 1
        for handler in outcomeHandlers {
            handler(outcome)
        }
    }
}
