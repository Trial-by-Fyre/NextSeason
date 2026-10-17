//
//  ProfileFlowRunner.swift
//  NextSeason
//

import Foundation
import SwiftUI
import os

/// Drives a single user flow for Instruments when launched with `-ProfileFlow`.
///
/// Sets coordinator state (tab, search query, navigation path) and waits on
/// tokens that Search/Show Detail bump when UI work settles
/// (`automationSearchSettledToken`, `automationDetailLoadedToken`). Emits
/// `OSSignposter` intervals for Instruments and records durations via
/// `AppDiagnosticsLogger` / `ProfileFlowTimingStore`.
///
/// Setup-only flows (e.g. seed) exit early; others sleep briefly after the flow
/// so xctrace can capture trailing work.
@MainActor
struct ProfileFlowRunner {
    private static var signposter: OSSignposter { ProfileFlowConfiguration.Signpost.signposter }

    let flow: ProfileFlowConfiguration.Flow
    let coordinator: AppNavigationCoordinator
    let repository: any WatchlistRepository
    let tvMaze: any TVMazeService
    let analytics: any AnalyticsTracking

    func run() async {
        ProfileFlowTimingStore.clear()
        ProfileFlowTimingStore.appendOutcome(flow: flow.rawValue, status: "started")
        do {
            // Instruments can enable signposts after launch. Starting earlier
            // loses the Begin event while still recording a later End.
            if ProcessInfo.processInfo.arguments.contains("-ProfileRequireSignposts") {
                try await ProfileFlowWait.until(
                    "signpost recording", timeout: .seconds(10),
                    isSatisfied: { Self.signposter.isEnabled }
                )
            }
            let start = Date.now
            let interval = beginFlowInterval()
            try await runScenario()
            try Task.checkCancellation()
            endFlowInterval(interval)
            AppDiagnosticsLogger.logProfileFlowTiming(
                flow: flow.rawValue,
                durationMs: max(0, Int(Date.now.timeIntervalSince(start) * 1000))
            )
            ProfileFlowTimingStore.appendOutcome(flow: flow.rawValue, status: "completed")
        } catch is CancellationError {
            coordinator.cancelAutomationSearch()
            ProfileFlowTimingStore.appendOutcome(flow: flow.rawValue, status: "cancelled")
        } catch {
            coordinator.cancelAutomationSearch()
            analytics.trackNonFatalError(error, context: "profile_flow_" + flow.rawValue)
            ProfileFlowTimingStore.appendOutcome(
                flow: flow.rawValue, status: "failed", error: error.localizedDescription
            )
        }
        // Failed/cancelled flows intentionally leave the interval unfinished;
        // an end-of-recording duration must not masquerade as a successful run.
    }

    private func runScenario() async throws {
        if flow.isSetupOnly {
            try await Task.sleep(for: .milliseconds(500))
            try await runSeedWatchlist()
            return
        }

        // Allow the root SwiftUI hierarchy to appear before driving navigation.
        try await Task.sleep(for: .milliseconds(750))

        switch flow {
        case .seedWatchlist:
            break
        case .search:
            try await runSearch()
        case .searchEmpty:
            try await runSearchEmpty()
        case .showDetails:
            try await runShowDetails()
        case .viewWishlist:
            try await runViewWishlist()
        case .addToWishlist:
            try await runAddToWishlist()
        case .removeFromWishlist:
            try await runRemoveFromWishlist()
        case .stressSearchDetailsBack:
            try await runStressSearchDetailsBack()
        case .stressAddRemoveWishlist:
            try await runStressAddRemoveWishlist()
        case .stressSearchEmpty:
            try await runStressSearchEmpty()
        case .launchWithData:
            try await runLaunchWithDataIdle()
        }

        // Keep the process alive briefly so xctrace can capture post-flow work.
        try await Task.sleep(for: .seconds(2))
    }

    private func beginFlowInterval() -> OSSignpostIntervalState {
        switch flow {
        case .seedWatchlist:
            Self.signposter.beginInterval("flow.seedWatchlist")
        case .search:
            Self.signposter.beginInterval("flow.search")
        case .searchEmpty:
            Self.signposter.beginInterval("flow.searchEmpty")
        case .showDetails:
            Self.signposter.beginInterval("flow.showDetails")
        case .viewWishlist:
            Self.signposter.beginInterval("flow.viewWishlist")
        case .addToWishlist:
            Self.signposter.beginInterval("flow.addToWishlist")
        case .removeFromWishlist:
            Self.signposter.beginInterval("flow.removeFromWishlist")
        case .stressSearchDetailsBack:
            Self.signposter.beginInterval("flow.stressSearchDetailsBack")
        case .stressAddRemoveWishlist:
            Self.signposter.beginInterval("flow.stressAddRemoveWishlist")
        case .stressSearchEmpty:
            Self.signposter.beginInterval("flow.stressSearchEmpty")
        case .launchWithData:
            Self.signposter.beginInterval("flow.launchWithData")
        }
    }

