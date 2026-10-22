//
//  IgnoreComplimentaryPlusSection.swift
//  NextSeason
//

import SwiftUI

/// Developer/TestFlight switch that hides complimentary Plus so real StoreKit
/// subscriptions alone decide access. The raw StoreKit and stored-grant rows stay
/// visible regardless of the switch, so after a relaunch (which turns it off) a
/// tester can tell a restored subscription apart from complimentary access.
struct IgnoreComplimentaryPlusSection: View {
    @Environment(PurchaseService.self) private var purchases

    // Writes go through the guarded setter; reads show the effective state.
    private var ignoreBinding: Binding<Bool> {
        Binding(
            get: { purchases.isIgnoringComplimentaryPlus },
            set: { purchases.setIgnoreComplimentaryPlus($0) }
        )
    }

    var body: some View {
        if purchases.canIgnoreComplimentaryPlus {
            Section {
                Toggle("Ignore Complimentary Plus", isOn: ignoreBinding)
                    .accessibilityHint(
                        "Uses only StoreKit subscriptions for access without changing the stored complimentary grant."
                    )
                if purchases.isIgnoringComplimentaryPlus {
                    Label("Complimentary Plus is ignored", systemImage: "testtube.2")
                        .foregroundStyle(.orange)
                }
                LabeledContent("StoreKit Plus", value: storeKitStatus)
                if let expiration = purchases.lastCommittedExpirationDate {
                    LabeledContent("Expires or renews") {
                        Text(expiration, format: .dateTime)
                    }
                }
                if let checked = purchases.lastCommittedCheckDate {
                    LabeledContent("Last checked") {
                        Text(checked, format: .dateTime.hour().minute().second())
                    }
                }
                LabeledContent(
                    "Complimentary grant",
                    value: purchases.hasStoredComplimentaryPlus
                        ? String(localized: "Stored") : String(localized: "Not stored")
                )
            } footer: {
                Text(
                    "StoreKit Plus shows the last StoreKit read only, never complimentary access. The switch never changes the stored grant and turns off when the app restarts. Simulate Free Tier still applies the free limit while both are on."
                )
            }
        }
    }

    /// The raw last committed read, not the retained `storeEntitlement`, so an
    /// unverified read after an earlier confirmed one is still visible.
    private var storeKitStatus: String {
        switch purchases.lastCommittedCheck {
        case .active: String(localized: "Active")
        case .inactive: String(localized: "Not active")
        case .unverified: String(localized: "Unable to verify")
        case nil: String(localized: "Checking…")
        }
    }
}

#if DEBUG
    #Preview {
        List {
            IgnoreComplimentaryPlusSection()
        }
        .environment(PurchaseService.preview)
    }
#endif
