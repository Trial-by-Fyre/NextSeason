//
//  NextSeasonUITesting.swift
//  NextSeasonUITests
//

import XCTest

// MARK: - Overview
//
// Shared UI-test harness as a protocol + extension — not an XCTestCase subclass —
// so Xcode does not list a phantom un-runnable suite. Concrete test classes
// (e.g. `NavigationUITests`) conform to `NextSeasonUITesting` and call
// `launchUITestingApp()` from `setUp()`.
//
// It provides:
//   • App launch: `launchUITestingApp()` with the `-UITesting` argument
//     (stubbed network data) and a foreground wait.
//   • Shared constants from NextSeasonShared: `AccessibilityID`,
//     `UITestingSearchQuery`, and `UITestingLaunchArgument`.
//   • Reusable element accessors and interaction/assertion helpers.

enum UITestTimeout {
    static let standard: TimeInterval = 5
    static let extended: TimeInterval = 10
    /// Tracking persists asynchronously; allow extra time under simulator load.
    static let trackState: TimeInterval = 15
}

/// Values that match the stubbed preview show returned during UI testing.
enum UITestPreviewShow {
    static let name = "Severance"
    /// Canonical TVMaze id (detail / watchlist).
    static let id = 44933
    /// TheTVDB series id used by search-row accessibility identifiers.
    static let tvdbID = 371980
    /// Search-row subtitle from TheTVDB stub (`year · status`).
    static let searchStatus = "2022 · Continuing"
}

/// Shared UI-test surface: launched app + helpers. Conform from an `XCTestCase`.
@MainActor
protocol NextSeasonUITesting: AnyObject {
    var app: XCUIApplication! { get set }
}

@MainActor
extension NextSeasonUITesting where Self: XCTestCase {
    private var searchFieldPlaceholder: String { "Search TV shows" }
    private var watchlistSearchFieldPlaceholder: String { "Search Watchlist" }

