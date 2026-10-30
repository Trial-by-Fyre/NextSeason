//
//  SearchAndTrackUITests.swift
//  NextSeasonUITests
//

import XCTest

/// XCUITest coverage for Search, tracking, Watchlist undo, and related empty/error
/// paths. Uses `NextSeasonUITesting` so launches pass `-UITesting` and never hit
/// the live network.
@MainActor
final class SearchAndTrackUITests: XCTestCase, NextSeasonUITesting {
    var app: XCUIApplication!
    private let previewShowName = "Severance"

    override func setUp() async throws {
        try await super.setUp()
        try await launchUITestingApp()
    }

    func testSearchOpensShowDetail() {
        search(for: previewShowName)

        let result = waitForSearchResultRow(named: previewShowName)
        result.tap()

        waitForShowDetail()
        XCTAssertTrue(
            app.staticTexts["Next Season"].waitForExistenceIfNeeded(
                timeout: UITestTimeout.standard
            ))
    }

    func testTrackShowAppearsOnWatchlist() {
        trackShowFromDetail()

        app.tabBars.buttons["Watchlist"].tap()
        XCTAssertTrue(
            watchlistRow(named: previewShowName).waitForExistenceIfNeeded(
                timeout: UITestTimeout.extended
            ),
            "Tracked show should appear on the watchlist."
        )
        XCTAssertFalse(watchlistEmptyState.exists)
    }

    func testTryExampleButtonRunsSearch() {
        XCTAssertTrue(searchIdlePrompt.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        tapTryExample()

        waitForSearchResultRow(named: previewShowName, timeout: UITestTimeout.extended)
    }

    func testTryExamplePopulatesSearchField() {
        XCTAssertTrue(searchIdlePrompt.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        tapTryExample()

        XCTAssertTrue(
            waitForSearchFieldValue(previewShowName),
            "Try an Example should prefill the search field with the example query."
        )
    }

    func testSearchResultsHintAppearsOnFirstResults() {
        tapTryExample()

        waitForSearchResultRow(named: previewShowName, timeout: UITestTimeout.extended)
        XCTAssertTrue(
            searchResultsHint.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "The first search results should show row guidance below the list."
        )
    }

    func testSearchResultsHintDismissesAfterTrack() {
        tapTryExample()
        XCTAssertTrue(searchResultsHint.waitForExistenceIfNeeded(timeout: UITestTimeout.extended))

        let trackButton = searchTrackButton()
        XCTAssertTrue(trackButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        trackButton.tap()
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.Search.trackButton).\(UITestPreviewShow.tvdbID)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.trackState
            )
        )

        XCTAssertFalse(
            searchResultsHint.waitForExistence(timeout: 2),
            "Tracking a show should dismiss the search results hint."
        )
    }

    func testSearchResultsHintDismissesAfterOpeningDetail() {
        tapTryExample()
        XCTAssertTrue(searchResultsHint.waitForExistenceIfNeeded(timeout: UITestTimeout.extended))

        let result = waitForSearchResultRow(named: previewShowName)
        result.tap()

        waitForShowDetail()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        waitForSearchResultRow(named: previewShowName)
        XCTAssertFalse(
            searchResultsHint.waitForExistence(timeout: 2),
            "Opening show detail should dismiss the search results hint."
        )
    }

    func testSearchWithNoResultsShowsFallbackGuidance() {
        search(for: UITestingSearchQuery.noResults)

        XCTAssertTrue(
            searchNoResults.waitForExistenceIfNeeded(timeout: UITestTimeout.extended),
            "An empty result set should show the fallback guidance, not imply the show is missing."
        )
        XCTAssertTrue(
            app.staticTexts[
                "Try a more specific title — add a subtitle or the year (for example, “Title: Subtitle” or “Title 2019”)."
            ].exists,
            "The guidance text should be exposed to VoiceOver, not hidden behind the title."
        )
    }

    func testSearchFailureShowsRetryState() {
        search(for: UITestingSearchQuery.failure)

        XCTAssertTrue(
            app.staticTexts["Something Went Wrong"].waitForExistenceIfNeeded(
                timeout: UITestTimeout.extended),
            "A failed search should surface an error state."
        )
        XCTAssertTrue(
            app.buttons["Try Again"].waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "The failure state should offer a retry action."
        )
    }

