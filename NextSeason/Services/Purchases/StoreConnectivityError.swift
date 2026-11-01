//
//  StoreConnectivityError.swift
//  NextSeason
//

import Foundation
import StoreKit

/// Identifies StoreKit failures caused by missing or lost connectivity, so
/// Restore Purchases can suggest reconnecting instead of a generic retry.
///
/// Apple documents network failures as `StoreKitError.networkError(URLError)`
/// and, for StoreKit's Objective-C errors, `NSURLErrorDomain` codes
/// (https://developer.apple.com/documentation/storekit/handling-errors).
/// Anything else stays unclassified: not every StoreKit failure is a network outage.
nonisolated enum StoreConnectivityError {
    /// URL error codes that mean the App Store could not be reached.
    private static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .dataNotAllowed, .internationalRoamingOff,
    ]

    static func isConnectivityFailure(_ error: any Error) -> Bool {
        if case .networkError = error as? StoreKitError { return true }
        // Also matches bridged `NSURLErrorDomain` NSErrors.
        if let urlError = error as? URLError {
            return connectivityCodes.contains(urlError.code)
        }
        // StoreKit and system frameworks can wrap the URL error they received.
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
            return isConnectivityFailure(underlying)
        }
        return false
    }
}
