import Combine
import Foundation
import StoreKit
import OSLog

/// StoreKit 2 subscription manager. Owns all purchase, restore and entitlement
/// logic so the rest of the app only needs to read `tier` and `products`.
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    /// Tier backed by verified StoreKit entitlements.
    @Published private(set) var entitledTier: SubscriptionTier = .free
    /// A short-lived, server-verified grant scoped to the currently signed-in
    /// SceneMe account; never stored as a StoreKit transaction or persisted.
    @Published private(set) var complimentaryReviewTier: SubscriptionTier = .free
    private var complimentaryReviewExpiresAt: Date?
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productLoadError: String?
    private let storeLogger = Logger(subsystem: "com.sceneme.app", category: "StoreKit")
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    /// Transaction proof sent to SceneMe's backend for Apple verification.
    @Published private(set) var latestTransactionID: String?

    /// SceneMe account currently signed in — used to tag and filter purchases.
    private(set) var boundAccountToken: UUID?

    /// The tier the rest of the app honors.
    var tier: SubscriptionTier {
        // Give a valid server grant priority over a cached Xcode Debug override.
        if complimentaryReviewTier == .pro,
           let expiry = complimentaryReviewExpiresAt,
           expiry > Date() {
            return .pro
        }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-screenshots")
            || ProcessInfo.processInfo.environment["SCENEME_SCREENSHOT_MODE"] == "1" {
            return .free
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-authenticated")
            || ProcessInfo.processInfo.environment["SCENEME_UI_TEST_AUTHENTICATED"] == "1"
            || UserDefaults.standard.bool(forKey: "SCENEME_UI_TEST_AUTHENTICATED") {
            return .pro
        }
        #endif
        return entitledTier
    }

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        // Tasks are deferred to start() — starting StoreKit listeners in init()
        // before the run loop is ready causes an OS_dispatch_mach_msg crash.
    }

    /// Bind StoreKit entitlements to a SceneMe user so two accounts on one
    /// Apple ID do not share Creator/Pro after new purchases.
    func bindAccount(userId: String?) {
        // Clear access whenever the signed-in account changes.
        complimentaryReviewExpiresAt = nil
        complimentaryReviewTier = .free
        boundAccountToken = userId.flatMap(UUID.init(uuidString:))
        entitledTier = .free
        latestTransactionID = nil
        Task { await refreshEntitlement() }
    }

    /// Trust only a valid, unexpired server grant for this specific user ID.
    func applyReviewAccess(_ subscription: APIService.AccountStatus.Subscription, for userId: String) {
        guard let id = UUID(uuidString: userId), id == boundAccountToken else { return }

        var expiry: Date?
        if subscription.isReviewAccess == true,
           subscription.environment == "complimentary_review",
           subscription.status == "active",
           subscription.tier == "pro",
           let raw = subscription.expiresAt {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiry = parser.date(from: raw)
            if expiry == nil {
                parser.formatOptions = [.withInternetDateTime]
                expiry = parser.date(from: raw)
            }
        }
        complimentaryReviewExpiresAt = expiry
        complimentaryReviewTier = (expiry ?? .distantPast) > Date() ? .pro : .free
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
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        productLoadError = nil
        defer { isLoadingProducts = false }
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
            let missingCount = SceneMeProductID.allCases.count - products.count
            storeLogger.info("Product fetch returned \(fetched.count) products; missing \(missingCount)")
            if missingCount > 0 {
                productLoadError = "Some subscription prices are unavailable from the App Store. Please try again shortly."
            }
        } catch {
            productLoadError = "Unable to load subscription prices. Check your connection and try again."
            let nsError = error as NSError
            storeLogger.error("Product fetch failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
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

        var options: Set<Product.PurchaseOption> = []
        if let boundAccountToken {
            options.insert(.appAccountToken(boundAccountToken))
        }

        let result = try await product.purchase(options: options)

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlement()
        case .pending:
            // Family sharing / Ask to Buy — entitlement arrives via listener.
            throw SubscriptionError.pendingApproval
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restorePurchases() async -> String {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
        } catch {
            #if DEBUG
            print("[SubscriptionService] Restore sync failed: \(error)")
            #endif
            return "Restore could not be completed. Check your App Store connection and try again."
        }
        await refreshEntitlement()
        return tier > .free
            ? "Your \(tier.displayName) subscription was restored."
            : "No active SceneMe subscription was found for this Apple ID."
    }

    // MARK: - Entitlement

    /// Highest active tier for the bound SceneMe account.
    func refreshEntitlement() async {
        var highest: SubscriptionTier = .free
        var highestTransactionID: String?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard !transaction.isUpgraded else { continue }
            guard belongsToBoundAccount(transaction) else { continue }

            if let id = SceneMeProductID(rawValue: transaction.productID) {
                if id.tier > highest {
                    highest = id.tier
                    highestTransactionID = String(transaction.id)
                }
            }
        }

        entitledTier = highest
        latestTransactionID = highestTransactionID
    }

    /// Tagged purchases must match the signed-in SceneMe user.
    /// Untagged (legacy) purchases still apply so existing subscribers are not locked out.
    private func belongsToBoundAccount(_ transaction: Transaction) -> Bool {
        guard let boundAccountToken else { return true }
        guard let token = transaction.appAccountToken else { return true }
        return token == boundAccountToken
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
                    #if DEBUG
                    print("[SubscriptionService] Unverified transaction: \(error)")
                    #endif
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
        if let price = product(for: id)?.displayPrice {
            return price
        }
        #if DEBUG
        if isScreenshotMode {
            return screenshotDisplayPrice(for: id)
        }
        #endif
        return nil
    }

    /// Per-month equivalent when displayed on a yearly card, e.g. "$5.00/mo".
    func monthlyEquivalent(for id: SceneMeProductID) -> String? {
        guard id.isYearly else { return nil }
        if let product = product(for: id) {
            let monthly = (product.price / 12) as Decimal
            let formatted = product.priceFormatStyle
                .precision(.fractionLength(2))
                .format(monthly)
            return "\(formatted)/mo"
        }
        #if DEBUG
        if isScreenshotMode {
            return id == .proYearly ? "$10.00/mo" : "$4.58/mo"
        }
        #endif
        return nil
    }

    func yearlySavingsPercent(for tier: SubscriptionTier) -> Int? {
        let monthlyID: SceneMeProductID = tier == .pro ? .proMonthly : .creatorMonthly
        let yearlyID: SceneMeProductID = tier == .pro ? .proYearly : .creatorYearly
        if
            let monthly = product(for: monthlyID)?.price,
            let yearly = product(for: yearlyID)?.price,
            monthly > 0
        {
            let annualIfMonthly = monthly * 12
            guard annualIfMonthly > yearly else { return nil }
            let saved = ((annualIfMonthly - yearly) / annualIfMonthly) * 100
            return NSDecimalNumber(decimal: saved).intValue
        }
        #if DEBUG
        if isScreenshotMode {
            return tier == .pro ? 33 : 34
        }
        #endif
        return nil
    }

    #if DEBUG
    private var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-screenshots")
            || ProcessInfo.processInfo.environment["SCENEME_SCREENSHOT_MODE"] == "1"
    }

    /// Mirrors SceneMe.storekit for deterministic UI-test captures only. Unit
    /// tests fail if the approved StoreKit configuration drifts from these values.
    private func screenshotDisplayPrice(for id: SceneMeProductID) -> String {
        switch id {
        case .creatorMonthly: "$6.99"
        case .creatorYearly: "$54.99"
        case .proMonthly: "$14.99"
        case .proYearly: "$119.99"
        }
    }
    #endif
}

// MARK: - Error

enum SubscriptionError: LocalizedError {
    case productNotFound
    case verificationFailed
    case pendingApproval

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found. Please try again later."
        case .verificationFailed:
            return "Purchase verification failed. Please contact support."
        case .pendingApproval:
            return "This purchase is pending approval. Access will unlock automatically after Apple completes it."
        }
    }
}
