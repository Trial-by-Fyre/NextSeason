//
//  WatchlistSearchUITests.swift
//  NextSeasonUITests
//

import XCTest

@MainActor
final class WatchlistSearchUITests: XCTestCase, NextSeasonUITesting {
    var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        try await launchUITestingApp()
    }
    private let previewShowName = UITestPreviewShow.name

    func testWatchlistExposesSearchFieldWhenShowsTracked() {
        trackPreviewShowAndOpenWatchlist()

        assertNotExists(
            watchlistSearchField,
            "The watchlist search field should stay hidden until the user opens search."
        )
        assertExists(
            watchlistSearchButton,
            "The watchlist should show a search button in the navigation bar when shows are tracked."
        )

        revealWatchlistSearchField()
    }

    func testWatchlistSearchKeepsMatchingRowVisible() {
        trackPreviewShowAndOpenWatchlist()

        searchWatchlist(for: "Sev")

        XCTAssertTrue(
            watchlistRow(named: previewShowName).waitForExistenceIfNeeded(
                timeout: UITestTimeout.standard
            ),
            "A matching query should keep the tracked show visible."
        )
        assertNotExists(
            watchlistNoResults,
            "A matching query should not show the no-matches state."
        )
    }

    func testWatchlistSearchWithNoMatchShowsNoResults() {
        trackPreviewShowAndOpenWatchlist()

        searchWatchlist(for: "zzzznomatch")

        assertExists(
            watchlistNoResults,
            "A non-matching query should surface the no-matches state."
        )
        assertNotExists(
            watchlistRow(named: previewShowName),
            "A non-matching query should hide the tracked show row."
        )
    }

    func testWatchlistClearingSearchRestoresRow() {
        trackPreviewShowAndOpenWatchlist()

        searchWatchlist(for: "zzzznomatch")
        assertExists(
            watchlistNoResults,
            "A non-matching query should surface the no-matches state before clearing."
        )

        clearWatchlistSearchField()

        XCTAssertTrue(
            watchlistRow(named: previewShowName).waitForExistenceIfNeeded(
                timeout: UITestTimeout.standard
            ),
            "Clearing the search should restore the tracked show row."
        )
        assertNotExists(
            watchlistNoResults,
            "Clearing the search should dismiss the no-matches state."
        )
    }

    // MARK: - Helpers

    private func trackPreviewShowAndOpenWatchlist() {
        // Seed via "Try an Example" so we don't type into the Search-tab field,
        // which is prone to a keyboard-focus flake under load. This test only
        // needs a tracked show; how it gets there isn't what's under test.
        tapTryExample()
        waitForSearchResultRow(named: previewShowName, timeout: UITestTimeout.extended)

        let trackButton = searchTrackButton()
        XCTAssertTrue(trackButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        trackButton.tap()

        // The watchlist row appearing is the real confirmation that tracking
        // persisted; asserting the search-row star flips first is redundant and
        // flaky under load (tracking persists asynchronously).
        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: previewShowName, timeout: UITestTimeout.trackState)
    }
}
