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
    case plusAnnual = "com.TrialByFyre.NextSeason.plus.annual"
    case plusLifetime = "com.TrialByFyre.NextSeason.plus.lifetime"
    case tipTrailer = "com.TrialByFyre.NextSeason.tip.small"
    case tipPilot = "com.TrialByFyre.NextSeason.tip.medium"
    case tipHitShow = "com.TrialByFyre.NextSeason.tip.large"

    /// Stable ordering for `Product.products(for:)`.
    static var allIDs: [String] { allCases.map(\.rawValue) }

    var kind: StoreProductKind {
        switch self {
        case .plusAnnual: .plusAnnual
        case .plusLifetime: .plusLifetime
        case .tipTrailer, .tipPilot, .tipHitShow: .tip
        }
    }

    /// Name used by previews, tests, and stubs. Production UI uses StoreKit.
    var fallbackDisplayName: String {
        switch self {
        case .plusAnnual:
            String(localized: "NextSeason Plus Annual")
        case .plusLifetime:
            String(localized: "NextSeason Plus Lifetime")
        case .tipTrailer:
            String(localized: "Trailer")
        case .tipPilot:
            String(localized: "Pilot")
        case .tipHitShow:
            String(localized: "Hit Show")
        }
    }

    /// Provisional US prices for previews and stubs only — never shown as live prices.
    var fallbackPriceText: String {
        switch self {
        case .plusAnnual: "$10.00"
        case .plusLifetime: "$20.00"
        case .tipTrailer: "$1.00"
        case .tipPilot: "$3.00"
        case .tipHitShow: "$5.00"
        }
    }

    /// Description used by previews, tests, and stubs. Production UI uses StoreKit.
    var fallbackDescription: String {
        switch self {
        case .plusAnnual:
            String(localized: "Unlimited watchlist for one year, renews annually.")
        case .plusLifetime:
            String(localized: "Unlimited watchlist, one-time purchase.")
        case .tipTrailer, .tipPilot, .tipHitShow:
            String(localized: "Optional support for NextSeason. Does not unlock features.")
        }
    }
}

/// Product category for partitioning loaded StoreKit products and entitlements.
nonisolated enum StoreProductKind: Equatable, Sendable {
    case plusAnnual
    case plusLifetime
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
