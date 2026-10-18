//
//  DiagnosticsSimulatedUpdateRunner.swift
//  NextSeason
//

import Foundation

/// Runs a two-step simulated season update through the real `WatchlistRefreshService`,
/// without touching the user's normal watchlist repository or live TVMaze.
///
/// Uses an in-memory `SimulatedWatchlistRepository` and `DiagnosticsSimulatedDataProvider`
/// so beta / TestFlight validation can exercise status recompute + notification
/// decisions end-to-end with fake show data.
@MainActor
final class DiagnosticsSimulatedUpdateRunner {
    private let dataProvider: DiagnosticsSimulatedDataProvider
    private let repository: SimulatedWatchlistRepository
    private let notificationService: any NotificationManaging
    private let analytics: any AnalyticsTracking
    private let refreshService: WatchlistRefreshService
    private let diagnostics: BetaRefreshDiagnostics
    private let clock: @Sendable () -> Date
    private var isSeeded = false
    private var pipelineTemplate: TrackedShow?

    init(
        dataProvider: DiagnosticsSimulatedDataProvider = DiagnosticsSimulatedDataProvider(),
        pipelineTemplate: TrackedShow? = nil,
        notifications: any NotificationManaging,
        diagnostics: BetaRefreshDiagnostics,
        analytics: any AnalyticsTracking,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        if let pipelineTemplate {
            // Prefer a real watchlist show's identity so notification copy looks familiar.
            self.dataProvider = DiagnosticsSimulatedDataProvider(
                showID: pipelineTemplate.id,
                showName: pipelineTemplate.name,
                clock: clock
            )
            self.pipelineTemplate = pipelineTemplate
        } else {
            self.dataProvider = dataProvider
            self.pipelineTemplate = nil
        }
        self.repository = SimulatedWatchlistRepository()
        self.notificationService = notifications
        self.analytics = analytics
        self.diagnostics = diagnostics
        self.clock = clock
        self.refreshService = WatchlistRefreshService(
            tvMaze: self.dataProvider,
            repository: repository,
            notifications: notifications,
            analytics: analytics,
            diagnostics: diagnostics,
            clock: clock
        )
    }

    /// The simulated show's ID (the template show's, when one was given).
    var showID: Int { dataProvider.showID }

    var dataPhaseLabel: String {
        dataProvider.phaseLabel
    }

    func resetScenario() {
        repository.removeAll()
        dataProvider.reset()
        isSeeded = false
    }

    /// Advances the two-step simulated pipeline once and returns a human-readable summary.
    ///
    /// 1. First call (if not seeded): seeds undated / baseline tracked state, then
    ///    force-refreshes against the provider's current phase (usually baseline).
    /// 2. Provider advances to `.updated` after the run.
    /// 3. Second call: force-refreshes against dated season data so
    ///    `StatusChangeDetector` can choose a notification; then resets the scenario.
    ///
    /// Unavailable when `BetaBuildConfiguration.isAvailable` is false.
    @discardableResult
    func runNextStep() async -> String {
        let betaValidationAvailable = await MainActor.run {
            BetaBuildConfiguration.isAvailable
        }
        guard betaValidationAvailable else {
            return String(
                localized: "Simulated scenarios are unavailable in production builds."
            )
        }

        if !isSeeded {
            repository.seed(makeInitialTracked(at: clock()))
            isSeeded = true
        }

        let phase = dataProvider.currentPhase
        let outcome = await refreshService.refreshAll(force: true)

        let tracked = repository.show(id: dataProvider.showID)
        let statusSummary =
            tracked?.nextSeason.headlineSummary
            ?? String(localized: "No simulated show found")
        let notificationDecision =
            outcome?.notificationDecision ?? String(localized: "Refresh did not complete")
        let summary = String(
            localized:
                "Step \(phase.stepNumber) (\(phase.shortLabel)): \(statusSummary). \(notificationDecision)"
        )

        diagnostics.recordSimulatedScenarioSummary(summary)

        // A failed alert left pending: stay on the updated step so the next tap
        // retries it, as a real refresh would (R03).
        if phase == .updated, hasPendingRetry {
            return summary
        }
        dataProvider.advanceAfterRun()

        // Completed the "updated" step — clear so the next tap starts from seed again.
        if phase == .updated {
            resetScenario()
        }

        return summary
    }

    /// True when the simulated show has a pending signature, which in this
    /// dated scenario means a failed delivery is waiting to be retried.
    private var hasPendingRetry: Bool {
        repository.show(id: dataProvider.showID)?.pendingChangeSignature != nil
    }

