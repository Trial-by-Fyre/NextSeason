//
//  NavigationUITests.swift
//  NextSeasonUITests
//

import XCTest

@MainActor
final class NavigationUITests: XCTestCase, NextSeasonUITesting {
    var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        try await launchUITestingApp()
    }
    func testLaunchShowsSearchTab() {
        XCTAssertTrue(
            searchIdlePrompt.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "Search tab should show the idle prompt on launch."
        )
        XCTAssertTrue(
            tryExampleButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "Search idle state should offer Try an Example on launch."
        )
        XCTAssertTrue(
            app.navigationBars["NextSeason"].waitForExistenceIfNeeded(
                timeout: UITestTimeout.standard
            ))
        XCTAssertTrue(app.tabBars.buttons["Search"].exists)
    }

    func testSwitchToWatchlistTabShowsEmptyState() {
        app.tabBars.buttons["Watchlist"].tap()

        XCTAssertTrue(
            watchlistEmptyState.waitForExistenceIfNeeded(timeout: UITestTimeout.extended),
            "Watchlist tab should show the empty state when no shows are tracked."
        )
        XCTAssertTrue(
            app.navigationBars["Watchlist"].waitForExistenceIfNeeded(
                timeout: UITestTimeout.standard
            ))
    }

    func testSwitchBetweenTabs() {
        app.tabBars.buttons["Watchlist"].tap()
        XCTAssertTrue(watchlistEmptyState.waitForExistenceIfNeeded(timeout: UITestTimeout.extended))

        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(searchIdlePrompt.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
    }

    func testSearchTabReturnsToResultsAfterViewingDetailFromAnotherTab() {
        search(for: UITestPreviewShow.name)

        let result = waitForSearchResultRow(named: UITestPreviewShow.name)
        result.tap()
        waitForShowDetail()

        app.tabBars.buttons["Watchlist"].tap()
        XCTAssertTrue(watchlistEmptyState.waitForExistenceIfNeeded(timeout: UITestTimeout.extended))

        app.tabBars.buttons["Search"].tap()

        waitForSearchResultRow(named: UITestPreviewShow.name, timeout: UITestTimeout.extended)
        XCTAssertTrue(
            waitForSearchFieldValue(UITestPreviewShow.name),
            "Returning to Search should preserve the last query."
        )
        assertNotExists(
            showDetailTrackButton(),
            "Search tab should return to the results list, not a stale detail screen."
        )
    }

    func testFindShowButtonNavigatesToSearch() {
        XCTContext.runActivity(named: "Search for a show and open its detail") { _ in
            search(for: UITestPreviewShow.name)

            let result = waitForSearchResultRow(
                named: UITestPreviewShow.name,
                timeout: UITestTimeout.extended
            )
            result.tap()
            waitForShowDetail()
        }

        XCTContext.runActivity(named: "Switch to empty watchlist") { _ in
            app.tabBars.buttons["Watchlist"].tap()
            assertExists(
                watchlistEmptyState,
                timeout: UITestTimeout.extended,
                "Watchlist tab should show the empty state when no shows are tracked."
            )
        }

        XCTContext.runActivity(named: "Tap Find a Show and verify search root") { _ in
            let findShow = app.buttons["Find a Show"]
            assertExists(
                findShow,
                "Watchlist empty state should offer a Find a Show button."
            )
            findShow.tap()

            assertExists(
                searchField,
                "Find a Show should show the search field on the Search tab."
            )
            waitForSearchResultRow(
                named: UITestPreviewShow.name,
                timeout: UITestTimeout.extended
            )
            assertNotExists(
                showDetailTrackButton(),
                "Find a Show should return to the search results list, not a stale detail screen."
            )
        }
    }
}
