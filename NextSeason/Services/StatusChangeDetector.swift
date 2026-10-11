//
//  StatusChangeDetector.swift
//  NextSeason
//

import Foundation

/// Decides whether a next-season delta is worth notifying about and applies
/// PD-008 debounce rules before alerting.
nonisolated enum StatusChangeDetector {
    struct Evaluation: Sendable {
        var tracked: TrackedShow
        var notification: SeasonNotificationContent?
    }

    /// A stable string representing the current next-season state for dedup.
    static func signature(for status: NextSeasonStatus) -> String {
        switch status {
        case .airing(let season):
            "airing:\(season)"
        case .scheduled(let season, let premiere):
            "scheduled:\(season):\(premiere.timeIntervalSince1970)"
        case .announcedUndated(let season):
            "announcedUndated:\(season)"
        case .returningNoSeasonYet:
            "returningNoSeasonYet"
        case .ended:
            "ended"
        case .unknown:
            "unknown"
        }
    }

    /// Meaningful deltas from `TVMazeResearch.md` §5.
    static func isMeaningfulChange(from old: NextSeasonStatus, to new: NextSeasonStatus) -> Bool {
        guard old != new else { return false }

        switch (old, new) {
        case (.announcedUndated, .scheduled):
            return true
        case (.scheduled, .scheduled):
            return true
        case (_, .airing):
            return true
        case (_, .ended):
            return true
        case (.returningNoSeasonYet, .announcedUndated),
            (.returningNoSeasonYet, .scheduled):
            return true
        default:
            return false
        }
    }

    /// Changes backed by a concrete premiere or on-air evidence can notify immediately.
    static func isDateBacked(_ status: NextSeasonStatus) -> Bool {
        switch status {
        case .scheduled, .airing:
            return true
        default:
            return false
        }
    }

    /// Records `newStatus` as an already-announced baseline, with no notification.
    ///
    /// Used for shows resumed after a Plus lapse: whatever changed while they were
    /// paused is history, so the current state becomes the last-notified signature
    /// and any pending soft-change debounce is cleared. Later changes away from
    /// this baseline notify normally.
    static func baseline(tracked: TrackedShow, newStatus: NextSeasonStatus, at: Date = .now)
        -> TrackedShow
    {
        var updated = tracked
        updated.lastCheckedAt = at
        updated.nextSeason = newStatus
        updated.lastNotifiedSignature = signature(for: newStatus)
        updated.pendingChangeSignature = nil
        return updated
    }

    /// Updates local next-season state and decides whether to notify (PD-008).
    ///
    /// Always returns a tracked show with `lastCheckedAt` and `nextSeason` applied.
    /// A notification is included only when the delta is meaningful, not a duplicate
    /// of `lastNotifiedSignature`, and either date-backed (notify immediately) or
    /// confirmed across two consecutive polls (debounce soft changes).
    static func evaluate(tracked: TrackedShow, newStatus: NextSeasonStatus, at: Date = .now)
        -> Evaluation
    {
        let previousStatus = tracked.nextSeason
        var updated = tracked
        updated.lastCheckedAt = at
        updated.nextSeason = newStatus

        let changeSignature = signature(for: newStatus)

        // Debounce confirmed: a prior poll stashed this soft change as pending, and
        // this poll sees the same signature again — notify and clear pending.
        if tracked.pendingChangeSignature == changeSignature,
            changeSignature != tracked.lastNotifiedSignature
        {
            updated.lastNotifiedSignature = changeSignature
            updated.pendingChangeSignature = nil
            return Evaluation(
                tracked: updated,
                notification: SeasonNotificationContent(
                    showID: tracked.id, showName: tracked.name, status: newStatus)
            )
        }

        // Not a meaningful delta (or no change) — keep the UI current, no alert.
        guard isMeaningfulChange(from: previousStatus, to: newStatus) else {
            updated.pendingChangeSignature = nil
            return Evaluation(tracked: updated, notification: nil)
        }

        // Already notified for this exact next-season state — do not re-alert.
        if changeSignature == tracked.lastNotifiedSignature {
            updated.pendingChangeSignature = nil
            return Evaluation(tracked: updated, notification: nil)
        }

        // Date-backed (scheduled / airing): concrete enough to notify on first sight.
        if isDateBacked(newStatus) {
            updated.lastNotifiedSignature = changeSignature
            updated.pendingChangeSignature = nil
            return Evaluation(
                tracked: updated,
                notification: SeasonNotificationContent(
                    showID: tracked.id, showName: tracked.name, status: newStatus)
            )
        }

        // Soft meaningful change: wait for a second consecutive poll before notifying.
        updated.pendingChangeSignature = changeSignature
        return Evaluation(tracked: updated, notification: nil)
    }
}

nonisolated struct SeasonNotificationContent: Sendable {
    let showID: Int
    let showName: String
    let status: NextSeasonStatus

    /// The show name leads the notification so it's clear which show updated.
    var title: String { showName }

    var body: String {
        switch status {
        case .airing(let season):
            return String(localized: "Season \(season) is now airing.")
        case .scheduled(let season, let premiere):
            let date = premiere.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "Season \(season) premieres \(date).")
        case .announcedUndated(let season):
            return String(localized: "Season \(season) announced — date to be confirmed.")
        case .returningNoSeasonYet:
            return String(localized: "Returning — watch for next season news.")
        case .ended:
            return String(localized: "This series has ended.")
        case .unknown:
            return String(localized: "There's a next season update.")
        }
    }
}
