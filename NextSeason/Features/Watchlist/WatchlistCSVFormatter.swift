//
//  WatchlistCSVFormatter.swift
//  NextSeason
//

import Foundation

/// Builds a spreadsheet-friendly CSV from the on-device watchlist.
///
/// Column headers stay English and stable so a later import can match them.
/// Human-readable status text uses the same localized copy the app shows.
nonisolated enum WatchlistCSVFormatter {
    /// English column headers in export order. Kept stable (not localized) so a
    /// future import can match columns reliably across app versions.
    static let headerColumns = [
        "Show Name",
        "TVMaze ID",
        "TVDB ID",
        "Status",
        "Next Season",
        "Next Season Premiere",
        "Date Added",
        "TVMaze URL",
    ]

    /// RFC 4180 CSV (CRLF), without a UTF-8 BOM. The file writer adds the BOM
    /// so Excel on Windows still opens the sheet as UTF-8.
    ///
    /// `dateStyle` formats the premiere inside the descriptive Next Season text;
    /// tests inject a fixed locale and time zone.
    static func csv(
        shows: [TrackedShow],
        tvdbIDsByTVMazeID: [Int: Int],
        dateStyle: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
    ) -> String {
        let rows =
            shows
            .sorted(by: Self.isOrderedBefore)
            .map { row(for: $0, tvdbID: tvdbIDsByTVMazeID[$0.id], dateStyle: dateStyle) }
        let lines = [headerColumns.map(escape).joined(separator: ",")] + rows
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func isOrderedBefore(_ lhs: TrackedShow, _ rhs: TrackedShow) -> Bool {
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private static func row(
        for show: TrackedShow,
        tvdbID: Int?,
        dateStyle: Date.FormatStyle
    ) -> String {
        let fields = [
            escape(sanitizeForSpreadsheet(show.name)),
            escape(String(show.id)),
            escape(tvdbID.map(String.init) ?? ""),
            escape(show.status.displayLabel),
            escape(show.nextSeason.headline(dateStyle: dateStyle)),
            escape(premiereDateString(show.nextSeason)),
            escape(dateAddedString(show.dateAdded)),
            escape(show.tvMazeURL?.absoluteString ?? ""),
        ]
        return fields.joined(separator: ",")
    }

    /// Prefixes formula-leading values so spreadsheet apps treat them as text.
    ///
    /// Excel and Numbers still execute `=`, `+`, `-`, and `@` after CSV quoting.
    private static func sanitizeForSpreadsheet(_ field: String) -> String {
        guard let first = field.first, Self.formulaPrefixes.contains(first) else {
            return field
        }
        return "'" + field
    }

    /// TVMaze premiere dates are UTC calendar days; keep that day in the CSV.
    private static func premiereDateString(_ status: NextSeasonStatus) -> String {
        guard case .scheduled(_, let premiere) = status else { return "" }
        return premiere.formatted(
            Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        )
    }

    /// Full ISO-8601 timestamp in UTC. Unlike premiere dates (calendar days only),
    /// `dateAdded` is a wall-clock instant and needs time-of-day for sorting.
    private static func dateAddedString(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }

    private static let formulaPrefixes: Set<Character> = ["=", "+", "-", "@"]

    /// Quotes a field when it contains a comma, quote, or line break.
    private static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
