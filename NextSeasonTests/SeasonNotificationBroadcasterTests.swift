//
//  SeasonNotificationBroadcasterTests.swift
//  NextSeasonTests
//

import Foundation
import Testing
import UserNotifications

@testable import NextSeason

/// Season-change notifications name the original broadcaster and its country,
/// like show detail, since TVMaze schedules reflect the original broadcast rather
/// than local availability. Wording only: timing and dedupe are unchanged.

// MARK: - Fixtures

@MainActor
private final class BroadcasterTVMaze: TVMazeService {
    var updates: [Int: Date] = [:]
    var shows: [Int: Show] = [:]

    @MainActor func searchShows(matching query: String) async throws -> [Show] { [] }

    @MainActor func lookupShow(theTVDBID: Int) async throws -> Show {
        throw TVMazeError.notFound
    }

    @MainActor func show(id: Int, bypassCache: Bool) async throws -> Show {
        guard let show = shows[id] else { throw TVMazeError.notFound }
        return show
    }

    @MainActor func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
        updates
    }

    @MainActor func allUpdatedShows() async throws -> [Int: Date] { updates }
}

/// Returns scripted outcomes, then `.accepted`.
@MainActor
private final class RecordingDelivery: NotificationDelivering {
    var outcomes: [NotificationDeliveryOutcome] = []
    private(set) var attempts: [SeasonNotificationContent] = []

    func deliver(_ content: SeasonNotificationContent) async -> NotificationDeliveryOutcome {
        attempts.append(content)
        return outcomes.isEmpty ? .accepted : outcomes.removeFirst()
    }
}

private let now = TVMazeDate.dateOnly("2026-06-14")!
private let day: TimeInterval = 86_400

/// Season 2 started 2026-06-01, so the show is airing at `now`; with
/// `premiere` set to a later date it is scheduled instead.
private func show(
    network: String?, country: String?, premiere: String = "2026-06-01",
    updatedAt: Date = now - day
) -> Show {
    let seasons = [
        Season(
            id: 11, number: 1, premiereDate: TVMazeDate.dateOnly("2024-01-10"),
            endDate: TVMazeDate.dateOnly("2024-03-10"), episodeOrder: 8),
        Season(
            id: 12, number: 2, premiereDate: TVMazeDate.dateOnly(premiere),
            endDate: nil, episodeOrder: nil),
    ]
    return Show(
        id: 1, name: "Murdoch Mysteries", tvMazeURL: nil, summaryHTML: nil,
        posterMediumURL: nil, posterOriginalURL: nil, status: .running,
        premiered: TVMazeDate.dateOnly("2024-01-10"), ended: nil, network: network,
        networkCountry: country, genres: [], averageRuntime: nil, seasons: seasons,
        nextEpisode: nil, updatedAt: updatedAt)
}

/// A saved row already told that season 2 was announced without a date.
private func undatedRow() -> TrackedShow {
    var row = TrackedShow(
        from: show(network: "CBC", country: "Canada", updatedAt: now - 10 * day),
        at: now - 10 * day)
    row.nextSeason = .announcedUndated(season: 2)
    row.lastNotifiedSignature = StatusChangeDetector.signature(for: row.nextSeason)
    row.dateAdded = now - 60 * day
    return row
}

@MainActor
private func isolatedDefaults() -> UserDefaults {
    let suiteName = "SeasonNotificationBroadcasterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// One refresh service over an in-memory watchlist with fake TVMaze and delivery.
@MainActor
private struct Harness {
    let tvMaze = BroadcasterTVMaze()
    let delivery = RecordingDelivery()
    let repository = InMemoryWatchlistRepository(seed: [undatedRow()])
    let refresh: WatchlistRefreshService

    init(notifications: (any NotificationDelivering)? = nil) {
        refresh = WatchlistRefreshService(
            tvMaze: tvMaze, repository: repository, notifications: notifications ?? delivery,
            analytics: RecordingAnalyticsService(), userDefaults: isolatedDefaults(),
            clock: { now })
    }

    /// TVMaze now serves `show` as a server change.
    func report(_ show: Show) {
        tvMaze.shows[show.id] = show
        tvMaze.updates[show.id] = show.updatedAt
    }

    /// An ordinary (non-forced) refresh, as from the foreground or background.
    func poll() async {
        await refresh.refreshAll()
    }
}

/// Fixed locale and time zone so the premiere date formats predictably.
private func dateStyle() throws -> Date.FormatStyle {
    Date.FormatStyle(
        date: .abbreviated, time: .omitted, locale: Locale(identifier: "en_US"),
        calendar: Calendar(identifier: .gregorian),
        timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")))
}

private func content(
    _ status: NextSeasonStatus, broadcaster: String?, country: String?
) -> SeasonNotificationContent {
    SeasonNotificationContent(
        showID: 1, showName: "Murdoch Mysteries", status: status,
        broadcaster: broadcaster, country: country)
}

// MARK: - Wording

struct SeasonNotificationBroadcasterWordingTests {
    @Test("Airing names the broadcaster and country")
    func airing() {
        let notification = content(.airing(season: 20), broadcaster: "CBC Gem", country: "Canada")

        #expect(notification.body == "Season 20 airing on CBC Gem (Canada)")
        #expect(notification.title == "Murdoch Mysteries")
    }

    @Test("Scheduled names the broadcaster and country after the premiere date")
    func scheduled() throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let notification = content(
            .scheduled(season: 21, premiere: premiere), broadcaster: "CBC", country: "Canada")

        #expect(
            notification.body(dateStyle: try dateStyle())
                == "Season 21 premieres Jan 1, 2027 on CBC (Canada)")
    }

    @Test("A missing or blank country leaves just the broadcaster", arguments: [nil, "", " "])
    func missingCountry(_ country: String?) throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let airing = content(.airing(season: 20), broadcaster: "CBC Gem", country: country)
        let scheduled = content(
            .scheduled(season: 21, premiere: premiere), broadcaster: "CBC", country: country)

        #expect(airing.body == "Season 20 airing on CBC Gem")
        #expect(
            scheduled.body(dateStyle: try dateStyle()) == "Season 21 premieres Jan 1, 2027 on CBC")
    }

    @Test(
        "A missing or blank broadcaster keeps the generic wording, even with a country",
        arguments: [nil, "", "  "])
    func missingBroadcaster(_ broadcaster: String?) throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let airing = content(.airing(season: 20), broadcaster: broadcaster, country: "Canada")
        let scheduled = content(
            .scheduled(season: 21, premiere: premiere), broadcaster: broadcaster,
            country: "Canada")

        #expect(airing.body == "Season 20 is now airing")
        #expect(scheduled.body(dateStyle: try dateStyle()) == "Season 21 premieres Jan 1, 2027")
    }

    @Test(
        "Other notification types are unchanged by a broadcaster",
        arguments: [
            NextSeasonStatus.announcedUndated(season: 4), .returningNoSeasonYet, .ended, .unknown,
        ])
    func otherStatusesUnchanged(_ status: NextSeasonStatus) {
        let named = content(status, broadcaster: "CBC", country: "Canada")
        let unnamed = content(status, broadcaster: nil, country: nil)

        #expect(named.body == unnamed.body)
    }
}

