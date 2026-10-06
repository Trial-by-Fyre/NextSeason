//
//  SearchViewModelTests.swift
//  NextSeasonTests
//

import Foundation
import Synchronization
import Testing

@testable import NextSeason

/// Search state machine: TheTVDB pagination, TVDB→TVMaze mapping filter/overlay,
/// analytics, and debounce disabled (`.zero`) for deterministic async tests.
@MainActor
struct SearchViewModelTests {
    /// A `TheTVDBService` whose search behavior is supplied per test.
    private struct MockSearchService: TheTVDBService {
        let handler: @Sendable (String, Int) async throws -> TheTVDBSearchPage

        func searchSeries(matching query: String, offset: Int) async throws -> TheTVDBSearchPage {
            try await handler(query, offset)
        }
    }

    /// Configurable TVMaze stub for lookup/show resolution in search detail flows.
    private struct MockTVMazeService: TVMazeService {
        var lookupHandler: @Sendable (Int) async throws -> Show = { _ in await .preview }
        var showHandler: @Sendable (Int) async throws -> Show = { _ in await .preview }

        func searchShows(matching query: String) async throws -> [Show] { [] }

        func lookupShow(theTVDBID: Int) async throws -> Show {
            try await lookupHandler(theTVDBID)
        }

        func show(id: Int, bypassCache: Bool) async throws -> Show {
            try await showHandler(id)
        }

        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
            [:]
        }
    }

    /// Tracks TVMaze lookup traffic without mutating struct copies.
    private final class LookupCounter: Sendable {
        private let count = Mutex(0)

        func recordTheTVDB() {
            count.withLock { $0 += 1 }
        }

        var theTVDBLookups: Int {
            count.withLock { $0 }
        }
    }

    /// TVMaze stub that counts TheTVDB lookup attempts (should stay zero for mapped search).
    private struct CountingTVMazeService: TVMazeService {
        let counter: LookupCounter
        var showHandler: @Sendable (Int) async throws -> Show = { _ in await .preview }

        func searchShows(matching query: String) async throws -> [Show] { [] }

        func lookupShow(theTVDBID: Int) async throws -> Show {
            counter.recordTheTVDB()
            throw TVMazeError.notFound
        }

        func show(id: Int, bypassCache: Bool) async throws -> Show {
            try await showHandler(id)
        }

        func updatedShows(since period: TVMazeUpdatePeriod) async throws -> [Int: Date] {
            [:]
        }
    }

    private struct TestError: LocalizedError {
        var errorDescription: String? { "Something failed" }
    }

    private let sampleResult = TVDBSearchResult(
        id: 371980,
        name: "Severance",
        year: "2022",
        network: "Apple TV",
        status: "Continuing",
        posterURL: nil
    )

    /// In-memory mapping with a default Severance TVDB↔TVMaze pair.
    private func showIDMapping(
        map: [Int: Int] = [371980: 44933]
    ) -> InMemoryShowIDMapping {
        InMemoryShowIDMapping(map: map)
    }

    /// Mock page helper: when `rawCount` is omitted, advances by `results.count`
    /// (no sparse drops). Pass an explicit `rawCount` to simulate malformed rows.
    nonisolated private static func page(
        _ results: [TVDBSearchResult],
        hasMore: Bool,
        offset: Int = 0,
        rawCount: Int? = nil
    ) -> TheTVDBSearchPage {
        TheTVDBSearchPage(
            results: results,
            hasMore: hasMore,
            nextOffset: offset + (rawCount ?? results.count)
        )
    }

    /// View model with zero debounce and injectable search/TVMaze/mapping/analytics doubles.
    private func makeViewModel(
        search: MockSearchService,
        tvMaze: some TVMazeService = MockTVMazeService(),
        mapping: InMemoryShowIDMapping? = nil,
        analytics: any AnalyticsTracking = RecordingAnalyticsService()
    ) -> SearchViewModel {
        SearchViewModel(
            searchService: search,
            tvMaze: tvMaze,
            showIDMapping: mapping ?? showIDMapping(),
            analytics: analytics,
            debounce: .zero
        )
    }

    @Test("An empty/whitespace query resets to idle without calling the service")
    func emptyQueryStaysIdle() async {
        let viewModel = makeViewModel(
            search: MockSearchService { _, _ in
                Issue.record("service should not be called")
                return Self.page([], hasMore: false)
            }
        )
        viewModel.query = "   "
        await viewModel.search()
        #expect(viewModel.state == .idle)
    }

    @Test("Matching mapped shows populate the results state")
    func resultsPopulateState() async {
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([sampleResult], hasMore: false, offset: offset)
            }
        )
        viewModel.query = "severance"
        await viewModel.search()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [sampleResult], hasMore: false))
        )
        #expect(viewModel.resolvedTVMazeID(for: sampleResult.id) == 44933)
    }

    @Test("Search rows overlay TVMaze title and poster from the mapping")
    func overlaysTVMazeTitleAndPoster() async throws {
        let nativeTitle = TVDBSearchResult(
            id: 371980,
            name: "Ablösung",
            year: "2022",
            network: "Apple TV",
            status: "Continuing",
            posterURL: URL(string: "https://example.com/tvdb.jpg")
        )
        let poster = URL(
            string: "https://static.tvmaze.com/uploads/images/medium_portrait/1/1.jpg"
        )
        let mapping = InMemoryShowIDMapping(
            records: [
                371980: ShowIDMappingRecord(
                    tvMazeID: 44933,
                    name: "Severance",
                    posterMediumURL: poster
                )
            ]
        )
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([nativeTitle], hasMore: false, offset: offset)
            },
            mapping: mapping
        )
        viewModel.query = "severance"
        await viewModel.search()
        guard case .results(let page) = viewModel.state else {
            Issue.record("expected results")
            return
        }
        let item = try #require(page.items.first)
        #expect(item.id == 371980)
        #expect(item.name == "Severance")
        #expect(item.posterURL == poster)
    }

    @Test("Search drops TheTVDB poster when the mapping has no TVMaze artwork")
    func doesNotFallBackToTVDBPoster() async throws {
        let withTVDBPoster = TVDBSearchResult(
            id: 371980,
            name: "Ablösung",
            year: "2022",
            network: "Apple TV",
            status: "Continuing",
            posterURL: URL(string: "https://example.com/tvdb.jpg")
        )
        let mapping = InMemoryShowIDMapping(
            records: [
                371980: ShowIDMappingRecord(
                    tvMazeID: 44933,
                    name: "Severance",
                    posterMediumURL: nil
                )
            ]
        )
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([withTVDBPoster], hasMore: false, offset: offset)
            },
            mapping: mapping
        )
        viewModel.query = "severance"
        await viewModel.search()
        guard case .results(let page) = viewModel.state else {
            Issue.record("expected results")
            return
        }
        let item = try #require(page.items.first)
        #expect(item.name == "Severance")
        #expect(item.posterURL == nil)
    }

    @Test("Filtering removes unmapped results")
    func filteringRemovesUnmappedResults() async {
        let unmapped = TVDBSearchResult(
            id: 1,
            name: "Only On TheTVDB",
            year: "2020",
            network: nil,
            status: "Ended",
            posterURL: nil
        )
        let counter = LookupCounter()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([sampleResult, unmapped], hasMore: false, offset: offset)
            },
            tvMaze: CountingTVMazeService(counter: counter),
            mapping: showIDMapping(map: [371980: 44933])
        )
        viewModel.query = "show"
        await viewModel.search()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [sampleResult], hasMore: false))
        )
        #expect(counter.theTVDBLookups == 0)
    }

    @Test("Pagination continues when filtering leaves too few usable results")
    func paginationContinuesWhenFilteredThin() async {
        let page1Only = TVDBSearchResult(
            id: 1,
            name: "Unmapped",
            year: nil,
            network: nil,
            status: nil,
            posterURL: nil
        )
        let page2Mapped = TVDBSearchResult(
            id: 2,
            name: "Mapped",
            year: "2021",
            network: nil,
            status: "Continuing",
            posterURL: nil
        )
        let offsets = CallCounter()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                offsets.increment()
                if offset == 0 {
                    return Self.page([page1Only], hasMore: true, offset: offset)
                }
                return Self.page([page2Mapped], hasMore: false, offset: offset)
            },
            mapping: showIDMapping(map: [2: 99])
        )
        viewModel.query = "thin"
        await viewModel.search()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [page2Mapped], hasMore: false))
        )
        #expect(offsets.value == 2)
    }

    @Test("Search advances using page nextOffset, not filtered result count")
    func searchUsesPageNextOffsetNotResultCount() async {
        let unmapped = TVDBSearchResult(
            id: 1,
            name: "Unmapped",
            year: nil,
            network: nil,
            status: nil,
            posterURL: nil
        )
        let mapped = TVDBSearchResult(
            id: 2,
            name: "Mapped",
            year: "2021",
            network: nil,
            status: "Continuing",
            posterURL: nil
        )
        let requestedOffsets = OffsetRecorder()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                requestedOffsets.append(offset)
                if offset == 0 {
                    // One usable hit after discarding sparse rows from a full page.
                    return Self.page([unmapped], hasMore: true, offset: offset, rawCount: 10)
                }
                #expect(offset == 10)
                return Self.page([mapped], hasMore: false, offset: offset)
            },
            mapping: showIDMapping(map: [2: 99])
        )
        viewModel.query = "sparse-page"
        await viewModel.search()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [mapped], hasMore: false))
        )
        #expect(requestedOffsets.values == [0, 10])
    }

    @Test("Pagination terminates correctly when there are no more results")
    func paginationTerminatesWhenExhausted() async {
        let unmapped = TVDBSearchResult(
            id: 1,
            name: "Unmapped",
            year: nil,
            network: nil,
            status: nil,
            posterURL: nil
        )
        let offsets = CallCounter()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                offsets.increment()
                #expect(offset == 0)
                return Self.page([unmapped], hasMore: false, offset: offset)
            },
            mapping: showIDMapping(map: [:])
        )
        viewModel.query = "gone"
        await viewModel.search()
        #expect(viewModel.state == .empty)
        #expect(offsets.value == 1)
    }

    @Test("Zero actionable hits with more TVDB pages offers Load More instead of empty")
    func emptyActionableWithMorePagesKeepsLoadMore() async {
        let unmapped = TVDBSearchResult(
            id: 1,
            name: "Unmapped",
            year: nil,
            network: nil,
            status: nil,
            posterURL: nil
        )
        let mapped = TVDBSearchResult(
            id: 99,
            name: "Mapped Later",
            year: "2024",
            network: nil,
            status: "Continuing",
            posterURL: nil
        )
        let maxPages = SearchViewModel.maxTheTVDBPagesPerFill
        let offsets = CallCounter()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                offsets.increment()
                // Fill advances via nextOffset (1 per mock page), so the first
                // burst uses offsets 0..<maxPages before Load More.
                if offset < maxPages {
                    return Self.page([unmapped], hasMore: true, offset: offset)
                }
                return Self.page([mapped], hasMore: false, offset: offset)
            },
            mapping: showIDMapping(map: [99: 44933])
        )
        viewModel.query = "sparse"
        await viewModel.search()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [], hasMore: true))
        )
        #expect(offsets.value == maxPages)

        await viewModel.loadMore()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [mapped], hasMore: false))
        )
    }

    @Test("Load More that exhausts with no actionable hits becomes empty")
    func loadMoreExhaustionYieldsEmpty() async {
        let unmapped = TVDBSearchResult(
            id: 1,
            name: "Unmapped",
            year: nil,
            network: nil,
            status: nil,
            posterURL: nil
        )
        let maxPages = SearchViewModel.maxTheTVDBPagesPerFill
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                // First fill: maxPages unmapped pages that still report hasMore.
                if offset < maxPages {
                    return Self.page([unmapped], hasMore: true, offset: offset)
                }
                return Self.page([unmapped], hasMore: false, offset: offset)
            },
            mapping: showIDMapping(map: [:])
        )
        viewModel.query = "never"
        await viewModel.search()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [], hasMore: true))
        )
        await viewModel.loadMore()
        #expect(viewModel.state == .empty)
    }

    @Test("No matches yield the empty state")
    func noMatchesYieldEmpty() async {
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([], hasMore: false, offset: offset)
            }
        )
        viewModel.query = "no-such-show"
        await viewModel.search()
        #expect(viewModel.state == .empty)
    }

    @Test("A service error surfaces as the failed state with its message")
    func serviceErrorYieldsFailed() async {
        let viewModel = makeViewModel(
            search: MockSearchService { _, _ in throw TestError() }
        )
        viewModel.query = "severance"
        await viewModel.search()
        #expect(viewModel.state == .failed("Something failed"))
    }

    @Test("Clearing the query after results returns to idle")
    func clearingQueryReturnsToIdle() async {
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([sampleResult], hasMore: false, offset: offset)
            }
        )
        viewModel.query = FirstRunCopy.exampleSearchQuery
        await viewModel.search()
        #expect(
            viewModel.state
                == .results(SearchViewModel.ResultsPage(items: [sampleResult], hasMore: false))
        )

        viewModel.query = ""
        await viewModel.search()
        #expect(viewModel.state == .idle)
    }

    @Test("Repeating the same query while results are shown does not reload")
    func repeatedQuerySkipsReload() async {
        let counter = CallCounter()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                counter.increment()
                return Self.page([sampleResult], hasMore: false, offset: offset)
            }
        )
        viewModel.query = "severance"
        await viewModel.search()
        #expect(counter.value == 1)

        await viewModel.search()
        #expect(counter.value == 1)
    }

    @Test("Load more appends the next actionable page")
    func loadMoreAppendsNextPage() async {
        let second = TVDBSearchResult(
            id: 2,
            name: "Other Show",
            year: "2020",
            network: nil,
            status: "Ended",
            posterURL: nil
        )
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                if offset == 0 {
                    return Self.page([sampleResult], hasMore: true, offset: offset)
                }
                return Self.page([second], hasMore: false, offset: offset)
            },
            mapping: showIDMapping(map: [371980: 44933, 2: 82])
        )
        viewModel.query = "severance"
        await viewModel.search()
        await viewModel.loadMore()
        #expect(
            viewModel.state
                == .results(
                    SearchViewModel.ResultsPage(items: [sampleResult, second], hasMore: false)
                )
        )
    }

    @Test("Resolve maps a TheTVDB hit to a TVMaze show via mapped id")
    func resolveMapsToTVMazeShow() async throws {
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([sampleResult], hasMore: false, offset: offset)
            }
        )
        let show = try await viewModel.resolveShow(for: sampleResult)
        #expect(show.id == Show.preview.id)
        #expect(viewModel.resolvedTVMazeID(for: sampleResult.id) == Show.preview.id)
    }

    @Test("Search does not prefetch TheTVDB lookups for mapped results")
    func searchDoesNotPrefetchTheTVDBLookups() async {
        let counter = LookupCounter()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([sampleResult], hasMore: false, offset: offset)
            },
            tvMaze: CountingTVMazeService(counter: counter),
            mapping: showIDMapping(map: [371980: 44933])
        )
        viewModel.query = "severance"
        await viewModel.search()
        #expect(counter.theTVDBLookups == 0)
    }

    @Test("Successful search records search_performed immediately")
    func successfulSearchRecordsImmediately() async {
        let analytics = RecordingAnalyticsService()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([sampleResult], hasMore: false, offset: offset)
            },
            analytics: analytics
        )
        viewModel.query = "severance"
        await viewModel.search()

        guard
            case .searchPerformed(let queryLength, let resultCount, _, let outcome) =
                analytics.events.first
        else {
            Issue.record("expected search_performed")
            return
        }
        #expect(queryLength == 9)
        #expect(resultCount == 1)
        #expect(outcome == .results)
        #expect(
            analytics.events.contains { event in
                if case .searchResultSelected = event { return true }
                return false
            } == false)
    }

    @Test("Empty search records search_performed immediately")
    func emptySearchRecordsImmediately() async {
        let analytics = RecordingAnalyticsService()
        let viewModel = makeViewModel(
            search: MockSearchService { _, offset in
                Self.page([], hasMore: false, offset: offset)
            },
            mapping: showIDMapping(map: [:]),
            analytics: analytics
        )
        viewModel.query = "xyzzy"
        await viewModel.search()

        #expect(
            analytics.events.contains { event in
                if case .searchPerformed(let queryLength, let resultCount, _, let outcome) = event {
                    return queryLength == 5 && resultCount == 0 && outcome == .empty
                }
                return false
            })
        #expect(analytics.events.contains { $0 == .emptySearchResultsShown })
    }

    @Test("Failed search records search_performed with outcome failed")
    func failedSearchRecordsFailedOutcome() async {
        let analytics = RecordingAnalyticsService()
        let viewModel = makeViewModel(
            search: MockSearchService { _, _ in throw TestError() },
            analytics: analytics
        )
        viewModel.query = "severance"
        await viewModel.search()

        #expect(
            analytics.events.contains { event in
                if case .searchPerformed(let queryLength, let resultCount, _, let outcome) = event {
                    return queryLength == 9 && resultCount == 0 && outcome == .failed
                }
                return false
            })
        #expect(
            analytics.events.contains { event in
                if case .nonFatalError(_, let context) = event {
                    return context == "search"
                }
                return false
            }
        )
    }

    /// Thread-safe invocation counter for paginated search handlers.
    private final class CallCounter: Sendable {
        private let count = Mutex(0)

        func increment() {
            count.withLock { $0 += 1 }
        }

        var value: Int {
            count.withLock { $0 }
        }
    }

    /// Records TheTVDB page offsets requested during pagination tests.
    private final class OffsetRecorder: Sendable {
        private let stored = Mutex<[Int]>([])

        func append(_ value: Int) {
            stored.withLock { $0.append(value) }
        }

        var values: [Int] {
            stored.withLock { $0 }
        }
    }
}
