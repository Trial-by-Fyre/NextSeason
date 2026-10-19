//
//  ContentViewNotificationNavigationTests.swift
//  NextSeasonTests
//

import Observation
import SwiftData
import SwiftUI
import Testing
import UIKit
import UserNotifications

@testable import NextSeason

/// Notification routing through the mounted root shell: `ContentView` hosted in a
/// window, so the real `TabView`, `NavigationStack`s, tab-change `onChange`, and
/// detail `onAppear` side effects run against the coordinator.
///
/// Limits: notification taps enter at `queueShowNavigation` (not
/// `UNUserNotificationCenter`), manual tab selection calls the `TabView`
/// binding's setter (`selectTabFromTabBar`) rather than tapping the tab bar
/// (`NavigationUITests` covers the real tap), and push animation is not observed.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ContentViewNotificationNavigationTests {
    private let container: ModelContainer
    private let repository: GatedWatchlistRepository
    private let tvMaze = RoutingTVMazeService(heldLookup: HeldLookupProgress())
    private let analytics = ObservedAnalytics()
    private let removal: WatchlistPendingRemoval
    private let coordinator = AppNavigationCoordinator()
    private let outcomes: OutcomeLog

    init() throws {
        container = try NextSeasonModelContainer.make(
            configuration: ModelConfiguration(
                "content-nav-\(UUID().uuidString)", isStoredInMemoryOnly: true))
        repository = GatedWatchlistRepository(
            base: SwiftDataWatchlistRepository(context: ModelContext(container)))
        removal = WatchlistPendingRemoval(repository: repository, analytics: analytics)
        // The undo window never expires on its own during a test.
        removal.undoWindowSecondsOverride = 600
        outcomes = OutcomeLog()
        let log = outcomes
        removal.addOutcomeHandler { log.outcomes.append($0) }
        for id in [10, 11, 82, 83] {
            tvMaze.shows[id] = Self.show(id)
        }
    }

    // MARK: - Untracked notification target from Watchlist

    @Test("Foreground tap for an untracked show keeps Search detail after tab effects")
    func foregroundUntrackedNotificationKeepsSearchDetail() async throws {
        try await assertUntrackedNotificationKeepsSearchDetail(animated: true)
    }

    @Test("Launch/background-return tap for an untracked show keeps Search detail")
    func backgroundReturnUntrackedNotificationKeepsSearchDetail() async throws {
        try await assertUntrackedNotificationKeepsSearchDetail(animated: false)
    }

    /// `animated` mirrors `NotificationRouting`: `true` for a tap while already
    /// active (animated push), `false` for launch/background return.
    private func assertUntrackedNotificationKeepsSearchDetail(animated: Bool) async throws {
        try await repository.add(Self.show(10))
        let window = try await mountLandingOnWatchlist()
        defer { unmount(window) }

        coordinator.queueShowNavigation(showID: 82, animated: animated)
        try await waitUntil { analytics.events.contains(.searchResultOpened(showID: 82)) }
        await settleMainActor()

        #expect(coordinator.selectedTab == .search)
        #expect(coordinator.searchPath.count == 1)
        #expect(analytics.events.contains(.appOpenedFromNotification(showID: 82)))
    }

    @Test("Untracked notification from Watchlist commits a pending deferred removal")
    func untrackedNotificationCommitsPendingRemoval() async throws {
        try await repository.add(Self.show(10))
        try await repository.add(Self.show(11))
        let window = try await mountLandingOnWatchlist()
        defer { unmount(window) }
        let tracked = try #require(try await repository.trackedShow(showID: 10))
        removal.requestRemoval(tracked, source: .watchlist)

        coordinator.queueShowNavigation(showID: 82, animated: true)
        try await waitUntil { !outcomes.outcomes.isEmpty }
        try await waitUntil { analytics.events.contains(.searchResultOpened(showID: 82)) }
        await settleMainActor()

        #expect(outcomes.outcomes == [.committed(showID: 10)])
        #expect(removal.pendingRemoval == nil)
        #expect(try await savedShowIDs() == [11])
        #expect(coordinator.selectedTab == .search)
        #expect(coordinator.searchPath.count == 1)
    }

    // MARK: - Manual tab selection

    @Test("Manual Watchlist to Search returns to root and commits the pending removal")
    func manualSwitchToSearchReturnsToRoot() async throws {
        try await repository.add(Self.show(10))
        let window = try await mountLandingOnWatchlist()
        defer { unmount(window) }

        // Leave a Search detail open, then go back to Watchlist.
        coordinator.selectTabFromTabBar(.search)
        coordinator.searchPath.append(Self.show(82))
        try await waitUntil { analytics.events.contains(.searchResultOpened(showID: 82)) }
        coordinator.selectTabFromTabBar(.watchlist)
        try await waitUntil { analytics.events.filter { $0 == .watchlistViewed }.count >= 2 }
        let tracked = try #require(try await repository.trackedShow(showID: 10))
        removal.requestRemoval(tracked, source: .watchlist)

        coordinator.selectTabFromTabBar(.search)
        try await waitUntil { !outcomes.outcomes.isEmpty }
        await settleMainActor()

        #expect(outcomes.outcomes == [.committed(showID: 10)])
        #expect(try await savedShowIDs().isEmpty)
        #expect(coordinator.selectedTab == .search)
        #expect(coordinator.searchPath.isEmpty)
        // The stale detail never reappeared (its onAppear would cancel a removal).
        #expect(analytics.events.filter { $0 == .searchResultOpened(showID: 82) }.count == 1)
    }

    @Test("A suspended leave-Watchlist commit cannot clear a newer notification detail")
    func delayedTabCommitCannotClearNewerNotificationDetail() async throws {
        try await repository.add(Self.show(10))
        let window = try await mountLandingOnWatchlist()
        defer { unmount(window) }
        let tracked = try #require(try await repository.trackedShow(showID: 10))
        removal.requestRemoval(tracked, source: .watchlist)
        repository.holdsRemove = true

        // The tab-change task suspends inside the commit's repository write.
        coordinator.selectTabFromTabBar(.search)
        await repository.waitUntilRemoveHeld()

        coordinator.queueShowNavigation(showID: 82, animated: true)
        try await waitUntil { analytics.events.contains(.searchResultOpened(showID: 82)) }

        repository.releaseRemove()
        try await waitUntil { outcomes.outcomes.contains(.committed(showID: 10)) }
        await settleMainActor()

        #expect(try await savedShowIDs().isEmpty)
        #expect(coordinator.selectedTab == .search)
        #expect(coordinator.searchPath.count == 1)
    }

    // MARK: - Superseded requests

    @Test("An older slow lookup cannot replace a newer notification's Search detail")
    func newerNotificationSupersedesOlderLookup() async throws {
        try await repository.add(Self.show(10))
        let window = try await mountLandingOnWatchlist()
        defer { unmount(window) }
        tvMaze.heldShowID = 82

        coordinator.queueShowNavigation(showID: 82, animated: true)
        await tvMaze.waitUntilHeld()
        coordinator.queueShowNavigation(showID: 83, animated: true)
        try await waitUntil { analytics.events.contains(.searchResultOpened(showID: 83)) }

        tvMaze.releaseHeld()
        // Wait until the held lookup has returned to the coordinator's main-actor
        // continuation, then drain it, so the assertions see its outcome.
        try await waitUntil { tvMaze.heldLookup.completedCount == 1 }
        await settleMainActor()

        #expect(coordinator.selectedTab == .search)
        #expect(coordinator.searchPath.count == 1)
        #expect(analytics.events.contains(.searchResultOpened(showID: 82)) == false)
        #expect(analytics.events.contains(.appOpenedFromNotification(showID: 82)) == false)
    }

    // MARK: - Tracked and paused targets

    @Test("Tracked notification target from Search opens Watchlist detail")
    func trackedTargetOpensWatchlistDetail() async throws {
        try await repository.add(Self.show(10))
        let window = try await mountLandingOnWatchlist()
        defer { unmount(window) }
        coordinator.selectTabFromTabBar(.search)

        coordinator.queueShowNavigation(showID: 10, animated: false)
        try await waitUntil { analytics.events.contains(.watchlistItemOpened(showID: 10)) }
        await settleMainActor()

        #expect(coordinator.selectedTab == .watchlist)
        #expect(coordinator.watchlistPath.count == 1)
        #expect(coordinator.pendingWatchlistDetail == nil)
        #expect(coordinator.searchPath.isEmpty)
    }

    @Test("Paused notification target from Search opens the Watchlist root")
    func pausedTargetOpensWatchlistRoot() async throws {
        try await repository.add(Self.show(10))
        try await repository.add(Self.show(11))
        try await repository.setPaused(true, showIDs: [11])
        let window = try await mountLandingOnWatchlist()
        defer { unmount(window) }
        coordinator.selectTabFromTabBar(.search)

        coordinator.queueShowNavigation(showID: 11, animated: false)
        try await waitUntil { analytics.events.contains(.appOpenedFromNotification(showID: 11)) }
        await settleMainActor()

        #expect(coordinator.selectedTab == .watchlist)
        #expect(coordinator.watchlistPath.isEmpty)
        #expect(coordinator.pendingWatchlistDetail == nil)
        #expect(analytics.events.contains(.watchlistItemOpened(showID: 11)) == false)
    }

    // MARK: - Harness

    /// Hosts `ContentView` and waits for the one-time landing tab (Watchlist,
    /// because each test saves a show first) and the Watchlist's first load.
    private func mountLandingOnWatchlist() async throws -> UIWindow {
        NotificationRouting.resetForTesting()
        let mapping = InMemoryShowIDMapping(map: [:])
        let root = ContentView(
            coordinator: coordinator,
            searchService: PreviewTheTVDBService(stub: .previewSearchResult),
            tvMaze: tvMaze,
            showIDMapping: mapping
        )
        .environment(\.watchlistRepository, repository)
        .environment(\.showIDMapping, mapping)
        .environment(\.watchlistPendingRemoval, removal)
        .environment(\.analytics, analytics)
        .environment(\.notificationService, AuthorizedNotifications())
        .environment(PurchaseService.preview)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        try await waitUntil { coordinator.selectedTab == .watchlist }
        try await waitUntil { analytics.events.contains(.watchlistViewed) }
        await settleMainActor()
        return window
    }

    private func unmount(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        NotificationRouting.resetForTesting()
    }

    /// Runs queued main-actor work (such as `ContentView`'s tab-change task)
    /// enqueued before this call. The main executor is a serial FIFO queue, so a
    /// job enqueued now runs after everything already scheduled.
    private func settleMainActor() async {
        await Task { @MainActor in }.value
        await Task { @MainActor in }.value
    }

    private func savedShowIDs() async throws -> Set<Int> {
        try await SwiftDataWatchlistRepository(context: ModelContext(container)).trackedShowIDs()
    }

    private static func show(_ id: Int) -> Show {
        Show(
            id: id,
            name: "Show \(id)",
            tvMazeURL: nil,
            summaryHTML: nil,
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: nil,
            ended: nil,
            network: nil,
            genres: [],
            averageRuntime: nil,
            seasons: [],
            nextEpisode: nil,
            updatedAt: .now
        )
    }
}

