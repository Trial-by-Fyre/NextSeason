//
//  WatchlistViewModel.swift
//  NextSeason
//

import Foundation
import SwiftUI

/// Loads, filters, and sections the local watchlist, and keeps list animations
/// in sync with undoable removals via `WatchlistPendingRemoval`.
@Observable
@MainActor
final class WatchlistViewModel {
    enum State: Equatable {
        case loaded
        case failed(String)
    }

    private(set) var state: State = .loaded
    /// Rows rendered by the list. Kept separate from `state` so `ForEach` can
    /// diff removals and animate instead of replacing the whole list.
    private(set) var shows: [TrackedShow] = []

    /// User-entered text from the watchlist search bar. Filtering is local; the
    /// full `shows` list stays intact so removals still animate correctly.
    var searchText = ""

    /// `shows` narrowed to the current search query. Matching is
    /// case- and diacritic-insensitive on the show name.
    var filteredShows: [TrackedShow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return shows }
        return shows.filter { $0.name.localizedStandardContains(query) }
    }

    /// Non-empty status sections for the current filter, in display order.
    /// Empty sections are omitted. Coming Soon sorts by premiere date (soonest
    /// first); every other section sorts alphabetically by show name.
    var filteredSectionGroups: [WatchlistSectionGroup] {
        Self.sectionGroups(from: filteredShows)
    }

    /// Paused shows (Plus lapsed) matching the current filter, alphabetical.
    /// Rendered in their own section below every status section.
    var filteredPausedShows: [TrackedShow] {
        filteredShows.filter(\.isPaused).sorted(by: Self.alphabeticalSort)
    }

    /// Groups active shows into non-empty sections in `WatchlistSection` display
    /// order. Paused shows are excluded — their stored status may be stale.
    ///
    /// Coming Soon sorts by premiere date (soonest first); every other section
    /// sorts alphabetically. Exposed as `static` for unit tests.
    static func sectionGroups(from shows: [TrackedShow]) -> [WatchlistSectionGroup] {
        var buckets: [WatchlistSection: [TrackedShow]] = [:]
        for show in shows where !show.isPaused {
            let section = WatchlistSection.section(for: show.nextSeason)
            buckets[section, default: []].append(show)
        }

        return WatchlistSection.allCases.compactMap { section in
            guard var sectionShows = buckets[section], !sectionShows.isEmpty else {
                return nil
            }
            if section == .comingSoon {
                sectionShows.sort(by: Self.comingSoonSort)
            } else {
                sectionShows.sort(by: Self.alphabeticalSort)
            }
            return WatchlistSectionGroup(section: section, shows: sectionShows)
        }
    }

    private static func comingSoonSort(_ lhs: TrackedShow, _ rhs: TrackedShow) -> Bool {
        switch (lhs.nextSeason, rhs.nextSeason) {
        case (.scheduled(_, let leftDate), .scheduled(_, let rightDate)):
            if leftDate != rightDate { return leftDate < rightDate }
            return alphabeticalSort(lhs, rhs)
        default:
            return alphabeticalSort(lhs, rhs)
        }
    }

    private static func alphabeticalSort(_ lhs: TrackedShow, _ rhs: TrackedShow) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    var pendingRemoval: TrackedShow? { removalCoordinator.pendingRemoval }

    private let repository: any WatchlistRepository
    private let refreshService: WatchlistRefreshService?
    private let removalCoordinator: WatchlistPendingRemoval
    private let analytics: any AnalyticsTracking
    /// Applies confirmed Plus access to pause flags before each load, so the list
    /// never shows a split that disagrees with current access.
    private let accessReconciler: WatchlistAccessReconciler?

    private var reloadGeneration = 0

    init(
        repository: any WatchlistRepository,
        refreshService: WatchlistRefreshService? = nil,
        removalCoordinator: WatchlistPendingRemoval,
        analytics: any AnalyticsTracking,
        accessReconciler: WatchlistAccessReconciler? = nil
    ) {
        self.repository = repository
        self.refreshService = refreshService
        self.removalCoordinator = removalCoordinator
        self.analytics = analytics
        self.accessReconciler = accessReconciler

        removalCoordinator.addOutcomeHandler { [weak self] outcome in
            self?.handleOutcome(outcome)
        }
    }

    /// Re-reads the watchlist from persistence without flashing a loading
    /// spinner when the reload token bumps in quick succession.
    /// Concurrent reloads keep only the newest result so a slower older fetch
    /// cannot overwrite fresher data.
    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        await accessReconciler?.reconcile()
        do {
            let fetched = try await repository.all()
            guard generation == reloadGeneration else { return }
            shows = fetched
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration else { return }
            state = .failed(error.localizedDescription)
            analytics.trackNonFatalError(error, context: "watchlist_reload")
        }
    }

    /// Brief feedback after a pull-to-refresh that could not update some or all
    /// shows (usually offline). Only user-initiated refreshes set it; foreground
    /// and background refresh failures stay silent. Saved rows are kept as-is.
    private(set) var refreshFailureMessage: String?

    static let refreshFailedMessage = String(
        localized: "Couldn't refresh your Watchlist. Check your connection and try again."
    )
    static let refreshPartlyFailedMessage = String(
        localized: "Some shows couldn't be refreshed. Try again later."
    )

    /// How long the pull-to-refresh failure notice stays up.
    static let refreshFailureDisplaySeconds: TimeInterval = 4
    private var refreshFailureDismissal: Task<Void, Never>?

    /// Commits any pending removal, force-refreshes tracked shows, then reloads.
    func refreshFromNetwork() async {
        clearRefreshFailure()
        await removalCoordinator.commitPendingRemovalIfNeeded()
        // Pull-to-refresh is interactive — update rows silently; don't alert.
        let outcome = await refreshService?.refreshAll(force: true, deliverNotifications: false)
        await reload()
        guard let message = Self.refreshFailureMessage(for: outcome) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { refreshFailureMessage = message }
        // Transient notice: hide it after a few seconds unless replaced or dismissed.
        refreshFailureDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.refreshFailureDisplaySeconds))
            guard !Task.isCancelled else { return }
            self?.clearRefreshFailure()
        }
    }

    func clearRefreshFailure() {
        refreshFailureDismissal?.cancel()
        refreshFailureDismissal = nil
        guard refreshFailureMessage != nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) { refreshFailureMessage = nil }
    }

    /// Pull-to-refresh feedback for a refresh outcome. Cancelled runs (`nil`)
    /// and runs without failures show nothing.
    static func refreshFailureMessage(for outcome: WatchlistRefreshOutcome?) -> String? {
        switch outcome?.completion {
        case nil, .cancelled:
            return nil
        case .aborted:
            return refreshFailedMessage
        case .finished(let counts):
            guard counts.failed > 0 else { return nil }
            let nothingSucceeded = counts.refreshed == 0 && counts.skippedUnchanged == 0
            return nothingSucceeded ? refreshFailedMessage : refreshPartlyFailedMessage
        }
    }

    /// Called when the list reappears (pop from Show Details, tab return). A
    /// deferred removal started on another screen is persisted now and its row
    /// leaves at once, instead of lingering until the undo window times out.
    /// The toast's Undo still restores it.
    func persistDeferredRemovalOnReturn() {
        guard let showID = removalCoordinator.deferredRemovalShowID else { return }
        removeShowAnimated(showID: showID)
        removalCoordinator.persistDeferredRemovalKeepingUndo()
    }

    /// Starts the undo window for removing `tracked`. The row stays visible
    /// until the removal is committed or the user confirms with OK.
    func requestRemoval(
        _ tracked: TrackedShow,
        source: WatchlistActionSource = .watchlist
    ) {
        removalCoordinator.requestRemoval(tracked, source: source)
    }

    /// Swipe-to-delete: drops rows from the list immediately, then persists and
    /// shows an informational undo toast. Must run synchronously inside
    /// `.onDelete` so `List` item counts stay consistent.
    func deleteImmediately(
        at offsets: IndexSet,
        in sectionShows: [TrackedShow]
    ) {
        let targets = offsets.compactMap { index -> TrackedShow? in
            sectionShows.indices.contains(index) ? sectionShows[index] : nil
        }
        for tracked in targets {
            deleteImmediately(tracked)
        }
    }

    /// Immediate delete shared by swipe-to-delete and the VoiceOver row action.
    /// Drops the row from the list synchronously, then persists and shows an
    /// informational undo toast. Distinct from star-button `requestRemoval`.
    func deleteImmediately(_ tracked: TrackedShow) {
        removeShow(showID: tracked.id)
        removalCoordinator.requestImmediateRemoval(tracked, source: .watchlist)
    }

    func undoPendingRemoval() async {
        _ = await removalCoordinator.undoRemoval()
    }

    /// Puts a show back into the in-memory list (e.g. after undoing an immediate delete).
    func restoreShowAnimated(_ tracked: TrackedShow) {
        guard !shows.contains(where: { $0.id == tracked.id }) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            shows.append(tracked)
            state = .loaded
        }
    }

    func commitPendingRemovalIfNeeded() async {
        await removalCoordinator.commitPendingRemovalIfNeeded()
    }

    /// Removes a row from the displayed list. Wrap in `withAnimation` at the call
    /// site so SwiftUI can run the standard list removal animation.
    func removeShow(showID: Int) {
        guard let index = shows.firstIndex(where: { $0.id == showID }) else { return }
        shows.remove(at: index)
        state = .loaded
    }

    func removeShowAnimated(showID: Int) {
        withAnimation(.easeInOut(duration: 0.35)) {
            removeShow(showID: showID)
        }
    }

    /// Single path for keeping the displayed list aligned with pending-removal
    /// transitions reported by `WatchlistPendingRemoval`.
    func handleOutcome(_ outcome: PendingRemovalOutcome) {
        switch outcome {
        case .committed(let showID), .replaced(let showID):
            removeShowAnimated(showID: showID)
        case .undone(let showID):
            Task { await restoreRowIfNeeded(showID: showID) }
        case .cancelled:
            break
        case .failed(let showID):
            Task { await reconcileAfterFailure(showID: showID) }
        }
    }

    func isPendingRemoval(_ tracked: TrackedShow) -> Bool {
        pendingRemoval?.id == tracked.id
    }

    /// Restores a row after immediate-mode undo or a failed immediate delete.
    private func restoreRowIfNeeded(showID: Int) async {
        guard !shows.contains(where: { $0.id == showID }) else { return }
        do {
            if let tracked = try await repository.trackedShow(showID: showID) {
                restoreShowAnimated(tracked)
            } else {
                await reload()
            }
        } catch {
            await reload()
        }
    }

    /// Keeps the list aligned with persistence when a deferred commit fails or
    /// an immediate delete could not be persisted.
    private func reconcileAfterFailure(showID: Int) async {
        await restoreRowIfNeeded(showID: showID)
        if shows.contains(where: { $0.id == showID }) == false {
            await reload()
        }
    }
}