    private func endFlowInterval(_ interval: OSSignpostIntervalState) {
        switch flow {
        case .seedWatchlist:
            Self.signposter.endInterval("flow.seedWatchlist", interval)
        case .search:
            Self.signposter.endInterval("flow.search", interval)
        case .searchEmpty:
            Self.signposter.endInterval("flow.searchEmpty", interval)
        case .showDetails:
            Self.signposter.endInterval("flow.showDetails", interval)
        case .viewWishlist:
            Self.signposter.endInterval("flow.viewWishlist", interval)
        case .addToWishlist:
            Self.signposter.endInterval("flow.addToWishlist", interval)
        case .removeFromWishlist:
            Self.signposter.endInterval("flow.removeFromWishlist", interval)
        case .stressSearchDetailsBack:
            Self.signposter.endInterval("flow.stressSearchDetailsBack", interval)
        case .stressAddRemoveWishlist:
            Self.signposter.endInterval("flow.stressAddRemoveWishlist", interval)
        case .stressSearchEmpty:
            Self.signposter.endInterval("flow.stressSearchEmpty", interval)
        case .launchWithData:
            Self.signposter.endInterval("flow.launchWithData", interval)
        }
    }

    /// Requests a distinct profiling search, even when its query is unchanged.
    private func runSearch() async throws {
        let phaseStart = Date.now
        let interval = Self.signposter.beginInterval("search.query")
        try await performSearch(FirstRunCopy.exampleSearchQuery)
        Self.signposter.endInterval("search.query", interval)
        AppDiagnosticsLogger.logProfileFlowTiming(
            flow: flow.rawValue,
            durationMs: max(0, Int(Date.now.timeIntervalSince(phaseStart) * 1000)),
            phase: "search.query"
        )
    }

    private func runSearchEmpty() async throws {
        let interval = Self.signposter.beginInterval("search.empty")
        try await performSearch(ProfileFlowConfiguration.SearchQuery.emptyResults)
        Self.signposter.endInterval("search.empty", interval)
    }

    /// Populates the watchlist from fixed queries (setup before other flows).
    private func runSeedWatchlist() async throws {
        let interval = Self.signposter.beginInterval("watchlist.seed")
        for query in ProfileFlowConfiguration.SeedData.watchlistSearchQueries {
            try Task.checkCancellation()
            let show = try await resolveShow(matching: query)
            if try await repository.contains(showID: show.id) { continue }
            do {
                try await repository.add(show)
            } catch {
                analytics.trackNonFatalError(error, context: "profile_flow_seed")
                throw error
            }
        }
        coordinator.notifyWatchlistDataChanged()
        try await Task.sleep(for: .seconds(1))
        Self.signposter.endInterval("watchlist.seed", interval)
    }

    /// Push show detail, wait for load, then pop — captures retention after dismiss.
    private func runShowDetails() async throws {
        let show = try await resolveExampleShow()

        let phaseStart = Date.now
        let interval = Self.signposter.beginInterval("showDetails.load")
        let detailToken = coordinator.automationDetailLoadedToken
        coordinator.selectedTab = .search
        coordinator.searchPath.append(show)
        analytics.track(.showDetailViewed(showID: show.id))
        try await waitForDetailLoaded(since: detailToken)
        try await Task.sleep(for: .milliseconds(300))
        Self.signposter.endInterval("showDetails.load", interval)
        AppDiagnosticsLogger.logProfileFlowTiming(
            flow: flow.rawValue,
            durationMs: max(0, Int(Date.now.timeIntervalSince(phaseStart) * 1000)),
            phase: "showDetails.load"
        )

        let retentionInterval = Self.signposter.beginInterval("showDetails.retentionCheck")
        coordinator.showSearchRoot()
        try await Task.sleep(for: .seconds(1))
        Self.signposter.endInterval("showDetails.retentionCheck", retentionInterval)
    }

    private func runViewWishlist() async throws {
        let interval = Self.signposter.beginInterval("watchlist.view")
        coordinator.selectedTab = .watchlist
        coordinator.notifyWatchlistDataChanged()
        try await Task.sleep(for: .seconds(1))
        Self.signposter.endInterval("watchlist.view", interval)
    }

    private func runAddToWishlist() async throws {
        let show = try await resolveExampleShow()

        let phaseStart = Date.now
        let interval = Self.signposter.beginInterval("watchlist.add")
        if try await repository.contains(showID: show.id) {
            try await repository.remove(showID: show.id)
        }

        try await performSearch(FirstRunCopy.exampleSearchQuery)

        do {
            try await repository.add(show)
            analytics.track(.watchlistAdded(source: .search, showID: show.id))
            coordinator.notifyWatchlistDataChanged()
        } catch {
            analytics.trackNonFatalError(error, context: "profile_flow_add")
            throw error
        }
        Self.signposter.endInterval("watchlist.add", interval)
        AppDiagnosticsLogger.logProfileFlowTiming(
            flow: flow.rawValue,
            durationMs: max(0, Int(Date.now.timeIntervalSince(phaseStart) * 1000)),
            phase: "watchlist.add"
        )
    }

