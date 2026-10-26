//
//  PurchaseConfirmation.swift
//  NextSeason
//

import StoreKit
// `PurchaseAction` comes from StoreKit's SwiftUI integration.
import SwiftUI

/// The SwiftUI purchase action of the view that started a purchase.
///
/// Apple recommends `PurchaseAction` for SwiftUI apps: it shows StoreKit's
/// confirmation sheet over the scene that view is in. `Product.purchase()`
/// leaves StoreKit to choose a scene and is documented for watchOS.
/// Wrapped so `PurchaseService` can pass it through without depending on StoreKit.
struct PurchaseConfirmation {
    let action: PurchaseAction

    /// Keeps the SwiftUI dependency here rather than in the StoreKit client.
    @MainActor
    func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        try await action(product)
    }
}
