//
//  DiagnosticsSimulations.swift
//  NextSeason
//

import Foundation

/// Owns the Diagnostics simulation runners between button taps.
///
/// The two-step scenario only advances when every tap reaches the same runner, so a
/// runner is kept until the watchlist show it copies changes. The runner itself
/// starts over after a completed step 2. The delayed pipeline has its own runner,
/// so running it never resets a two-step scenario that is in progress.
@MainActor
final class DiagnosticsSimulations {
    typealias MakeRunner = @MainActor (TrackedShow) -> DiagnosticsSimulatedUpdateRunner

    private let makeRunner: MakeRunner
    private var stepRunner: DiagnosticsSimulatedUpdateRunner?
    private var delayedRunner: DiagnosticsSimulatedUpdateRunner?

    init(makeRunner: @escaping MakeRunner) {
        self.makeRunner = makeRunner
    }

    /// Runs the next step of the two-step baseline → updated scenario.
    @discardableResult
    func runNextStep(using template: TrackedShow) async -> String {
        let runner = runner(reusing: stepRunner, for: template)
        stepRunner = runner
        return await runner.runNextStep()
    }

    /// Runs the one-shot delayed refresh → notification pipeline.
    @discardableResult
    func runDelayedNewSeasonNotification(using template: TrackedShow) async -> String {
        let runner = runner(reusing: delayedRunner, for: template)
        delayedRunner = runner
        return await runner.runDelayedNewSeasonNotification()
    }

    /// Matches on show ID only: a refresh of the real watchlist row changes its
    /// other fields, which must not restart a scenario in progress.
    private func runner(
        reusing existing: DiagnosticsSimulatedUpdateRunner?,
        for template: TrackedShow
    ) -> DiagnosticsSimulatedUpdateRunner {
        if let existing, existing.showID == template.id {
            return existing
        }
        return makeRunner(template)
    }
}