    private func runRemoveFromWishlist() async throws {
        let show = try await resolveExampleShow()

        let interval = Self.signposter.beginInterval("watchlist.remove")
        if try await repository.contains(showID: show.id) == false {
            try await repository.add(show)
            coordinator.notifyWatchlistDataChanged()
        }

        coordinator.selectedTab = .watchlist
        coordinator.notifyWatchlistDataChanged()
        try await Task.sleep(for: .milliseconds(500))

        do {
            try await repository.remove(showID: show.id)
            analytics.track(.watchlistRemoved(source: .watchlist, showID: show.id))
            coordinator.notifyWatchlistDataChanged()
        } catch {
            analytics.trackNonFatalError(error, context: "profile_flow_remove")
            throw error
        }
        Self.signposter.endInterval("watchlist.remove", interval)
    }

    private func resolveExampleShow() async throws -> Show {
        try await resolveShow(matching: FirstRunCopy.exampleSearchQuery)
    }

    private func resolveShow(matching query: String) async throws -> Show {
        let shows = try await tvMaze.searchShows(matching: query)
        let matching = shows.first { $0.name.localizedCaseInsensitiveContains(query) }
        guard let show = matching ?? shows.first else {
            throw NSError(
                domain: "ProfileFlow", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No show found for " + query]
            )
        }
        return show
    }

    private func performSearch(_ query: String) async throws {
        try Task.checkCancellation()
        coordinator.selectedTab = .search
        let baseline = coordinator.requestAutomationSearch(query)
        try await ProfileFlowWait.until("search " + query, timeout: .seconds(15)) {
            coordinator.automationSearchSettledToken > baseline
        }
        if let message = coordinator.automationSearchError {
            throw NSError(
                domain: "ProfileFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func waitForDetailLoaded(since startToken: Int) async throws {
        try await ProfileFlowWait.until("show detail", timeout: .seconds(12)) {
            coordinator.automationDetailLoadedToken > startToken
        }
    }

    /// Repeated search → detail → back to stress navigation / retention.
    private func runStressSearchDetailsBack() async throws {
        let show = try await resolveExampleShow()

        let interval = Self.signposter.beginInterval("stress.searchDetailsBack")
        for iteration in 1...20 {
            try await performSearch(FirstRunCopy.exampleSearchQuery)
            let detailToken = coordinator.automationDetailLoadedToken
            coordinator.searchPath.append(show)
            try await waitForDetailLoaded(since: detailToken)
            coordinator.showSearchRoot()
            try await Task.sleep(for: .milliseconds(200))
            ProfileFlowTimingStore.appendOutcome(
                flow: flow.rawValue, status: "iteration_completed", iteration: iteration
            )
        }
        Self.signposter.endInterval("stress.searchDetailsBack", interval)
    }

    private func runStressAddRemoveWishlist() async throws {
        let show = try await resolveExampleShow()

        let interval = Self.signposter.beginInterval("stress.addRemoveWishlist")
        for iteration in 1...50 {
            try Task.checkCancellation()
            do {
                try await repository.add(show)
                coordinator.notifyWatchlistDataChanged()
                try await repository.remove(showID: show.id)
                coordinator.notifyWatchlistDataChanged()
            } catch {
                analytics.trackNonFatalError(error, context: "profile_flow_stress_add_remove")
                throw error
            }
            try await Task.sleep(for: .milliseconds(100))
            ProfileFlowTimingStore.appendOutcome(
                flow: flow.rawValue, status: "iteration_completed", iteration: iteration
            )
        }
        Self.signposter.endInterval("stress.addRemoveWishlist", interval)
    }

    private func runStressSearchEmpty() async throws {
        let interval = Self.signposter.beginInterval("stress.searchEmpty")
        for iteration in 1...20 {
            try await performSearch(ProfileFlowConfiguration.SearchQuery.emptyResults)
            ProfileFlowTimingStore.appendOutcome(
                flow: flow.rawValue, status: "iteration_completed", iteration: iteration
            )
        }
        Self.signposter.endInterval("stress.searchEmpty", interval)
    }

    /// Exercises a populated watchlist at idle after launch (seed data must exist).
    private func runLaunchWithDataIdle() async throws {
        let interval = Self.signposter.beginInterval("launchWithData.idle")
        coordinator.selectedTab = .watchlist
        coordinator.notifyWatchlistDataChanged()
        try await Task.sleep(for: .seconds(3))
        Self.signposter.endInterval("launchWithData.idle", interval)
    }
}