    func testReopeningTrackedShowReflectsTrackedState() {
        search(for: previewShowName)

        let result = waitForSearchResultRow(named: previewShowName)
        result.tap()

        let trackButton = showDetailTrackButton()
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.ShowDetail.trackButton).\(UITestPreviewShow.id)",
                labelContaining: "Track",
                timeout: UITestTimeout.standard
            ),
            "An untracked show should offer to Track."
        )
        trackButton.tap()
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.ShowDetail.trackButton).\(UITestPreviewShow.id)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.trackState
            ),
            "Tapping Track should mark the show as tracked."
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()

        result.tap()
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.ShowDetail.trackButton).\(UITestPreviewShow.id)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.extended
            ),
            "Reopening an already-tracked show should reflect the tracked state."
        )
    }

    func testTrackFromSearchRowWithoutOpeningDetail() {
        search(for: previewShowName)

        let trackButton = searchTrackButton()
        XCTAssertTrue(trackButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        trackButton.tap()

        XCTAssertFalse(
            app.navigationBars[previewShowName].waitForExistence(timeout: 1),
            "Tracking from the search row should not navigate to show detail."
        )
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.Search.trackButton).\(UITestPreviewShow.tvdbID)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.trackState
            ),
            "The search-row track button should reflect the tracked state."
        )

        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: previewShowName, timeout: UITestTimeout.trackState)
    }

    func testSearchRowUntrackShowsUndoToast() {
        trackShowFromSearchRow()

        searchTrackButton().tap()

        XCTAssertTrue(
            watchlistUndoButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "Untracking from the search row should offer Undo."
        )
        XCTAssertTrue(
            waitForPendingUntrackTrackButton(
                "\(AccessibilityID.Search.trackButton).\(UITestPreviewShow.tvdbID)"
            ),
            "The search-row star should reflect the pending untrack state."
        )

        watchlistConfirmButton.tap()

        app.tabBars.buttons["Watchlist"].tap()
        XCTAssertTrue(
            watchlistEmptyState.waitForExistenceIfNeeded(timeout: UITestTimeout.extended),
            "Confirming removal from search should clear the watchlist."
        )
    }

    func testRemoveLastShowViaStarShowsUndoThenEmptyState() {
        trackShowFromSearchRow()

        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: previewShowName)

        watchlistTrackButton().tap()

        XCTAssertTrue(
            watchlistUndoButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "Removing a show should offer Undo."
        )
        XCTAssertTrue(
            watchlistRow(named: previewShowName).waitForExistenceIfNeeded(
                timeout: UITestTimeout.standard
            ),
            "The watchlist row should stay visible while Undo is offered."
        )
        XCTAssertFalse(
            watchlistEmptyState.exists,
            "The empty state should not appear until the removal is committed."
        )

        watchlistConfirmButton.tap()

        waitForWatchlistRowToDisappear(named: previewShowName)
        XCTAssertTrue(
            watchlistEmptyState.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "After confirming removal, the watchlist should show its empty state."
        )

        app.tabBars.buttons["Search"].tap()
        searchTrackButton().tap()

        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: previewShowName)
    }

    func testWatchlistUndoRestoresRemovedShow() {
        trackShowFromSearchRow()

        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: previewShowName)

        watchlistTrackButton().tap()
        XCTAssertTrue(watchlistUndoButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        watchlistUndoButton.tap()

        waitForWatchlistRow(named: previewShowName)
        XCTAssertFalse(watchlistEmptyState.exists)
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.Watchlist.trackButton).\(UITestPreviewShow.id)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.trackState
            ),
            "Undo should restore the tracked star on the watchlist row."
        )
    }

    func testWatchlistStarTapUndoesPendingRemoval() {
        trackShowFromSearchRow()

        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: previewShowName)

        watchlistTrackButton().tap()
        XCTAssertTrue(watchlistUndoButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))

        watchlistTrackButton().tap()

        XCTAssertFalse(watchlistUndoButton.waitForExistence(timeout: 1))
        waitForWatchlistRow(named: previewShowName)
    }

    func testUntrackFromDetailShowsUndoToast() {
        trackShowFromDetail()

        showDetailTrackButton().tap()

        XCTAssertTrue(
            watchlistUndoButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "Untracking from detail should offer Undo."
        )
        XCTAssertTrue(
            waitForPendingUntrackTrackButton(
                "\(AccessibilityID.ShowDetail.trackButton).\(UITestPreviewShow.id)"
            ),
            "The detail star should reflect the pending untrack state."
        )

        watchlistUndoButton.tap()

        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.ShowDetail.trackButton).\(UITestPreviewShow.id)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.standard
            ),
            "Undo on detail should restore the tracked state."
        )
    }

    func testUntrackFromDetailConfirmRemovesFromWatchlist() {
        trackShowFromDetail()

        showDetailTrackButton().tap()
        XCTAssertTrue(watchlistUndoButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        watchlistConfirmButton.tap()

        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRowToDisappear(named: previewShowName)
        XCTAssertTrue(
            watchlistEmptyState.waitForExistenceIfNeeded(timeout: UITestTimeout.standard),
            "Confirming removal from detail should clear the watchlist."
        )
    }

    /// Blank space between the title and the star opens detail, like the title.
    func testTappingSearchRowBlankSpaceOpensShowDetail() {
        search(for: previewShowName)
        waitForSearchResultRow(named: previewShowName)

        let trackButton = searchTrackButton()
        XCTAssertTrue(trackButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        // Just left of the star, past the end of the title and subtitle text.
        let star = trackButton.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: star.minX - 24, dy: star.midY))
            .tap()

        waitForShowDetail()
    }

    /// Returning from detail keeps the query and results but does not reopen
    /// the keyboard over them.
    func testReturningFromShowDetailDoesNotRestoreSearchKeyboard() {
        // Type without submitting (`search(for:)` taps Search), so the keyboard
        // is still up when the row is opened, as in manual use.
        XCTAssertTrue(focusSearchField(searchField), "Search field should take focus.")
        searchField.typeText(previewShowName)
        let result = waitForSearchResultRow(named: previewShowName)
        XCTAssertTrue(app.keyboards.element.exists, "Typing should leave the keyboard up.")
        result.tap()
        waitForShowDetail()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        waitForSearchResultRow(named: previewShowName)
        XCTAssertEqual(searchFieldText(), previewShowName)
        XCTAssertFalse(
            app.keyboards.element.waitForExistence(timeout: 2),
            "Returning from detail should not reopen the search keyboard."
        )
    }

    /// A deferred removal started in detail is persisted on return to the
    /// Watchlist, so the row leaves at once, and the toast's Undo still restores it.
    func testRemovingFromWatchlistDetailRemovesRowOnReturnAndUndoRestores() {
        trackShowFromSearchRow()
        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: previewShowName).tap()
        showDetailTrackButton().tap()
        XCTAssertTrue(watchlistUndoButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))

        app.navigationBars.buttons.element(boundBy: 0).tap()

        // UI tests use a 30-second undo window, so this cannot be the timeout.
        waitForWatchlistRowToDisappear(named: previewShowName, timeout: UITestTimeout.standard)
        XCTAssertTrue(
            watchlistUndoButton.exists, "Undo should stay available after the row leaves.")
        watchlistUndoButton.tap()
        waitForWatchlistRow(named: previewShowName)
    }

    // MARK: - Helpers

    /// Search → row star → wait until the row shows Stop tracking (no detail push).
    private func trackShowFromSearchRow() {
        search(for: previewShowName)

        let trackButton = searchTrackButton()
        XCTAssertTrue(trackButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        trackButton.tap()
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.Search.trackButton).\(UITestPreviewShow.tvdbID)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.trackState
            ),
            "The search-row track button should reflect the tracked state."
        )
    }

    /// Search → open detail → star → wait until the detail button shows Stop tracking.
    private func trackShowFromDetail() {
        search(for: previewShowName)

        let result = waitForSearchResultRow(named: previewShowName)
        result.tap()

        let trackButton = showDetailTrackButton()
        XCTAssertTrue(trackButton.waitForExistenceIfNeeded(timeout: UITestTimeout.standard))
        trackButton.tap()
        XCTAssertTrue(
            waitForButton(
                "\(AccessibilityID.ShowDetail.trackButton).\(UITestPreviewShow.id)",
                labelContaining: "Stop tracking",
                timeout: UITestTimeout.trackState
            )
        )
    }
}