// MARK: - Test doubles

@MainActor
@Observable
private final class OutcomeLog {
    var outcomes: [PendingRemovalOutcome] = []
}

/// Records analytics observably so tests can wait for view side effects
/// (detail `onAppear`, Watchlist appearance) without sleeping.
@MainActor
@Observable
private final class ObservedAnalytics: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) { events.append(event) }
    func countersSnapshot() -> AnalyticsCounters { AnalyticsCounters() }
    func diagnosticsReport(
        notificationsEnabled: Bool, betaRefreshDiagnostics: BetaRefreshDiagnostics?
    ) -> String { "" }
}

/// Serves preloaded shows; optionally holds the first lookup of `heldShowID`.
private final class RoutingTVMazeService: TVMazeService, @unchecked Sendable {
    var shows: [Int: Show] = [:]
    var heldShowID: Int?
    let heldLookup: HeldLookupProgress

    init(heldLookup: HeldLookupProgress) {
        self.heldLookup = heldLookup
    }
    private var held: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func releaseHeld() {
        held?.resume()
        held = nil
    }

    func searchShows(matching query: String) async throws -> [Show] { [] }

    func lookupShow(theTVDBID: Int) async throws -> Show { throw TVMazeError.notFound }

    func show(id: Int, bypassCache: Bool) async throws -> Show {
        if id == heldShowID {
            heldShowID = nil
            await withCheckedContinuation { continuation in
                held = continuation
                started?.resume()
                started = nil
            }
            // Recorded on the main actor before returning, so the caller's
            // continuation is enqueued after this observable change.
            await MainActor.run { heldLookup.completedCount += 1 }
        }
        guard let show = shows[id] else { throw TVMazeError.notFound }
        return show
    }

