//
//  PausedWatchlistUITests.swift
//  NextSeasonUITests
//

import XCTest

/// Paused (Plus-lapsed) Watchlist rows: visible, not openable, still removable.
///
/// Launches with `-UITestingSeedPausedShow`, which starts the in-memory store
/// with the preview show already paused and Free access.
@MainActor
final class PausedWatchlistUITests: XCTestCase, NextSeasonUITesting {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            UITestingLaunchArgument.uiTesting, UITestingLaunchArgument.seedPausedShow,
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITestTimeout.standard))
        app.tabBars.buttons["Watchlist"].tap()
    }

    override func tearDown() async throws {
        app = nil
    }

    func testTappingPausedRowDoesNotOpenShowDetails() {
        assertExists(
            app.staticTexts["Paused — Plus Required"], "The paused section header should show.")
        let row = watchlistRow(named: UITestPreviewShow.name)
        assertExists(row, "The paused show should be listed.")

        row.tap()

        let detail = showDetailTrackButton()
        XCTAssertFalse(
            detail.waitForExistence(timeout: 2),
            "Tapping a paused row must not open Show Details.")
        assertExists(row, "The Watchlist should still be on screen.")
    }

    func testPausedRowCanBeDeleted() {
        let row = watchlistRow(named: UITestPreviewShow.name)
        assertExists(row, "The paused show should be listed.")

        row.swipeLeft()
        let delete = app.buttons["Delete"]
        assertExists(delete, "Swipe should reveal Delete for a paused row.")
        delete.tap()

        waitForWatchlistRowToDisappear(named: UITestPreviewShow.name)
        // Swipe-delete persists immediately and shows an informational undo toast;
        // the empty state appears once the toast is dismissed.
        assertExists(watchlistConfirmButton, "Deleting should show the undo toast.")
        watchlistConfirmButton.tap()
        assertExists(watchlistEmptyState, "Deleting the only show leaves the empty state.")
    }
}