    /// Seeds fake data with a dated new season, runs the real refresh + notification
    /// decision path, and schedules delivery after a short delay for background testing.
    ///
    /// Unlike `runNextStep`, this jumps straight to the updated phase and wraps
    /// notification delivery so the alert fires ~5–10s later (easier to background
    /// the app and verify a banner). Resets the scenario when finished.
    @discardableResult
    func runDelayedNewSeasonNotification(
        delayRange: ClosedRange<TimeInterval> = 5...10
    ) async -> String {
        let betaValidationAvailable = await MainActor.run {
            BetaBuildConfiguration.isAvailable
        }
        guard betaValidationAvailable else {
            return String(
                localized: "Delayed pipeline tests are unavailable in production builds."
            )
        }

        // A failed alert from the previous run is still pending: run again on
        // the same data so it is retried, instead of starting over (R03).
        if !hasPendingRetry {
            resetScenario()
            repository.seed(makeInitialTracked(at: clock()))
            dataProvider.forcePhase(.updated)
            isSeeded = true
        }

        let delay = TimeInterval.random(in: delayRange)
        let delayedNotifications = DiagnosticsDelayedNotificationDelivering(
            service: notificationService,
            delay: delay
        )
        let pipelineRefresh = WatchlistRefreshService(
            tvMaze: dataProvider,
            repository: repository,
            notifications: delayedNotifications,
            analytics: analytics,
            diagnostics: diagnostics,
            clock: clock
        )

        let outcome = await pipelineRefresh.refreshAll(force: true)

        let tracked = repository.show(id: dataProvider.showID)
        let statusSummary =
            tracked?.nextSeason.headlineSummary
            ?? String(localized: "No simulated show found")
        let notificationDecision =
            outcome?.notificationDecision ?? String(localized: "Refresh did not complete")
        let delaySeconds = Int(delay.rounded())
        let summary = String(
            localized:
                "Delayed pipeline (\(delaySeconds)s): \(statusSummary). \(notificationDecision)"
        )

        diagnostics.recordSimulatedScenarioSummary(summary)
        if !hasPendingRetry {
            resetScenario()
        }

        return summary
    }

    private func makeInitialTracked(at date: Date) -> TrackedShow {
        if let pipelineTemplate {
            return DiagnosticsSimulatedData.pipelineSeed(from: pipelineTemplate, at: date)
        }
        return TrackedShow(
            id: dataProvider.showID,
            name: dataProvider.showName,
            posterMediumURL: nil,
            summaryHTML:
                "<p>Beta diagnostics / simulated show. This is fake data for TestFlight validation only.</p>",
            tvMazeURL: nil,
            status: .running,
            nextSeason: .returningNoSeasonYet,
            sourceUpdatedAt: date.addingTimeInterval(-86_400),
            lastCheckedAt: date.addingTimeInterval(-86_400),
            dateAdded: date
        )
    }
}

/// In-memory watchlist used only by simulated refresh runs (never SwiftData).
@MainActor
private final class SimulatedWatchlistRepository: WatchlistRepository {
    private var shows: [Int: TrackedShow] = [:]

    func seed(_ tracked: TrackedShow) {
        shows[tracked.id] = tracked
    }

    func show(id: Int) -> TrackedShow? {
        shows[id]
    }

    func removeAll() {
        shows.removeAll()
    }

    func all() async throws -> [TrackedShow] {
        shows.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    func trackedShow(showID: Int) async throws -> TrackedShow? {
        shows[showID]
    }

    func trackedShowIDs() async throws -> Set<Int> {
        Set(shows.keys)
    }

    func contains(showID: Int) async throws -> Bool {
        shows[showID] != nil
    }

    func add(_ show: Show) async throws {
        guard shows[show.id] == nil else { return }
        shows[show.id] = TrackedShow(from: show)
    }

    func remove(showID: Int) async throws {
        shows.removeValue(forKey: showID)
    }

    func updateAfterRefresh(_ tracked: TrackedShow) async throws {
        shows[tracked.id] = tracked
    }

    func setPaused(_ isPaused: Bool, showIDs: Set<Int>) async throws {
        for id in showIDs { shows[id]?.isPaused = isPaused }
    }

    func restoreRemoved(_ tracked: TrackedShow, isPaused: Bool) async throws {
        guard shows[tracked.id] == nil else { return }
        var row = tracked
        row.isPaused = isPaused
        shows[tracked.id] = row
    }

    /// Same guard as the app's repositories, so simulations retry the same way.
    @discardableResult
    func restoreUndeliveredNotification(
        _ attempt: TrackedShow, previousLastNotifiedSignature: String?
    ) async throws -> Bool {
        guard let stored = shows[attempt.id],
            StatusChangeDetector.isStillCurrent(stored, decidedBy: attempt)
        else { return false }
        shows[attempt.id]?.lastNotifiedSignature = previousLastNotifiedSignature
        shows[attempt.id]?.pendingChangeSignature = attempt.lastNotifiedSignature
        return true
    }
}

extension DiagnosticsSimulatedDataProvider.Phase {
    fileprivate var stepNumber: String {
        switch self {
        case .baseline: "1"
        case .updated: "2"
        }
    }

    fileprivate var shortLabel: String {
        switch self {
        case .baseline: String(localized: "baseline fake data")
        case .updated: String(localized: "updated fake data")
        }
    }
}

extension NextSeasonStatus {
    fileprivate var headlineSummary: String {
        switch self {
        case .airing(let season):
            String(localized: "Season \(season) airing")
        case .scheduled(let season, let premiere):
            String(
                localized:
                    "Season \(season) premieres \(TVMazeDate.calendarDayString(premiere))"
            )
        case .announcedUndated(let season):
            String(localized: "Season \(season) announced without a date")
        case .returningNoSeasonYet:
            String(localized: "Returning, no season announced yet")
        case .ended:
            String(localized: "Ended")
        case .unknown:
            String(localized: "Unknown")
        }
    }
}
