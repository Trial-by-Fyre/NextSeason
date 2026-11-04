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

    /// The seed has no active shows, so a free slot is open.
    func testTappingPausedRowReactivatesWithoutOpeningShowDetails() {
        let header = app.staticTexts["Paused"]
        assertExists(header, "The paused section header should show.")
        let row = watchlistRow(named: UITestPreviewShow.name)
        assertExists(row, "The paused show should be listed.")
        XCTAssertEqual(row.elementType, .button, "The paused row should be a button.")

        row.tap()

        let detail = showDetailTrackButton()
        XCTAssertFalse(
            detail.waitForExistence(timeout: 2),
            "Tapping a paused row must not open Show Details.")
        assertExists(row, "The reactivated show should still be listed.")
        let sectionGone = NSPredicate(format: "exists == false")
        expectation(for: sectionGone, evaluatedWith: header)
        waitForExpectations(timeout: UITestTimeout.standard)
    }

    func testPausedRowStarStartsRemovalInsteadOfReactivating() {
        let row = watchlistRow(named: UITestPreviewShow.name)
        assertExists(row, "The paused show should be listed.")

        app.buttons["\(AccessibilityID.Watchlist.trackButton).\(UITestPreviewShow.id)"].tap()

        assertExists(watchlistUndoButton, "The star should start an undoable removal.")
        watchlistUndoButton.tap()
        assertExists(row, "Undo keeps the paused show.")
        // A mistaken reactivation would remove the section after its fetch, so
        // give it time before confirming the show is still paused.
        XCTAssertFalse(
            showDetailTrackButton().waitForExistence(timeout: 2),
            "The star must not open Show Details.")
        XCTAssertTrue(
            app.staticTexts["Paused"].exists, "The star must not reactivate the show.")
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