    var searchIdlePrompt: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Search.idlePrompt]
    }

    var watchlistEmptyState: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Watchlist.emptyState]
    }

    var watchlistNoResults: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Watchlist.noResults]
    }

    /// The watchlist's own search field (distinct from the Search tab field).
    var watchlistSearchField: XCUIElement {
        app.searchFields[watchlistSearchFieldPlaceholder]
    }

    var watchlistSearchButton: XCUIElement {
        app.navigationBars["Watchlist"].buttons[AccessibilityID.Watchlist.searchButton]
    }

    var searchNoResults: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Search.noResults]
    }

    var searchField: XCUIElement {
        app.searchFields[searchFieldPlaceholder]
    }

    var tryExampleButton: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Search.tryExampleButton]
    }

    var searchResultsHint: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Search.resultsHint]
    }

    var watchlistUndoButton: XCUIElement {
        let byID = app.descendants(matching: .any)[AccessibilityID.Watchlist.undoButton]
        if byID.exists { return byID }
        return app.buttons["Undo"]
    }

    var watchlistConfirmButton: XCUIElement {
        let byID = app.descendants(matching: .any)[AccessibilityID.Watchlist.confirmButton]
        if byID.exists { return byID }
        return app.buttons["OK"]
    }

    /// Launches the app with stubbed network data for UI tests.
    func launchUITestingApp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [UITestingLaunchArgument.uiTesting]
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: UITestTimeout.standard),
            "NextSeason should launch to the foreground during UI tests."
        )
    }

    /// Captures the current screen and accessibility tree when an assertion fails.
    func recordFailureContext(_ step: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Screenshot — \(step)"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Accessibility hierarchy — \(step)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = UITestTimeout.standard,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if !element.waitForExistence(timeout: timeout) {
            recordFailureContext(message)
            XCTFail(message, file: file, line: line)
        }
    }

    func assertNotExists(
        _ element: XCUIElement,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if element.exists {
            recordFailureContext(message)
            XCTFail(message, file: file, line: line)
        }
    }

    func waitForButton(_ identifier: String, labelContaining text: String, timeout: TimeInterval)
        -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let button = app.descendants(matching: .any)[identifier]
            if button.exists, button.label.localizedCaseInsensitiveContains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    /// Waits until a track star reflects a pending undoable removal.
    func waitForPendingUntrackTrackButton(
        _ identifier: String,
        timeout: TimeInterval = UITestTimeout.standard
    ) -> Bool {
        waitForButton(identifier, labelContaining: "Undo removing", timeout: timeout)
    }

    /// Waits until the watchlist row for a show is no longer visible.
    func waitForWatchlistRowToDisappear(
        named showName: String,
        showID: Int = UITestPreviewShow.id,
        timeout: TimeInterval = UITestTimeout.extended
    ) {
        let row = watchlistRow(named: showName, showID: showID)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !row.exists { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        recordFailureContext("Watchlist row should disappear for “\(showName)”")
        XCTFail("Watchlist row should disappear for “\(showName)”.")
    }

    func watchlistRow(named showName: String, showID: Int = UITestPreviewShow.id) -> XCUIElement {
        app.descendants(matching: .any)["\(AccessibilityID.Watchlist.row).\(showID)"]
    }

    /// Search result row in the list. Labels include network after the subtitle.
    func searchResultRow(
        named showName: String,
        showID: Int = UITestPreviewShow.tvdbID,
        status: String = UITestPreviewShow.searchStatus
    ) -> XCUIElement {
        let byID = app.descendants(matching: .any)["\(AccessibilityID.Search.result).\(showID)"]
        if byID.exists { return byID }

        let prefix = "\(showName), \(status)"
        return app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", prefix)
        ).firstMatch
    }

    /// Waits for a search result row by stable identifier, then by combined label.
    @discardableResult
    func waitForSearchResultRow(
        named showName: String,
        showID: Int = UITestPreviewShow.tvdbID,
        status: String = UITestPreviewShow.searchStatus,
        timeout: TimeInterval = UITestTimeout.standard
    ) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let row = searchResultRow(named: showName, showID: showID, status: status)
            if row.exists { return row }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let searchValue = searchFieldText() ?? searchFieldPlaceholder
        recordFailureContext("Search should return “\(showName)”")
        XCTFail(
            """
            Search should return “\(showName)” (id: \(AccessibilityID.Search.result).\(showID)). \
            Search field value: “\(searchValue)”.
            """
        )
        return searchResultRow(named: showName, showID: showID, status: status)
    }

    /// Waits for a watchlist row by stable identifier, then by combined label.
    @discardableResult
    func waitForWatchlistRow(
        named showName: String,
        showID: Int = UITestPreviewShow.id,
        timeout: TimeInterval = UITestTimeout.extended
    ) -> XCUIElement {
        let byID = watchlistRow(named: showName, showID: showID)
        if byID.waitForExistence(timeout: timeout) {
            return byID
        }

        let byLabel = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] 'Updated'",
                showName
            )
        ).firstMatch
        XCTAssertTrue(
            byLabel.waitForExistence(timeout: timeout),
            "Watchlist should show “\(showName)”."
        )
        return byLabel
    }

    func searchTrackButton(showID: Int = UITestPreviewShow.tvdbID) -> XCUIElement {
        let byID = app.descendants(matching: .any)[
            "\(AccessibilityID.Search.trackButton).\(showID)"]
        if byID.exists { return byID }
        return app.buttons["Track \(UITestPreviewShow.name)"]
    }

    func watchlistTrackButton(showID: Int = UITestPreviewShow.id) -> XCUIElement {
        let byID = app.descendants(matching: .any)[
            "\(AccessibilityID.Watchlist.trackButton).\(showID)"]
        if byID.exists { return byID }
        let stop = app.buttons["Stop tracking \(UITestPreviewShow.name)"]
        if stop.exists { return stop }
        return app.buttons["Track \(UITestPreviewShow.name)"]
    }

    func showDetailTrackButton(showID: Int = UITestPreviewShow.id) -> XCUIElement {
        app.descendants(matching: .any)["\(AccessibilityID.ShowDetail.trackButton).\(showID)"]
    }

    /// Detail-only track control; does not match the search-row star.
    @discardableResult
    func waitForShowDetail(
        showID: Int = UITestPreviewShow.id,
        timeout: TimeInterval = UITestTimeout.standard
    ) -> XCUIElement {
        let button = showDetailTrackButton(showID: showID)
        assertExists(
            button,
            timeout: timeout,
            "Show detail should display the track control (id: \(AccessibilityID.ShowDetail.trackButton).\(showID))."
        )
        return button
    }

    /// Taps `field` and waits for the keyboard, retrying the tap a few times.
    /// XCUITest can drop synthesized key events when typing races the focus
    /// handoff to a `.searchable` field, so callers must confirm focus first.
    @discardableResult
    func focusSearchField(_ field: XCUIElement, timeout: TimeInterval = UITestTimeout.standard)
        -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            field.tap()
            if app.keyboards.element.waitForExistence(timeout: 1) {
                return true
            }
        }
        return app.keyboards.element.exists
    }

    /// Returns user-entered search text, ignoring placeholder/empty values.
    func searchFieldText(in field: XCUIElement? = nil) -> String? {
        let field = field ?? searchField
        return enteredText(in: field, placeholder: searchFieldPlaceholder)
    }

    /// Returns user-entered watchlist search text, ignoring the placeholder/empty value.
    func watchlistSearchFieldText() -> String? {
        enteredText(in: watchlistSearchField, placeholder: watchlistSearchFieldPlaceholder)
    }

    func search(for query: String) {
        typeIntoSearchField(
            searchField,
            placeholder: searchFieldPlaceholder,
            query: query,
            missingFieldMessage:
                "Search tab should expose the “Search TV shows” field before typing."
        )
    }

    func searchWatchlist(for query: String) {
        revealWatchlistSearchField()
        typeIntoSearchField(
            watchlistSearchField,
            placeholder: watchlistSearchFieldPlaceholder,
            query: query,
            missingFieldMessage:
                "Watchlist should expose the “Search Watchlist” field before typing."
        )
    }

    func revealWatchlistSearchField() {
        if watchlistSearchField.exists {
            return
        }
        assertExists(
            watchlistSearchButton,
            "Watchlist should expose a search toolbar button before revealing search."
        )
        watchlistSearchButton.tap()
        assertExists(
            watchlistSearchField,
            "Tapping the watchlist search button should reveal the search field."
        )
    }

    func tapTryExample() {
        XCTAssertTrue(tryExampleButton.waitForExistence(timeout: UITestTimeout.standard))
        tryExampleButton.tap()
    }

    func clearSearchField(clearingField field: XCUIElement? = nil) {
        let field = field ?? searchField
        clearSearchField(field, placeholder: searchFieldPlaceholder)
    }

    func clearWatchlistSearchField() {
        clearSearchField(watchlistSearchField, placeholder: watchlistSearchFieldPlaceholder)
    }

    @discardableResult
    func waitForSearchFieldValue(
        _ expected: String,
        timeout: TimeInterval = UITestTimeout.extended
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if searchFieldText() == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    // MARK: - Shared search-field helpers

    private func enteredText(in field: XCUIElement, placeholder: String) -> String? {
        guard let value = field.value as? String else { return nil }
        guard !value.isEmpty, value != placeholder else { return nil }
        return value
    }

    private func typeIntoSearchField(
        _ field: XCUIElement,
        placeholder: String,
        query: String,
        missingFieldMessage: String
    ) {
        assertExists(field, missingFieldMessage)

        if enteredText(in: field, placeholder: placeholder) != nil {
            clearSearchField(field, placeholder: placeholder)
        }

        // Focus immediately before typing so any prior keyboard dismissal (e.g.
        // from clearing) can't leave the field unfocused when key events arrive.
        focusSearchField(field)
        field.typeText(query)
        dismissSearchKeyboardIfPresent()
    }

    private func clearSearchField(_ field: XCUIElement, placeholder: String) {
        assertExists(field, "Search field should exist before clearing.")
        focusSearchField(field)

        let clearCandidates = [
            field.buttons["Clear text"],
            app.buttons["Clear text"],
            app.navigationBars.buttons["Clear text"],
        ]
        for clearButton in clearCandidates where clearButton.waitForExistence(timeout: 1) {
            clearButton.tap()
            if enteredText(in: field, placeholder: placeholder) == nil { return }
        }

        guard enteredText(in: field, placeholder: placeholder) != nil else { return }

        // Prefer select-all over per-character delete; tapping keyboard keys is flaky on
        // narrow simulators (XCTest fails to scroll the delete key into view).
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 1) {
            app.menuItems["Select All"].tap()
        } else {
            field.typeKey("a", modifierFlags: [.command])
        }
        field.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        dismissSearchKeyboardIfPresent()
    }

    private func dismissSearchKeyboardIfPresent() {
        let searchKey = app.keyboards.buttons["Search"]
        guard searchKey.waitForExistence(timeout: 1) else { return }
        // The key can exist while the keyboard is still off-screen; tapping it then
        // fails with "failed to scroll to visible" (seen on iOS 27). Return submits
        // the search the same way without needing the key on screen.
        if searchKey.isHittable {
            searchKey.tap()
        } else {
            app.typeText(XCUIKeyboardKey.return.rawValue)
        }
    }
}
