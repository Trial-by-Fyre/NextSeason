//
//  FreeTierSimulationSection.swift
//  NextSeason
//

import SwiftUI

/// Uses the service's guarded setter so UI visibility is not the security boundary.
struct FreeTierSimulationSection: View {
    @Environment(PurchaseService.self) private var purchases

    // The binding routes writes through the guard and reads effective state directly,
    // including automatic purchase completion, without a second UI-owned state.
    private var simulationBinding: Binding<Bool> {
        Binding(
            get: { purchases.isSimulatingFreeTier },
            set: { purchases.setFreeTierSimulation($0) }
        )
    }

    var body: some View {
        if purchases.canSimulateFreeTier {
            Section {
                Toggle("Simulate Free Tier", isOn: simulationBinding)
                    .accessibilityHint(
                        "Enforces the normal watchlist limit without changing saved shows or actual entitlements."
                    )
                if purchases.isSimulatingFreeTier {
                    Label("Free tier simulation is active", systemImage: "testtube.2")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Subscription Testing")
            } footer: {
                Text(
                    "Enforces the normal limit of \(WatchlistLimitPolicy.freeShowLimit) shows. Existing shows and actual entitlements are preserved. Turn off to restore access. Simulation ends after a verified subscription purchase started during this simulation confirms active access, or when the app restarts. Renewals do not end simulation."
                )
            }
        }
    }
}

#if DEBUG
    #Preview {
        List {
            FreeTierSimulationSection()
        }
        .environment(PurchaseService.preview)
    }
#endif
