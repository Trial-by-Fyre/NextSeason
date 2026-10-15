//
//  ShowDataDecodingTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

struct ShowDataDecodingTests {
    @Test("A /search/shows entry decodes and maps to a domain Show")
    func decodesSearchResult() throws {
        let json = """
            [
              {
                "score": 0.9,
                "show": {
                  "id": 44933,
                  "name": "Severance",
                  "url": "https://www.tvmaze.com/shows/44933/severance",
                  "status": "Running",
                  "premiered": "2022-02-18",
                  "ended": null,
                  "averageRuntime": 49,
                  "genres": ["Drama", "Science-Fiction", "Mystery"],
                  "summary": "<p>Mark leads a team.</p>",
                  "network": { "id": 1, "name": "Apple TV" },
                  "image": {
                    "medium": "https://example.com/m.jpg",
                    "original": "https://example.com/o.jpg"
                  },
                  "updated": 1700000000
                }
              }
            ]
            """

        let results = try JSONDecoder().decode([ShowSearchResultData].self, from: Data(json.utf8))
        let show = try #require(results.first).show.toDomain()

        #expect(show.id == 44933)
        #expect(show.name == "Severance")
        #expect(show.tvMazeURL == URL(string: "https://www.tvmaze.com/shows/44933/severance"))
        #expect(show.status == .running)
        #expect(show.network == "Apple TV")
        #expect(show.genres == ["Drama", "Science-Fiction", "Mystery"])
        #expect(show.premiered == TVMazeDate.dateOnly("2022-02-18"))
        #expect(show.summaryHTML == "<p>Mark leads a team.</p>")
        #expect(show.posterMediumURL == URL(string: "https://example.com/m.jpg"))
    }

    @Test("A show with embedded seasons + next episode decodes and derives status")
    func decodesShowWithEmbeds() throws {
        let json = """
            {
              "id": 44933,
              "name": "Severance",
              "status": "Running",
              "premiered": "2022-02-18",
              "ended": null,
              "genres": ["Drama"],
              "summary": "<p>Test.</p>",
              "updated": 1700000000,
              "_embedded": {
                "seasons": [
                  { "id": 1, "number": 1, "premiereDate": "2022-02-18", "endDate": "2022-04-08", "episodeOrder": 9 },
                  { "id": 2, "number": 2, "premiereDate": "2025-01-17", "endDate": "2025-03-21", "episodeOrder": 10 },
                  { "id": 3, "number": 3, "premiereDate": null, "endDate": null, "episodeOrder": null }
                ],
                "nextepisode": {
                  "id": 99,
                  "season": 3,
                  "number": 1,
                  "name": "TBA",
                  "airdate": "2026-09-01",
                  "airstamp": "2026-09-01T00:00:00+00:00"
                }
              }
            }
            """

        let show = try JSONDecoder().decode(ShowData.self, from: Data(json.utf8)).toDomain()

        #expect(show.seasons.count == 3)
        #expect(show.seasons[2].premiereDate == nil)
        #expect(show.nextEpisode?.season == 3)
        #expect(show.nextEpisode?.number == 1)

        let now = try #require(TVMazeDate.dateOnly("2026-06-14"))
        let expected = NextSeasonStatus.scheduled(
            season: 3, premiere: try #require(TVMazeDate.dateOnly("2026-09-01")))
        #expect(NextSeasonCalculator.status(for: show, at: now) == expected)
    }
}
