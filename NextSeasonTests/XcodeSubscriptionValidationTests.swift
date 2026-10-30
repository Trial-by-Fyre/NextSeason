import Foundation
import StoreKit
import Testing

@testable import NextSeason

@MainActor
struct XcodeSubscriptionValidationTests {
    private let purchaseDate = Date(timeIntervalSince1970: 100)

    private func status(
        _ state: Product.SubscriptionInfo.RenewalState,
        id: UInt64 = 6, originalID: UInt64 = 6, date: Date? = nil, verified: Bool = true
    ) -> XcodeSubscriptionValidation.Status {
        .init(
            id: id, originalID: originalID, purchaseDate: date ?? purchaseDate,
            state: state, isVerified: verified)
    }

    private func check(_ statuses: [XcodeSubscriptionValidation.Status]) async
        -> PlusEntitlementCheck
    {
        await XcodeSubscriptionValidation.check(
            isXcode: true, transactionID: 6, originalID: 6, purchaseDate: purchaseDate,
            loadStatuses: { statuses })
    }

    @Test("Same-ID pending state 0 cannot grant access; subscribed approval can")
    func pendingThenApproved() async {
        #expect(await check([status(.init(rawValue: 0))]) == .unverified)
        #expect(await check([status(.subscribed)]) == .active)
    }

    @Test(
        "Subscribed and grace retain access without a local expiration-date cutoff",
        arguments: [Product.SubscriptionInfo.RenewalState.subscribed, .inGracePeriod])
    func entitledStates(_ state: Product.SubscriptionInfo.RenewalState) async {
        #expect(await check([status(state)]) == .active)
    }

    @Test(
        "Known terminal states do not entitle",
        arguments: [Product.SubscriptionInfo.RenewalState.expired, .inBillingRetryPeriod, .revoked])
    func inactiveStates(_ state: Product.SubscriptionInfo.RenewalState) async {
        #expect(await check([status(state)]) == .inactive)
    }

    @Test("Missing, unverified, future and failed statuses are uncertain, not a confirmed lapse")
    func uncertainStatuses() async {
        #expect(await check([]) == .unverified)
        #expect(await check([status(.subscribed, verified: false)]) == .unverified)
        #expect(await check([status(.init(rawValue: 999))]) == .unverified)
        #expect(await check([status(.expired), status(.init(rawValue: 0))]) == .unverified)
        let result = await XcodeSubscriptionValidation.check(
            isXcode: true, transactionID: 6, originalID: 6, purchaseDate: purchaseDate
        ) { throw PurchaseError.unverified }
        #expect(result == .unverified)
    }

    @Test("Unrelated or older purchases cannot approve a pending transaction")
    func identityAndLineage() async {
        #expect(await check([status(.subscribed, id: 7, originalID: 7)]) == .unverified)
        #expect(
            await check([status(.subscribed, id: 5, date: purchaseDate.addingTimeInterval(-1))])
                == .unverified)
        #expect(
            await check([status(.subscribed, id: 7)]) == .unverified,
            "Equal dates do not order distinct IDs")
        #expect(
            await check([status(.subscribed, id: 7, date: purchaseDate.addingTimeInterval(1))])
                == .active)
        #expect(
            await check([status(.revoked, id: 7, date: purchaseDate.addingTimeInterval(1))])
                == .inactive)
    }

    @Test("A verified active status wins over an uncertain matching status")
    func validStatusWins() async {
        #expect(await check([status(.init(rawValue: 0)), status(.inGracePeriod)]) == .active)
    }

    @Test("Production and sandbox policy never depends on an extra status lookup")
    func nonXcodeBypassesLookup() async {
        var lookups = 0
        let result = await XcodeSubscriptionValidation.check(
            isXcode: false, transactionID: 6, originalID: 6, purchaseDate: purchaseDate
        ) {
            lookups += 1
            throw PurchaseError.unverified
        }
        #expect(result == .active)
        #expect(lookups == 0)
    }
}
