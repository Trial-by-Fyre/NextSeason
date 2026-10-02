//
//  TipJarSection.swift
//  NextSeason
//

import SwiftUI

/// Optional consumable tips. Shown to free and Plus users; never unlocks features.
///
/// Purchase buttons are created only from products StoreKit actually loaded.
struct TipJarSection: View {
    @Environment(PurchaseService.self) private var purchases

    var body: some View {
        Section {
            switch purchases.tipCatalogAvailability {
            case .available:
                ForEach(purchases.tipProducts) { product in
                    Button {
                        Task { _ = await purchases.purchase(product) }
                    } label: {
                        LabeledContent {
                            Text(product.displayPrice)
                        } label: {
                            Text(product.displayName)
                        }
                    }
                    .accessibilityIdentifier(tipIdentifier(for: product.productID))
                    .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
                    .disabled(purchases.isPurchasing)
                }
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading tip options")
            case .unavailable:
                Text("NextSeason couldn't load tip options right now.")
                    .appSecondaryText()
                Button("Try Again") {
                    Task { await purchases.loadProducts() }
                }
                .disabled(purchases.isLoadingProducts || purchases.isPurchasing)
            }
        } header: {
            Text("Support NextSeason")
        } footer: {
            Text(
                "Tips are optional and do not unlock features. Thank you for supporting NextSeason."
            )
        }
        .task {
            if purchases.tipProducts.isEmpty {
                await purchases.loadProducts()
            }
        }
    }

    /// Maps known tip product IDs to stable accessibility identifiers for UI tests.
    private func tipIdentifier(for productID: String) -> String {
        switch StoreProductID(rawValue: productID) {
        case .tipTrailer: AccessibilityID.Store.tipTrailer
        case .tipPilot: AccessibilityID.Store.tipPilot
        case .tipHitShow: AccessibilityID.Store.tipHitShow
        default: productID
        }
    }
}
