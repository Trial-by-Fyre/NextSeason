//
//  StoreProductID.swift
//  NextSeason
//

import Foundation

/// App Store product identifiers for NextSeason Plus and optional tips.
///
/// These IDs must match App Store Connect (and the local `.storekit` file)
/// exactly. Prices are loaded from StoreKit at runtime.
nonisolated enum StoreProductID: String, CaseIterable, Sendable {
    case plusAnnual = "com.trialbyfyre.nextseason.plus.annual"
    case plusMonthly = "com.trialbyfyre.nextseason.plus.monthly"
    case tipTrailer = "com.trialbyfyre.nextseason.tip.trailer"
    case tipPilot = "com.trialbyfyre.nextseason.tip.pilot"
    case tipHitShow = "com.trialbyfyre.nextseason.tip.hitshow"

    /// Stable ordering for `Product.products(for:)`.
    static var allIDs: [String] { allCases.map(\.rawValue) }

    var kind: StoreProductKind {
        switch self {
        case .plusAnnual: .plusAnnual
        case .plusMonthly: .plusMonthly
        case .tipTrailer, .tipPilot, .tipHitShow: .tip
        }
    }

    /// Name used by previews, tests, and stubs. Production UI uses StoreKit.
    var fallbackDisplayName: String {
        switch self {
        case .plusAnnual:
            String(localized: "NextSeason Plus Annual")
        case .plusMonthly:
            String(localized: "NextSeason Plus Monthly")
        case .tipTrailer:
            String(localized: "Trailer")
        case .tipPilot:
            String(localized: "Pilot")
        case .tipHitShow:
            String(localized: "Hit Show")
        }
    }

    /// US prices for previews and stubs only — never shown as live prices.
    var fallbackPriceText: String {
        switch self {
        case .plusAnnual: "$9.99"
        case .plusMonthly: "$1.99"
        case .tipTrailer: "$0.99"
        case .tipPilot: "$2.99"
        case .tipHitShow: "$4.99"
        }
    }

    /// Description used by previews, tests, and stubs. Production UI uses StoreKit.
    var fallbackDescription: String {
        switch self {
        case .plusAnnual:
            String(localized: "Unlimited watchlist for one year, renews annually.")
        case .plusMonthly:
            String(localized: "Unlimited watchlist for one month, renews monthly.")
        case .tipTrailer, .tipPilot, .tipHitShow:
            String(localized: "Optional support for NextSeason. Does not unlock features.")
        }
    }
}

/// Product category for partitioning loaded StoreKit products and entitlements.
nonisolated enum StoreProductKind: Equatable, Sendable {
    case plusAnnual
    case plusMonthly
    case tip
}

/// Product presentation values that views can display without importing StoreKit.
nonisolated struct StoreProduct: Identifiable, Equatable, Sendable {
    var id: String { productID }
    let productID: String
    let displayName: String
    let description: String
    let displayPrice: String
    let kind: StoreProductKind

    init(
        productID: String,
        displayName: String,
        description: String,
        displayPrice: String,
        kind: StoreProductKind
    ) {
        self.productID = productID
        self.displayName = displayName
        self.description = description
        self.displayPrice = displayPrice
        self.kind = kind
    }

    /// Preview and test catalog. Production purchase UI uses StoreKit-loaded products.
    init(_ id: StoreProductID) {
        self.init(
            productID: id.rawValue,
            displayName: id.fallbackDisplayName,
            description: id.fallbackDescription,
            displayPrice: id.fallbackPriceText,
            kind: id.kind
        )
    }
}

/// Privacy Policy and Terms of Use URLs shown near subscription purchase.
///
/// Apple's standard EULA is used until NextSeason publishes its own terms.
/// Privacy Policy is omitted until a public URL exists (required before App Review).
nonisolated enum StoreLegalLinks {
    static let termsOfUse = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )

    static let privacyPolicy: URL? = URL(string: "https://getnextseason.com/privacy.html")
}
