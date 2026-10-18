//
//  StatusChangeDetectorTests.swift
//  NextSeasonTests
//

import Foundation
import Testing

@testable import NextSeason

struct StatusChangeDetectorTests {
    private let now = TVMazeDate.dateOnly("2026-06-14")!
    private let premiere = TVMazeDate.dateOnly("2026-09-01")!
    private let laterPremiere = TVMazeDate.dateOnly("2026-10-01")!

    private func tracked(
        nextSeason: NextSeasonStatus,
        pendingChangeSignature: String? = nil,
        lastNotifiedSignature: String? = nil
    ) -> TrackedShow {
        TrackedShow(
            id: 1,
            name: "Test Show",
            posterMediumURL: nil,
            status: .running,
            nextSeason: nextSeason,
            sourceUpdatedAt: .distantPast,
            lastCheckedAt: .distantPast,
            lastNotifiedSignature: lastNotifiedSignature,
            pendingChangeSignature: pendingChangeSignature,
            dateAdded: .distantPast
        )
    }

    @Test("A premiere date notifies immediately without waiting for a second poll")
    func dateBackedChangeNotifiesImmediately() {
        let show = tracked(nextSeason: .announcedUndated(season: 2))
        let evaluation = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .scheduled(season: 2, premiere: premiere),
            at: now
        )

        #expect(evaluation.notification != nil)
        #expect(
            evaluation.tracked.lastNotifiedSignature
                == StatusChangeDetector.signature(for: .scheduled(season: 2, premiere: premiere)))
        #expect(evaluation.tracked.pendingChangeSignature == nil)
    }

    @Test("A non-date-backed change waits for a confirming poll")
    func ambiguousChangeDebouncesUntilSecondPoll() {
        let show = tracked(nextSeason: .returningNoSeasonYet)
        let first = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .announcedUndated(season: 2),
            at: now
        )

        #expect(first.notification == nil)
        #expect(
            first.tracked.pendingChangeSignature
                == StatusChangeDetector.signature(for: .announcedUndated(season: 2)))

        let second = StatusChangeDetector.evaluate(
            tracked: first.tracked,
            newStatus: .announcedUndated(season: 2),
            at: now
        )

        #expect(second.notification != nil)
        #expect(second.tracked.pendingChangeSignature == nil)
    }

    @Test("The same transition is never notified twice")
    func duplicateTransitionIsSuppressed() {
        var show = tracked(nextSeason: .announcedUndated(season: 2))
        show.lastNotifiedSignature = StatusChangeDetector.signature(
            for: .scheduled(season: 2, premiere: premiere))

        let evaluation = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .scheduled(season: 2, premiere: premiere),
            at: now
        )

        #expect(evaluation.notification == nil)
    }

    @Test("A changed premiere date is a meaningful, immediately notifiable update")
    func scheduledDateChangeNotifiesImmediately() {
        let show = tracked(nextSeason: .scheduled(season: 2, premiere: premiere))
        let evaluation = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .scheduled(season: 2, premiere: laterPremiere),
            at: now
        )

        #expect(evaluation.notification != nil)
        #expect(
            evaluation.tracked.lastNotifiedSignature
                == StatusChangeDetector.signature(
                    for: .scheduled(season: 2, premiere: laterPremiere)))
    }

    @Test("Transition to airing notifies immediately")
    func airingTransitionNotifiesImmediately() {
        let show = tracked(nextSeason: .scheduled(season: 2, premiere: premiere))
        let evaluation = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .airing(season: 2),
            at: now
        )

        #expect(evaluation.notification != nil)
        #expect(evaluation.notification?.status == .airing(season: 2))
    }

    @Test("Transition to ended debounces until a second poll confirms it")
    func endedTransitionDebouncesUntilConfirmed() {
        let show = tracked(nextSeason: .returningNoSeasonYet)
        let first = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .ended,
            at: now
        )

        #expect(first.notification == nil)
        #expect(first.tracked.pendingChangeSignature == StatusChangeDetector.signature(for: .ended))

        let second = StatusChangeDetector.evaluate(
            tracked: first.tracked,
            newStatus: .ended,
            at: now
        )

        #expect(second.notification != nil)
        #expect(second.notification?.status == .ended)
    }

    @Test("A transient edit that reverts before confirmation clears the pending signature")
    func flappingChangeClearsPendingWithoutNotifying() {
        let show = tracked(nextSeason: .returningNoSeasonYet)
        let first = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .announcedUndated(season: 2),
            at: now
        )
        #expect(first.tracked.pendingChangeSignature != nil)

        let reverted = StatusChangeDetector.evaluate(
            tracked: first.tracked,
            newStatus: .returningNoSeasonYet,
            at: now
        )

        #expect(reverted.notification == nil)
        #expect(reverted.tracked.pendingChangeSignature == nil)
    }

    /// Review finding R09: a watchlist row saved with a later episode's date as
    /// its premiere is corrected to announced silently, and the real premiere
    /// date still notifies when it appears.
    @Test("Reverting from airing to announced when the next-episode pointer advances is silent")
    func airingToAnnouncedWhenPointerAdvancesDoesNotNotify() {
        let show = tracked(
            nextSeason: .airing(season: 2),
            lastNotifiedSignature: StatusChangeDetector.signature(for: .airing(season: 2))
        )
        let evaluation = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .announcedUndated(season: 2),
            at: now
        )
        #expect(evaluation.notification == nil)
        #expect(evaluation.tracked.nextSeason == .announcedUndated(season: 2))
    }

    @Test("A midseason next-episode date does not trigger a now-airing alert")
    func midseasonEpisodeDateDoesNotNotifyAiring() {
        let show = tracked(nextSeason: .returningNoSeasonYet)
        let evaluation = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .announcedUndated(season: 2),
            at: now
        )
        #expect(evaluation.notification == nil)
        #expect(evaluation.tracked.nextSeason == .announcedUndated(season: 2))
    }

    @Test("Correcting a wrong premiere to announced is silent; the real premiere notifies")
    func correctedPremiereIsSilentThenRealPremiereNotifies() {
        let wrong = NextSeasonStatus.scheduled(season: 2, premiere: premiere)
        let show = tracked(
            nextSeason: wrong,
            lastNotifiedSignature: StatusChangeDetector.signature(for: wrong)
        )

        let corrected = StatusChangeDetector.evaluate(
            tracked: show, newStatus: .announcedUndated(season: 2), at: now)
        #expect(corrected.notification == nil)
        #expect(corrected.tracked.nextSeason == .announcedUndated(season: 2))
        #expect(corrected.tracked.pendingChangeSignature == nil)

        let real = StatusChangeDetector.evaluate(
            tracked: corrected.tracked,
            newStatus: .scheduled(season: 2, premiere: laterPremiere),
            at: now
        )
        #expect(real.notification != nil)
    }

    @Test("Cosmetic status churn that is not a meaningful delta does not notify")
    func nonMeaningfulChangeDoesNotNotify() {
        let show = tracked(nextSeason: .unknown)
        let evaluation = StatusChangeDetector.evaluate(
            tracked: show,
            newStatus: .returningNoSeasonYet,
            at: now
        )

        #expect(evaluation.notification == nil)
        #expect(evaluation.tracked.pendingChangeSignature == nil)
    }
}
