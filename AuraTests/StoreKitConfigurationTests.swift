import Foundation
import Testing
@testable import Aura

struct StoreKitConfigurationTests {
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
