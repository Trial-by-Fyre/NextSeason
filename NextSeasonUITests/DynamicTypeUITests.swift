//
//  DynamicTypeUITests.swift
//  NextSeasonUITests
//

import XCTest

/// Search and Watchlist at the largest accessibility text size: every state's
/// content must be reachable by scrolling, and the search field and tab bar
/// stay usable.
@MainActor
final class DynamicTypeUITests: XCTestCase, NextSeasonUITesting {
    var app: XCUIApplication!

    /// Maximum swipes before concluding content cannot be scrolled into view.
    private let maximumSwipes = 8

    override func setUp() async throws {
        try await super.setUp()
        try await launchUITestingApp(additionalArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
    }

    func testIdleStateScrollsToTryExampleAtLargestTextSize() {
        assertExists(searchIdlePrompt, "Search should open on the idle prompt.")

        scrollIntoView(tryExampleButton, "Try an Example should be reachable by scrolling.")
        tryExampleButton.tap()

        waitForSearchResultRow(named: UITestPreviewShow.name, timeout: UITestTimeout.extended)
    }

    func testNoResultsStateScrollsToDescriptionAtLargestTextSize() {
        search(for: UITestingSearchQuery.noResults)
        assertExists(
            searchNoResults,
            timeout: UITestTimeout.extended,
            "An empty result set should show the fallback guidance."
        )

        // The container holds the title and guidance, so reaching its bottom
        // edge means the whole guidance can be read.
        scrollIntoView(searchNoResults, "The no-results guidance should be reachable by scrolling.")
        assertSearchChromeReachable()
    }

    func testFailureStateScrollsToTryAgainAtLargestTextSize() {
        search(for: UITestingSearchQuery.failure)
        assertExists(
            app.staticTexts["Something Went Wrong"],
            timeout: UITestTimeout.extended,
            "A failed search should surface an error state."
        )

        let tryAgain = app.buttons["Try Again"]
        scrollIntoView(tryAgain, "Try Again should be reachable by scrolling.")
        assertSearchChromeReachable()
    }

    func testResultsScrollToAttributionAtLargestTextSize() {
        tapTryExampleAfterScrolling()
        waitForSearchResultRow(named: UITestPreviewShow.name, timeout: UITestTimeout.extended)

        let attribution = app.descendants(matching: .any)[AccessibilityID.Search.tvdbAttribution]
        scrollIntoView(attribution, "TheTVDB attribution should be reachable by scrolling.")
        assertSearchChromeReachable()
    }

    func testWatchlistEmptyStateScrollsToFindAShowAtLargestTextSize() {
        // At this size the empty state is a list row below the notifications
        // banner, so it may not exist until scrolled to.
        app.tabBars.buttons["Watchlist"].tap()
        let findAShow = app.buttons["Find a Show"]
        scrollIntoView(findAShow, "Find a Show should be reachable by scrolling.")
        findAShow.tap()
        XCTAssertTrue(
            searchField.waitForExistence(timeout: UITestTimeout.standard),
            "Find a Show should return to Search with its field visible."
        )
    }

    func testWatchlistNoMatchesScrollsAtLargestTextSize() {
        tapTryExampleAfterScrolling()
        waitForSearchResultRow(named: UITestPreviewShow.name, timeout: UITestTimeout.extended)
        // Tracking is setup here; XCUITest scrolls the star into view to tap it.
        let trackButton = searchTrackButton()
        assertExists(trackButton, "Search results should expose a track control.")
        trackButton.tap()

        // The tracked row may sit below the notifications banner, which fills
        // the screen at this size, so go straight to Watchlist search.
        app.tabBars.buttons["Watchlist"].tap()
        searchWatchlist(for: "zzzznomatch")
        // The no-matches identifier is shared by each of its children, so
        // target the message itself.
        let message = app.staticTexts["No tracked shows match “zzzznomatch”."]
        scrollIntoView(message, "The no-matches message should be reachable by scrolling.")
    }

    // MARK: - Helpers

    private func tapTryExampleAfterScrolling() {
        assertExists(tryExampleButton, "Search should offer Try an Example on first launch.")
        scrollIntoView(tryExampleButton, "Try an Example should be reachable by scrolling.")
        tryExampleButton.tap()
    }

    /// Swipes up until the bottom of `element` clears the tab bar, then asserts it.
    /// Does not require `element` to exist first: List creates off-screen rows
    /// and footers lazily.
    private func scrollIntoView(_ element: XCUIElement, _ message: String) {
        _ = element.waitForExistence(timeout: UITestTimeout.standard)
        var swipes = 0
        while !isFullyVisible(element), swipes < maximumSwipes {
            app.swipeUp()
            swipes += 1
        }
        if !isFullyVisible(element) {
            recordFailureContext(message)
        }
        XCTAssertTrue(isFullyVisible(element), message)
    }

    /// Hittable with its bottom edge above the tab bar, so none of it is hidden
    /// behind the bar and a tap reaches it.
    private func isFullyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        return element.frame.maxY <= app.tabBars.firstMatch.frame.minY
    }

    /// Scrolling back to the top restores the search field, and tabs still respond.
    private func assertSearchChromeReachable() {
        var swipes = 0
        while !searchField.isHittable, swipes < maximumSwipes {
            app.swipeDown()
            swipes += 1
        }
        XCTAssertTrue(searchField.isHittable, "The search field should remain reachable.")

        let watchlistTab = app.tabBars.buttons["Watchlist"]
        XCTAssertTrue(watchlistTab.isHittable, "The tab bar should remain usable.")
        watchlistTab.tap()
        XCTAssertTrue(
            app.navigationBars["Watchlist"].waitForExistence(timeout: UITestTimeout.standard),
            "Selecting Watchlist should still navigate at the largest text size."
        )
    }
}