    func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] { [:] }
}

@MainActor
@Observable
private final class HeldLookupProgress {
    var completedCount = 0
}

/// Production SwiftData repository with an optional hold on `remove(showID:)`.
@MainActor
private final class GatedWatchlistRepository: WatchlistRepository {
    private let base: SwiftDataWatchlistRepository
    var holdsRemove = false
    private var held: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(base: SwiftDataWatchlistRepository) {
        self.base = base
    }

    func waitUntilRemoveHeld() async {
        if held != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func releaseRemove() {
        holdsRemove = false
        held?.resume()
        held = nil
    }

    func all() async throws -> [TrackedShow] { try await base.all() }
    func trackedShow(showID: Int) async throws -> TrackedShow? {
        try await base.trackedShow(showID: showID)
    }
    func trackedShowIDs() async throws -> Set<Int> { try await base.trackedShowIDs() }
    func contains(showID: Int) async throws -> Bool { try await base.contains(showID: showID) }
    func activeShowIDs() async throws -> Set<Int> { try await base.activeShowIDs() }
    func add(_ show: Show) async throws { try await base.add(show) }

    func remove(showID: Int) async throws {
        if holdsRemove {
            await withCheckedContinuation { continuation in
                held = continuation
                started?.resume()
                started = nil
            }
        }
        try await base.remove(showID: showID)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        try await base.updateAfterRefresh(tracked)
    }
    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        try await base.setPaused(isPaused, showIDs: showIDs)
    }
    func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {
        try await base.restoreRemoved(tracked, isPaused: isPaused)
    }
    func restoreUndeliveredNotification(
        _ attempt: TrackedShow, previousLastNotifiedSignature: String?
    ) async throws -> Bool {
        try await base.restoreUndeliveredNotification(
            attempt, previousLastNotifiedSignature: previousLastNotifiedSignature)
    }
}

/// Notification permission already granted, so Watchlist shows no prompts.
@MainActor
private final class AuthorizedNotifications: NotificationManaging {
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func needsAuthorizationPrompt() async -> Bool { false }
    func deferAuthorizationPrompt() {}
    func isDenied() async -> Bool { false }
    func canDeliverVisibleAlerts() async -> Bool { true }
    func openNotificationSettings() {}
    func enableNotificationsFromSettingsEntryPoint() async {}
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        .accepted
    }
    func deliver(_ content: SeasonNotificationContent, requestIdentifier: String) async
        -> NotificationDeliveryOutcome
    { .accepted }
    func deliverAfterDelay(
        _ content: SeasonNotificationContent, requestIdentifier: String, delay: TimeInterval
    ) async -> NotificationDeliveryOutcome { .accepted }
}
