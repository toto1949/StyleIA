import Foundation
import Testing
import StoreKit
import StoreKitTest
@testable import Aura

struct StoreKitConfigurationTests {
    // Opt in on a host with a working StoreKit test service. A failed local
    // purchase run is a release blocker, not proof of Sandbox compatibility.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCENEME_RUN_STOREKIT_TESTS"] == "1")) @MainActor
    func localPurchaseRenewalRefundAndExpiry() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SceneMe.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions(); session.resetToDefaultState() }

        let service = SubscriptionService()
        let account = UUID()
        service.bindAccount(userId: account.uuidString)
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await service.loadProducts()
        #expect(service.products.isEmpty)
        #expect(service.productLoadError != nil)
        #expect(!service.isLoadingProducts)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await service.loadProducts()
        #expect(service.products.count == 4)
        #expect(service.productLoadError == nil)
        #expect(!service.isLoadingProducts)
        for id in SceneMeProductID.allCases {
            #expect(service.formattedPrice(for: id) != nil)
        }

        let creator = "com.sceneme.creator.monthly"
        let purchase = try await session.buyProduct(identifier: creator, options: [.appAccountToken(account)])
        await service.refreshEntitlement()
        #expect(service.entitledTier == .creator)
        #expect(service.latestTransactionID == String(purchase.id))

        // A different SceneMe account must not inherit this tagged purchase.
        service.bindAccount(userId: UUID().uuidString)
        await service.refreshEntitlement()
        #expect(service.entitledTier == .free)

        service.bindAccount(userId: account.uuidString)
        await service.refreshEntitlement()
        #expect(service.entitledTier == .creator)

        try session.forceRenewalOfSubscription(productIdentifier: creator)
        await service.refreshEntitlement()
        #expect(service.entitledTier == .creator)
        try session.expireSubscription(productIdentifier: creator)
        await service.refreshEntitlement()
        #expect(service.entitledTier == .free)

        let pro = try await session.buyProduct(identifier: "com.sceneme.pro.yearly", options: [.appAccountToken(account)])
        await service.refreshEntitlement()
        #expect(service.entitledTier == .pro)
        try session.refundTransaction(identifier: UInt(pro.id))
        await service.refreshEntitlement()
        #expect(service.entitledTier == .free)

        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        try await service.purchase(.creatorMonthly)
        #expect(!service.isPurchasing)
        #expect(service.entitledTier == .free)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        try await service.purchase(.creatorMonthly)
        #expect(service.entitledTier == .creator)
        #expect(!service.isPurchasing)
    }

    @Test
    func localConfigurationMatchesProductContract() throws {
        let configurationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SceneMe.storekit")
        #expect(FileManager.default.fileExists(atPath: configurationURL.path))
        let data = try Data(contentsOf: configurationURL)
        let configuration = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let groups = configuration["subscriptionGroups"] as? [[String: Any]] ?? []
        let subscriptions = groups.flatMap {
            $0["subscriptions"] as? [[String: Any]] ?? []
        }

        let expectedIDs = Set(SceneMeProductID.allCases.map(\.rawValue))
        let configuredIDs = Set(subscriptions.compactMap { $0["productID"] as? String })
        #expect(configuredIDs == expectedIDs)
        #expect(subscriptions.count == expectedIDs.count)
        #expect(subscriptions.allSatisfy { $0["type"] as? String == "RecurringSubscription" })
        #expect(subscriptions.allSatisfy {
            guard let period = $0["recurringSubscriptionPeriod"] as? String else { return false }
            return period == "P1M" || period == "P1Y"
        })

        let pricePairs: [(String, String)] = subscriptions.compactMap { product in
            guard
                let id = product["productID"] as? String,
                let price = product["displayPrice"] as? String
            else { return nil }
            return (id, price)
        }
        let configuredPrices: [String: String] = Dictionary(uniqueKeysWithValues: pricePairs)
        #expect(configuredPrices == [
            "com.sceneme.creator.monthly": "6.99",
            "com.sceneme.creator.yearly": "54.99",
            "com.sceneme.pro.monthly": "14.99",
            "com.sceneme.pro.yearly": "119.99"
        ])

        for productID in SceneMeProductID.allCases {
            #expect(productID.tier == (productID.rawValue.contains(".pro.") ? .pro : .creator))
            #expect(productID.isYearly == productID.rawValue.hasSuffix(".yearly"))
        }
    }
}
