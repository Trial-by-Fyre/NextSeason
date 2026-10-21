//
//  ExternalLinksTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Verifies the About screen's support, legal, and credit destinations.
struct ExternalLinksTests {
    @Test("Support opens the NextSeason website's support page")
    func supportURLUsesWebsiteSupportPage() {
        let url = ExternalLinks.support
        #expect(url.scheme == "https")
        #expect(url.host == "getnextseason.com")
        #expect(url.path == "/support.html")
    }

    @Test("Credits link back to TVMaze and TheTVDB")
    func creditURLsUseProviderWebsites() {
        #expect(ExternalLinks.tvMaze.scheme == "https")
        #expect(ExternalLinks.tvMaze.host == "www.tvmaze.com")
        #expect(TheTVDBConfiguration.websiteURL.scheme == "https")
        #expect(TheTVDBConfiguration.websiteURL.host == "www.thetvdb.com")
    }

    @Test("About and the paywall share published legal links")
    func legalLinksAreAvailable() throws {
        let privacy = try #require(StoreLegalLinks.privacyPolicy)
        let terms = try #require(StoreLegalLinks.termsOfUse)
        #expect(privacy.scheme == "https")
        #expect(privacy.host == "getnextseason.com")
        #expect(terms.scheme == "https")
    }
}
