import Combine
import Foundation
import StoreKit

/// StoreKit 2 subscription manager. Owns all purchase, restore and entitlement
/// logic so the rest of the app only needs to read `tier` and `products`.
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        // Tasks are deferred to start() — starting StoreKit listeners in init()
        // before the run loop is ready causes an OS_dispatch_mach_msg crash.
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    /// Call exactly once from the root view's `.task` modifier, after the
    /// app's run loop is fully initialised.
    func start() {
        guard transactionListenerTask == nil else { return }
        transactionListenerTask = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: SceneMeProductID.allCases.map(\.rawValue))
            // Sort: pro before creator, monthly before yearly within each tier.
            products = fetched.sorted { lhs, rhs in
                let lhsID = SceneMeProductID(rawValue: lhs.id)
                let rhsID = SceneMeProductID(rawValue: rhs.id)
                let lhsTier = lhsID?.tier.rawValue ?? 0
                let rhsTier = rhsID?.tier.rawValue ?? 0
                if lhsTier != rhsTier { return lhsTier > rhsTier }
                return !(lhsID?.isYearly ?? false) && (rhsID?.isYearly ?? true)
            }
        } catch {
            // Products stay empty; paywall will show price placeholders.
            print("[SubscriptionService] Product fetch failed: \(error)")
        }
    }

    func product(for id: SceneMeProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    // MARK: - Purchase

    func purchase(_ productID: SceneMeProductID) async throws {
        guard let product = product(for: productID) else {
            throw SubscriptionError.productNotFound
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlement()
        case .pending:
            // Family sharing / Ask to Buy — entitlement arrives via listener.
            break
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
        } catch {
            print("[SubscriptionService] Restore sync failed: \(error)")
        }
        await refreshEntitlement()
    }

    // MARK: - Entitlement

    /// Highest active tier across all product IDs.
    func refreshEntitlement() async {
        var highest: SubscriptionTier = .free

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard !transaction.isUpgraded else { continue }

            if let id = SceneMeProductID(rawValue: transaction.productID) {
                if id.tier > highest {
                    highest = id.tier
                }
            }
        }

        tier = highest
    }

    // MARK: - Transaction listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await transaction.finish()
                    await refreshEntitlement()
                } catch {
                    print("[SubscriptionService] Unverified transaction: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let value):
            return value
        }
    }

    /// Human-readable formatted price string for a product ID, e.g. "$7.99".
    /// Returns nil until the product has loaded from the App Store, so the UI
    /// never shows a price StoreKit didn't provide.
    func formattedPrice(for id: SceneMeProductID) -> String? {
        product(for: id)?.displayPrice
    }

    /// Per-month equivalent when displayed on a yearly card, e.g. "$5.00/mo".
    func monthlyEquivalent(for id: SceneMeProductID) -> String? {
        guard id.isYearly, let product = product(for: id) else { return nil }
        let monthly = (product.price / 12) as Decimal
        let formatted = product.priceFormatStyle
            .precision(.fractionLength(2))
            .format(monthly)
        return "\(formatted)/mo"
    }
}

// MARK: - Error

enum SubscriptionError: LocalizedError {
    case productNotFound
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found. Please try again later."
        case .verificationFailed:
            return "Purchase verification failed. Please contact support."
        }
    }
}
