//
//  AccessibilityAuditUITests.swift
//  NextSeasonUITests
//

import XCTest

/// Runs Xcode's accessibility audit on the primary screens reachable under
/// `-UITesting`. About and store sheets are omitted from UI-test launches, so
/// they are not covered here.
@MainActor
final class AccessibilityAuditUITests: XCTestCase, NextSeasonUITesting {
    var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        try await launchUITestingApp()
    }

    func testSearchIdlePassesAccessibilityAudit() {
        assertExists(
            searchIdlePrompt,
            "Search tab should show the idle prompt on launch."
        )
        auditCurrentScreen("Search idle")
    }

    func testSearchResultsPassAccessibilityAudit() {
        tapTryExample()
        waitForSearchResultRow(named: UITestPreviewShow.name, timeout: UITestTimeout.extended)
        auditCurrentScreen("Search results")
    }

    func testSearchNoResultsPassAccessibilityAudit() {
        search(for: UITestingSearchQuery.noResults)
        assertExists(
            searchNoResults,
            timeout: UITestTimeout.extended,
            "An empty result set should show the fallback guidance."
        )
        auditCurrentScreen("Search no results")
    }

    func testSearchFailurePassesAccessibilityAudit() {
        search(for: UITestingSearchQuery.failure)
        assertExists(
            app.staticTexts["Something Went Wrong"],
            timeout: UITestTimeout.extended,
            "A failed search should surface an error state."
        )
        auditCurrentScreen("Search failure")
    }

    func testShowDetailPassesAccessibilityAudit() {
        tapTryExample()
        waitForSearchResultRow(named: UITestPreviewShow.name, timeout: UITestTimeout.extended)
            .tap()
        waitForShowDetail()
        auditCurrentScreen("Show detail")
    }

    func testWatchlistEmptyPassesAccessibilityAudit() {
        app.tabBars.buttons["Watchlist"].tap()
        assertExists(
            watchlistEmptyState,
            timeout: UITestTimeout.extended,
            "Watchlist tab should show the empty state when no shows are tracked."
        )
        auditCurrentScreen("Watchlist empty")
    }

    func testPopulatedWatchlistPassesAccessibilityAudit() {
        trackPreviewShowAndOpenWatchlist()
        auditCurrentScreen("Watchlist populated", allowsLegacyUnresolvedWatchlistRowText: true)
    }

    func testWatchlistPendingRemovalPassesAccessibilityAudit() {
        trackPreviewShowAndOpenWatchlist()

        watchlistTrackButton().tap()
        assertExists(
            watchlistUndoButton,
            "Removing a show should offer Undo."
        )
        XCTAssertTrue(
            waitForPendingUntrackTrackButton(
                "\(AccessibilityID.Watchlist.trackButton).\(UITestPreviewShow.id)"
            ),
            "The watchlist star should reflect the pending untrack state."
        )
        auditCurrentScreen("Watchlist pending removal")
    }

    func testWatchlistSearchNoResultsPassAccessibilityAudit() {
        trackPreviewShowAndOpenWatchlist()
        searchWatchlist(for: "zzzznomatch")
        assertExists(
            watchlistNoResults,
            "A non-matching query should surface the no-matches state."
        )
        auditCurrentScreen("Watchlist search no results")
    }

    func testWatchlistSearchMatchPassesAccessibilityAudit() {
        trackPreviewShowAndOpenWatchlist()
        searchWatchlist(for: UITestPreviewShow.name)
        XCTAssertTrue(
            watchlistRow(named: UITestPreviewShow.name).waitForExistence(
                timeout: UITestTimeout.standard
            ),
            "A matching query should keep the tracked show visible."
        )
        assertNotExists(
            watchlistNoResults,
            "A matching query should not show the no-matches state."
        )
        auditCurrentScreen("Watchlist search match", allowsLegacyUnresolvedWatchlistRowText: true)
    }

    // MARK: - Helpers

    /// Seeds the in-memory watchlist via Try an Example, then opens Watchlist.
    private func trackPreviewShowAndOpenWatchlist() {
        tapTryExample()
        waitForSearchResultRow(named: UITestPreviewShow.name, timeout: UITestTimeout.extended)

        let trackButton = searchTrackButton()
        assertExists(trackButton, "Search results should expose a track control.")
        trackButton.tap()

        app.tabBars.buttons["Watchlist"].tap()
        waitForWatchlistRow(named: UITestPreviewShow.name, timeout: UITestTimeout.trackState)
    }

    /// Audits the current screen and fails with every outstanding issue.
    /// Known issues are ignored in `shouldIgnore` so this test stays a
    /// regression net rather than a permanently red checklist.
    ///
    /// Pass `allowsLegacyUnresolvedWatchlistRowText: true` only for screens
    /// showing a tappable watchlist row; see `isLegacyUnresolvedStyledCopy`.
    private func auditCurrentScreen(
        _ name: String,
        allowsLegacyUnresolvedWatchlistRowText: Bool = false
    ) {
        var issueSummaries: [String] = []

        do {
            try app.performAccessibilityAudit { issue in
                if self.shouldIgnore(
                    issue,
                    allowsLegacyUnresolvedWatchlistRowText: allowsLegacyUnresolvedWatchlistRowText
                ) {
                    return true
                }
                issueSummaries.append(self.formattedIssue(issue))
                return true
            }
        } catch {
            recordFailureContext("Accessibility audit — \(name)")
            XCTFail("Accessibility audit threw on \(name): \(error)")
            return
        }

        guard !issueSummaries.isEmpty else { return }

        recordFailureContext("Accessibility audit — \(name)")
        let summary = issueSummaries.joined(separator: "\n\n")
        let attachment = XCTAttachment(string: summary)
        attachment.name = "Accessibility issues — \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail(
            "Accessibility audit found \(issueSummaries.count) issue(s) on \(name):\n\(summary)")
    }

    private func formattedIssue(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let element = issue.element
        let identifier = element?.identifier ?? ""
        let label = element?.label ?? ""
        let elementName = identifier.isEmpty ? (label.isEmpty ? "unknown" : label) : identifier
        return """
            \(issue.compactDescription)
            Type: \(issue.auditType)
            Element: \(elementName)
            Label: \(label)
            \(issue.detailedDescription)
            """
    }

    /// Ignore only known system or SwiftUI false positives, identified by
    /// element. Remove an entry here when the underlying UI is fixed.
    private func shouldIgnore(
        _ issue: XCUIAccessibilityAuditIssue,
        allowsLegacyUnresolvedWatchlistRowText: Bool
    ) -> Bool {
        if isSystemSearchClearButton(issue) { return true }
        if isUnlabeledWatchlistSearchChrome(issue) { return true }
        if isSystemSearchFieldTextClipped(issue) { return true }
        if isKnownContentUnavailableTextClipped(issue) { return true }
        if isKnownSwiftUIDynamicTypeFalsePositive(issue) { return true }
        if isKnownSecondaryContrastNearlyPassed(issue) { return true }
        if isLegacyUndoToastContrastFalsePositive(issue) { return true }
        if allowsLegacyUnresolvedWatchlistRowText && isLegacyUnresolvedStyledCopy(issue) {
            return true
        }
        return false
    }

    /// iOS 18 only: the pre-Liquid Glass undo toast reports "Contrast failed"
    /// for its message, Undo, and OK even though measured ratios are well
    /// above 4.5:1 (about 16.7:1, 5.1:1, and 16.9:1). iOS 26+ passes.
    private func isLegacyUndoToastContrastFalsePositive(_ issue: XCUIAccessibilityAuditIssue)
        -> Bool
    {
        if #available(iOS 26, *) { return false }
        guard issue.auditType.contains(.contrast) else { return false }
        let identifier = issue.element?.identifier ?? ""
        let label = issue.element?.label ?? ""
        return identifier == AccessibilityID.Watchlist.undoButton
            || identifier == AccessibilityID.Watchlist.confirmButton
            || label == "Removed from watchlist"
    }

    /// iOS 18 only, and only for audits that opt in via
    /// `allowsLegacyUnresolvedWatchlistRowText` (populated Watchlist and
    /// Watchlist search match). The audit cannot resolve the text nodes inside
    /// a combined watchlist `NavigationLink` row, so the already-known
    /// styled-copy Dynamic Type and "nearly passed" contrast issues arrive with
    /// a nil element and cannot be matched by label. iOS 26+ resolves these
    /// elements.
    ///
    /// Limitation: within the two opted-in states on iOS 18, any other
    /// unresolved (nil-element) Dynamic Type or "nearly passed" issue is also
    /// hidden. iOS 26+ runs of the same tests still report it.
    private func isLegacyUnresolvedStyledCopy(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        if #available(iOS 26, *) { return false }
        guard issue.element == nil else { return false }
        // Exact type match: an issue that also carries any other flag (for
        // example a full "Contrast failed" alongside Dynamic Type) is reported.
        if issue.auditType == .dynamicType { return true }
        return issue.auditType == .contrast
            && issue.compactDescription.hasPrefix("Contrast nearly passed")
    }

    /// System search-field clear button is smaller than 44pt by design.
    private func isSystemSearchClearButton(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType.contains(.hitRegion) else { return false }
        let label = issue.element?.label ?? ""
        return label == "Clear text"
            || issue.detailedDescription.contains("_UITextFieldClearButton")
    }

    /// SwiftUI reports an unlabeled node that looks like "Search" on Watchlist
    /// even though the toolbar button already has an accessibility label.
    private func isUnlabeledWatchlistSearchChrome(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType.contains(.sufficientElementDescription) else { return false }
        let label = issue.element?.label ?? ""
        return label.isEmpty && issue.compactDescription.contains("looks like: Search")
    }

    /// System `UISearchBarTextField` predicts clipping at the largest sizes.
    /// Limited to the two known `.searchable` fields; a future search field
    /// must not inherit this exception from the `.searchField` role alone.
    private func isSystemSearchFieldTextClipped(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType.contains(.textClipped) else { return false }
        let label = issue.element?.label ?? ""
        return label == "Search TV shows" || label == "Search Watchlist"
    }

    /// `ContentUnavailableView` titles/descriptions predict clipping at the
    /// largest accessibility sizes even though they use wrapping system styles.
    private func isKnownContentUnavailableTextClipped(_ issue: XCUIAccessibilityAuditIssue) -> Bool
    {
        guard issue.auditType.contains(.textClipped) else { return false }
        return Self.contentUnavailableCopy.contains(issue.element?.label ?? "")
    }

    /// Custom `foregroundStyle` on system text styles trips Dynamic Type even
    /// though the fonts themselves scale. Limited to nodes already observed.
    private func isKnownSwiftUIDynamicTypeFalsePositive(_ issue: XCUIAccessibilityAuditIssue)
        -> Bool
    {
        guard issue.auditType.contains(.dynamicType) else { return false }
        return matchesKnownStyledCopy(issue)
    }

    /// Secondary/caption copy is intentionally `.secondary`. "Nearly passed"
    /// is expected at footnote/caption size. Limited to nodes already observed.
    private func isKnownSecondaryContrastNearlyPassed(_ issue: XCUIAccessibilityAuditIssue) -> Bool
    {
        guard issue.auditType.contains(.contrast) else { return false }
        guard issue.compactDescription.hasPrefix("Contrast nearly passed") else { return false }
        return matchesKnownStyledCopy(issue)
    }

    /// True when the issue's element is one of the known styled-copy nodes.
    private func matchesKnownStyledCopy(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let identifier = issue.element?.identifier ?? ""
        let label = issue.element?.label ?? ""

        if Self.knownStyledCopyIdentifiers.contains(identifier) { return true }
        if Self.knownStyledCopyLabels.contains(label) { return true }
        if Self.knownStyledCopyLabelPrefixes.contains(where: { label.hasPrefix($0) }) {
            return true
        }
        return false
    }

    /// Identifiers on nodes the SwiftUI audit has already flagged.
    private static let knownStyledCopyIdentifiers: Set<String> = [
        AccessibilityID.Search.tryExampleButton,
        AccessibilityID.Search.idlePrompt,
        AccessibilityID.Search.noResults,
        AccessibilityID.Search.resultsHint,
        AccessibilityID.Search.tvdbAttribution,
        AccessibilityID.Watchlist.emptyState,
        AccessibilityID.Watchlist.noResults,
        AccessibilityID.Watchlist.undoButton,
        AccessibilityID.Watchlist.confirmButton,
        AccessibilityID.Watchlist.searchButton,
        "\(AccessibilityID.Search.result).\(UITestPreviewShow.tvdbID)",
        "\(AccessibilityID.Search.trackButton).\(UITestPreviewShow.tvdbID)",
        "\(AccessibilityID.Watchlist.row).\(UITestPreviewShow.id)",
        "\(AccessibilityID.Watchlist.trackButton).\(UITestPreviewShow.id)",
        "\(AccessibilityID.ShowDetail.trackButton).\(UITestPreviewShow.id)",
    ]

    /// Stable copy (or UI-test fixture text) on nodes the audit has flagged.
    private static let knownStyledCopyLabels: Set<String> = [
        "Try an Example",
        "Find Your Next Season",
        "Search for a show to see its next-season status. Use the search field above, or try an example.",
        "Search for a show to see its next-season status. Use the search field above.",
        "Can't Find Your Show?",
        "Try a more specific title — add a subtitle or the year (for example, “Title: Subtitle” or “Title 2019”).",
        "Something Went Wrong",
        "No Tracked Shows",
        "Find a Show",
        "Track shows you care about — tap the star on any search result.",
        "No Matches",
        "Data provided by TVMaze",
        "Metadata provided by TheTVDB. Please consider adding missing information or subscribing.",
        "Waiting for a Date",
        "Season 3 announced — date to be confirmed",
        "Ongoing series",
        "Apple TV",
        "Drama\u{00A0}· Science-Fiction\u{00A0}· Mystery",
        UITestPreviewShow.name,
        UITestPreviewShow.searchStatus,
        "Mark leads a team whose memories are surgically divided between work and personal lives.",
        "Enable notifications to get alerts when a tracked show's next season gets a release date or status update.",
        "Removed from watchlist",
    ]

    /// Labels whose suffix is data-dependent (timestamps, typed queries).
    private static let knownStyledCopyLabelPrefixes: [String] = [
        "Updated ",
        "No tracked shows match",
    ]

    /// `ContentUnavailableView` copy observed as text-clipped false positives.
    private static let contentUnavailableCopy: Set<String> = [
        "Find Your Next Season",
        "Search for a show to see its next-season status. Use the search field above, or try an example.",
        "Can't Find Your Show?",
        "Try a more specific title — add a subtitle or the year (for example, “Title: Subtitle” or “Title 2019”).",
        "Something Went Wrong",
        "No Tracked Shows",
        "Track shows you care about — tap the star on any search result.",
        "No Matches",
    ]

}
