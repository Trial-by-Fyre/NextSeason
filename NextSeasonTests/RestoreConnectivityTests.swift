//
//  RestoreConnectivityTests.swift
//  NextSeasonTests
//

import Foundation
import StoreKit
import Testing

@testable import NextSeason

/// StoreKit 8C: Restore Purchases while offline, then reconnecting and buying.
/// Restore failures get restore-specific titles and connectivity-specific wording
/// only when the error identifies a network failure, and leave no state behind
/// that blocks the first purchase after reconnecting.
@MainActor
struct RestoreConnectivityTests {
    private static let offlineMessage =
        "Couldn't restore purchases. Check your connection and try again."
    private static let genericMessage = "Couldn't restore purchases. Please try again."

    private func makeService(store: StubPurchaseStoreClient) -> PurchaseService {
        let defaults = UserDefaults(suiteName: "RestoreConnectivityTests.\(UUID().uuidString)")!
        return PurchaseService(
            store: store,
            entitlementStore: PlusEntitlementStore(
                userDefaults: defaults, persistence: MemoryComplimentaryPlusPersistence()),
            initialStoreEntitlement: .resolved(isEntitled: false)
        )
    }

    @Test(
        "Network failures are recognized, including wrapped URL errors",
        arguments: [
            StoreKitError.networkError(URLError(.notConnectedToInternet)) as any Error,
            URLError(.notConnectedToInternet),
            URLError(.networkConnectionLost),
            NSError(
                domain: "ASDErrorDomain", code: 500,
                userInfo: [
                    NSUnderlyingErrorKey: NSError(
                        domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
                ]),
        ])
    func recognizesConnectivityFailures(_ error: any Error) {
        #expect(StoreConnectivityError.isConnectivityFailure(error))
    }

    @Test(
        "Other StoreKit failures are not labeled as connectivity problems",
        arguments: [
            StoreKitError.unknown as any Error,
            StoreKitError.systemError(NSError(domain: "test", code: 1)),
            URLError(.badServerResponse),
            NSError(domain: "ASDErrorDomain", code: 500),
        ])
    func ignoresOtherFailures(_ error: any Error) {
        #expect(StoreConnectivityError.isConnectivityFailure(error) == false)
    }

    @Test("Offline restore explains the connection problem under a restore title")
    func offlineRestoreMessage() async {
        let store = StubPurchaseStoreClient()
        store.restoreError = StoreKitError.networkError(URLError(.notConnectedToInternet))
        let purchases = makeService(store: store)
        await purchases.start()

        let outcome = await purchases.restorePurchases()

        #expect(outcome == .failed(Self.offlineMessage))
        #expect(purchases.lastErrorMessage == Self.offlineMessage)
        #expect(purchases.lastErrorTitle == "Couldn't Restore Purchases")
        #expect(purchases.isPurchasing == false)
        #expect(purchases.isUnlimitedWatchlist == false)
    }

    @Test("An unidentified restore failure keeps the generic wording")
    func unknownRestoreFailureMessage() async {
        let store = StubPurchaseStoreClient()
        store.restoreError = StoreKitError.unknown
        let purchases = makeService(store: store)
        await purchases.start()

        #expect(await purchases.restorePurchases() == .failed(Self.genericMessage))
        #expect(purchases.lastErrorTitle == "Couldn't Restore Purchases")
    }

    @Test("A cancelled restore still shows no error")
    func cancelledRestore() async {
        let store = StubPurchaseStoreClient()
        store.restoreError = CancellationError()
        let purchases = makeService(store: store)
        await purchases.start()

        #expect(await purchases.restorePurchases() == .cancelled)
        #expect(purchases.lastErrorMessage == nil)
    }

    /// Guards the app-side state only; the stub cannot model StoreKit's own
    /// behavior after reconnecting.
    @Test(
        "App state left by an offline restore does not block the next purchase",
        arguments: [StoreProductID.plusMonthly, .plusAnnual])
    func firstPurchaseAfterReconnect(_ id: StoreProductID) async {
        let store = StubPurchaseStoreClient()
        store.restoreError = StoreKitError.networkError(URLError(.notConnectedToInternet))
        let purchases = makeService(store: store)
        await purchases.start()
        _ = await purchases.restorePurchases()

        // The tester dismisses the alert and reconnects.
        purchases.clearMessages()
        store.restoreError = nil

        let outcome = await purchases.purchase(StoreProduct(id))

        #expect(outcome == .success)
        #expect(purchases.isUnlimitedWatchlist)
        #expect(purchases.lastErrorMessage == nil)
        #expect(purchases.isPurchasing == false)
    }

    @Test("A product-load failure after a failed restore uses the purchase title")
    func loadFailureAfterRestoreFailureUsesPurchaseTitle() async {
        let store = StubPurchaseStoreClient()
        store.restoreError = URLError(.notConnectedToInternet)
        let purchases = makeService(store: store)
        await purchases.start()
        _ = await purchases.restorePurchases()

        // Offline, the paywall's product load can finish after Restore failed.
        store.loadError = URLError(.notConnectedToInternet)
        await purchases.loadProducts()

        #expect(purchases.lastErrorMessage == "Couldn't load purchase options. Please try again.")
        #expect(purchases.lastErrorTitle == "Couldn't Complete Purchase")
    }

    @Test("A purchase failure after a failed restore uses the purchase title")
    func purchaseFailureAfterRestoreFailureUsesPurchaseTitle() async {
        let store = StubPurchaseStoreClient()
        store.restoreError = StoreKitError.networkError(URLError(.notConnectedToInternet))
        let purchases = makeService(store: store)
        await purchases.start()
        _ = await purchases.restorePurchases()
        purchases.clearMessages()
        store.restoreError = nil
        store.reportsStaleSuccess = true

        guard case .failed = await purchases.purchase(StoreProduct(.plusMonthly)) else {
            Issue.record("Expected a stale success to be reported as a failure")
            return
        }
        #expect(purchases.lastErrorTitle == "Couldn't Complete Purchase")
    }
}
