//
//  DiagnosticsSimulatedDataProvider.swift
//  NextSeason
//

import Foundation
import Synchronization

/// Reserved show identity helpers for beta-only simulated update scenarios.
/// Never written to the real watchlist repository.
nonisolated enum DiagnosticsSimulatedData {
    static let showID = 777_777
    static let showName = "Beta diagnostics / simulated"

    /// Uses the production formatter with a fictional premiere-date announcement.
    /// This sample is only delivered by Diagnostics; it never changes watchlist data.
    static func notificationContent(from tracked: TrackedShow) -> SeasonNotificationContent {
        // Local noon keeps the screenshot date stable in the production local-date formatter.
        let premiere = Calendar.current.date(
            from: DateComponents(year: 2026, month: 10, day: 22, hour: 12)
        )!
        return SeasonNotificationContent(
            showID: tracked.id,
            showName: tracked.name,
            status: .scheduled(season: 4, premiere: premiere)
        )
    }

    /// Seeds the simulated pipeline with a watchlist show reset to an undated state
    /// so the next "updated" fetch can produce a meaningful status change.
    static func pipelineSeed(from tracked: TrackedShow, at date: Date) -> TrackedShow {
        TrackedShow(
            id: tracked.id,
            name: tracked.name,
            posterMediumURL: tracked.posterMediumURL,
            summaryHTML: tracked.summaryHTML,
            tvMazeURL: tracked.tvMazeURL,
            status: tracked.status,
            nextSeason: .returningNoSeasonYet,
            sourceUpdatedAt: date.addingTimeInterval(-86_400),
            lastCheckedAt: date.addingTimeInterval(-86_400),
            dateAdded: tracked.dateAdded
        )
    }
}

/// Fake `TVMazeService` for beta validation: a two-phase machine that returns
/// baseline (undated next season) data first, then updated (dated) season data.
///
/// Phase mutations are guarded by `Mutex` because refresh may call into this
/// provider off the main actor while the diagnostics runner advances phase on
/// the main actor.
final class DiagnosticsSimulatedDataProvider: TVMazeService, Sendable {
    /// Which fake payload `show(id:)` should return until the runner advances.
    enum Phase: Sendable {
        case baseline
        case updated
    }

    let showID: Int
    let showName: String

    private let phase = Mutex<Phase>(.baseline)
    private let clock: @Sendable () -> Date

    init(
        showID: Int = DiagnosticsSimulatedData.showID,
        showName: String = DiagnosticsSimulatedData.showName,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.showID = showID
        self.showName = showName
        self.clock = clock
    }

    /// Which fake payload the next `show(id:)` call will return.
    var currentPhase: Phase {
        phase.withLock { $0 }
    }

    /// Localized label for the diagnostics UI (baseline vs updated payload).
    var phaseLabel: String {
        switch currentPhase {
        case .baseline:
            String(localized: "Baseline (undated next season)")
        case .updated:
            String(localized: "Updated (dated next season)")
        }
    }

    /// Returns the machine to the undated baseline payload.
    func reset() {
        phase.withLock { $0 = .baseline }
    }

    /// Jumps to a specific phase without waiting for `advanceAfterRun`.
    func forcePhase(_ newPhase: Phase) {
        phase.withLock { $0 = newPhase }
    }

    /// Flips baseline ↔ updated after each simulated refresh step.
    func advanceAfterRun() {
        phase.withLock { $0 = $0 == .baseline ? .updated : .baseline }
    }

    func searchShows(matching query: String) async throws -> [Show] { [] }

    /// Diagnostics never exercise TheTVDB resolve; always not found.
    func lookupShow(theTVDBID: Int) async throws -> Show {
        throw TVMazeError.notFound
    }

    /// Only the reserved diagnostics `showID` is served; other ids throw `.notFound`.
    func show(id: Int, bypassCache: Bool) async throws -> Show {
        guard id == showID else {
            throw TVMazeError.notFound
        }
        return makeShow(for: currentPhase)
    }

    /// Always marks the simulated show as changed so refresh policy never skips it
    /// when `force` is false — simulations must re-fetch every run.
    func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        [showID: clock()]
    }

    private func makeShow(for phase: Phase) -> Show {
        let referenceDate = clock()
        let airedSeasons = [
            Season(
                id: 1,
                number: 1,
                premiereDate: TVMazeDate.dateOnly("2024-01-10"),
                endDate: TVMazeDate.dateOnly("2024-03-10"),
                episodeOrder: 8
            ),
            Season(
                id: 2,
                number: 2,
                premiereDate: TVMazeDate.dateOnly("2025-01-10"),
                endDate: TVMazeDate.dateOnly("2025-03-10"),
                episodeOrder: 8
            ),
        ]

        let upcomingSeason: Season
        switch phase {
        case .baseline:
            upcomingSeason = Season(
                id: 3,
                number: 3,
                premiereDate: nil,
                endDate: nil,
                episodeOrder: nil
            )
        case .updated:
            let premiere =
                Calendar.current.date(byAdding: .month, value: 2, to: referenceDate)
                ?? referenceDate.addingTimeInterval(60 * 60 * 24 * 60)
            upcomingSeason = Season(
                id: 3,
                number: 3,
                premiereDate: premiere,
                endDate: nil,
                episodeOrder: 10
            )
        }

        return Show(
            id: showID,
            name: showName,
            tvMazeURL: nil,
            summaryHTML: "<p>Simulated show for TestFlight beta validation only.</p>",
            posterMediumURL: nil,
            posterOriginalURL: nil,
            status: .running,
            premiered: TVMazeDate.dateOnly("2024-01-10"),
            ended: nil,
            network: "Beta diagnostics",
            genres: ["Diagnostics"],
            averageRuntime: 45,
            seasons: airedSeasons + [upcomingSeason],
            nextEpisode: nil,
            updatedAt: referenceDate
        )
    }
}