// MARK: - Refresh pipeline

@MainActor
struct SeasonNotificationBroadcasterRefreshTests {
    @Test("A refresh words the alert from the fetched broadcaster and its country")
    func refreshUsesFetchedBroadcaster() async throws {
        let harness = Harness()
        harness.report(show(network: "CBC Gem", country: "Canada"))

        await harness.poll()

        let notification = try #require(harness.delivery.attempts.only)
        #expect(notification.body == "Season 2 airing on CBC Gem (Canada)")
    }

    @Test("A scheduled change from a refresh names the broadcaster without a country")
    func refreshScheduledWithoutCountry() async throws {
        let harness = Harness()
        harness.report(show(network: "Netflix", country: nil, premiere: "2026-09-01"))

        await harness.poll()

        let notification = try #require(harness.delivery.attempts.only)
        #expect(notification.broadcaster == "Netflix")
        #expect(notification.country == nil)
        #expect(notification.body.hasSuffix(" on Netflix"))
    }

    @Test("A refresh without a broadcaster keeps the generic wording")
    func refreshWithoutBroadcaster() async throws {
        let harness = Harness()
        harness.report(show(network: nil, country: nil))

        await harness.poll()

        let notification = try #require(harness.delivery.attempts.only)
        #expect(notification.body == "Season 2 is now airing")
    }

    @Test("A retried alert uses the broadcaster from the retrying refresh, not the failed one")
    func retryUsesFreshBroadcaster() async throws {
        let harness = Harness()
        harness.delivery.outcomes = [.failed]
        harness.report(show(network: "CBC", country: "Canada"))
        await harness.poll()

        // Between the failure and the retry, TVMaze moves the show to CBC Gem.
        harness.report(show(network: "CBC Gem", country: nil, updatedAt: now - day / 2))
        await harness.poll()
        await harness.poll()

        let bodies = harness.delivery.attempts.map(\.body)
        #expect(bodies == ["Season 2 airing on CBC (Canada)", "Season 2 airing on CBC Gem"])
    }

    @Test("A broadcaster change alone never re-alerts an already announced status")
    func broadcasterChangeDoesNotRealert() async throws {
        let harness = Harness()
        harness.report(show(network: "CBC", country: "Canada"))
        await harness.poll()

        harness.report(show(network: "CBC Gem", country: "Canada", updatedAt: now - day / 2))
        await harness.poll()

        #expect(harness.delivery.attempts.count == 1)
        let saved = try #require(try await harness.repository.trackedShow(showID: 1))
        #expect(saved.lastNotifiedSignature == "airing:2")
        #expect(saved.pendingChangeSignature == nil)
    }

    @Test("Through NotificationService, the request carries the wording and the same identifier")
    func requestThroughNotificationService() async throws {
        @MainActor final class Scheduler {
            var requests: [UNNotificationRequest] = []
        }
        let scheduler = Scheduler()
        let service = NotificationService(
            scheduler: .init(alertsPermitted: true, add: { scheduler.requests.append($0) }),
            analytics: RecordingAnalyticsService())
        let harness = Harness(notifications: service)
        harness.report(show(network: "CBC Gem", country: "Canada"))

        await harness.poll()

        let request = try #require(scheduler.requests.only)
        #expect(request.content.title == "Murdoch Mysteries")
        #expect(request.content.body == "Season 2 airing on CBC Gem (Canada)")
        // The identifier is still keyed by status alone, so dedupe is unchanged.
        #expect(request.identifier == "show-1-airing:2")
    }
}

extension Array {
    /// The single element, or nil when there are zero or several.
    fileprivate var only: Element? { count == 1 ? first : nil }
}
