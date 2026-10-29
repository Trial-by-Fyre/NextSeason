//
//  ShowDetailBroadcastHeadlineTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

/// Show detail names the original broadcaster and its country, since TVMaze
/// schedules reflect the original broadcast rather than local availability.
struct ShowDetailBroadcastHeadlineTests {
    // MARK: - Wording

    @Test("Airing names the broadcaster and country")
    func airingWithCountry() {
        let headline = NextSeasonStatus.airing(season: 20)
            .detailHeadline(broadcaster: "CBC Gem", country: "Canada")

        #expect(headline == "Season 20 airing on CBC Gem (Canada)")
    }

    @Test(
        "Airing omits the parenthetical when the country is missing or blank",
        arguments: [nil, "", " "])
    func airingWithoutCountry(_ country: String?) {
        let headline = NextSeasonStatus.airing(season: 3)
            .detailHeadline(broadcaster: "Netflix", country: country)

        #expect(headline == "Season 3 airing on Netflix")
    }

    @Test("Airing falls back to a generic status without a broadcaster", arguments: [nil, ""])
    func airingWithoutBroadcaster(_ broadcaster: String?) {
        let headline = NextSeasonStatus.airing(season: 20)
            .detailHeadline(broadcaster: broadcaster, country: "Canada")

        #expect(headline == "Season 20 currently airing")
    }

    @Test("Scheduled names the broadcaster and country after the premiere date")
    func scheduledWithBroadcaster() throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let headline = NextSeasonStatus.scheduled(season: 21, premiere: premiere)
            .detailHeadline(broadcaster: "CBC", country: "Canada", dateStyle: try dateStyle())

        #expect(headline == "Season 21 premieres Jan 1, 2027 on CBC (Canada)")
    }

    @Test("Scheduled without a broadcaster keeps the shared headline")
    func scheduledWithoutBroadcaster() throws {
        let premiere = try #require(TVMazeDate.dateOnly("2027-01-01"))
        let style = try dateStyle()
        let status = NextSeasonStatus.scheduled(season: 21, premiere: premiere)

        #expect(
            status.detailHeadline(broadcaster: nil, country: "Canada", dateStyle: style)
                == "Season 21 premieres Jan 1, 2027")
    }

    @Test(
        "Statuses not tied to a broadcaster keep the shared headline",
        arguments: [
            NextSeasonStatus.announcedUndated(season: 4), .returningNoSeasonYet, .ended, .unknown,
        ]
    )
    func otherStatusesUnchanged(_ status: NextSeasonStatus) {
        #expect(status.detailHeadline(broadcaster: "CBC", country: "Canada") == status.headline)
    }

    @Test("The shared headline used by CSV export is unchanged")
    func sharedHeadlineUnchanged() {
        #expect(NextSeasonStatus.airing(season: 20).headline == "Currently showing Season 20")
    }

    // MARK: - Mapping

    @Test("Country comes from the network that supplies the name")
    func networkCountryMapping() throws {
        let show = try decodeShow(
            network: #"{ "id": 1, "name": "CBC", "country": { "name": "Canada", "code": "CA" } }"#,
            webChannel:
                #"{ "id": 2, "name": "CBC Gem", "country": { "name": "Canada", "code": "CA" } }"#
        )

        #expect(show.network == "CBC")
        #expect(show.networkCountry == "Canada")
    }

    @Test("A webChannel-only show uses the web channel's country, which may be null")
    func webChannelCountryMapping() throws {
        let gem = try decodeShow(
            network: "null",
            webChannel:
                #"{ "id": 2, "name": "CBC Gem", "country": { "name": "Canada", "code": "CA" } }"#
        )
        let netflix = try decodeShow(
            network: "null",
            webChannel: #"{ "id": 1, "name": "Netflix", "country": null }"#
        )

        #expect(gem.network == "CBC Gem")
        #expect(gem.networkCountry == "Canada")
        #expect(netflix.network == "Netflix")
        #expect(netflix.networkCountry == nil)
    }

    @Test("A missing broadcaster maps to no name and no country")
    func missingBroadcasterMapping() throws {
        let show = try decodeShow(network: "null", webChannel: "null")

        #expect(show.network == nil)
        #expect(show.networkCountry == nil)
    }

    // MARK: - Helpers

    private func decodeShow(network: String, webChannel: String) throws -> Show {
        let json = """
            {
              "id": 1,
              "name": "Murdoch Mysteries",
              "status": "Running",
              "genres": [],
              "network": \(network),
              "webChannel": \(webChannel)
            }
            """
        return try JSONDecoder().decode(ShowData.self, from: Data(json.utf8)).toDomain()
    }

    /// Fixed locale and time zone so the premiere date formats predictably.
    private func dateStyle() throws -> Date.FormatStyle {
        Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))
        )
    }
}
