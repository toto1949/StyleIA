import Foundation

// MARK: - Subscription tier

enum SubscriptionTier: Int, Comparable, Codable {
    case free     = 0
    case creator  = 1
    case pro      = 2

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: Labels

    var displayName: String {
        switch self {
        case .free:    return "Free"
        case .creator: return "Creator"
        case .pro:     return "Pro"
        }
    }

    var badgeColor: String {
        switch self {
        case .free:    return "#6E6E6E"
        case .creator: return "#C9A85C"
        case .pro:     return "#DFC078"
        }
    }

    // MARK: Limits

    /// Generations allowed per calendar month. nil = unlimited.
    var monthlyGenerationLimit: Int? {
        switch self {
        case .free:    return 5
        case .creator: return 30
        case .pro:     return nil
        }
    }

    // MARK: Feature flags

    var canAnimateToVideo: Bool       { self >= .pro }
    var canAddCompanion: Bool         { self >= .pro }
    var canUseCustomScene: Bool       { self >= .creator }
    var canRerollOutfit: Bool         { self >= .creator }
    var canUseCinematicFilters: Bool  { self >= .creator }
    var usesMaxQuality: Bool          { self >= .pro }
    var removesWatermark: Bool        { self >= .creator }

    // MARK: Feature descriptions (used in the paywall)

    struct Feature {
        let title: String
        let freeValue: String?    // nil = not available on free
        let creatorValue: String?
        let proValue: String?
    }

    static let featureTable: [Feature] = [
        Feature(
            title: "Generations / month",
            freeValue: "5",
            creatorValue: "30",
            proValue: "Unlimited"
        ),
        Feature(
            title: "All scenes + weekly drops",
            freeValue: "✓",
            creatorValue: "✓",
            proValue: "✓"
        ),
        Feature(
            title: "Clean exports (no SceneMe mark)",
            freeValue: nil,
            creatorValue: "✓",
            proValue: "✓"
        ),
        Feature(
            title: "Gender-aware outfits",
            freeValue: "✓",
            creatorValue: "✓",
            proValue: "✓"
        ),
        Feature(
            title: "Cinematic filters",
            freeValue: nil,
            creatorValue: "✓",
            proValue: "✓"
        ),
        Feature(
            title: "Outfit re-roll",
            freeValue: nil,
            creatorValue: "✓",
            proValue: "✓"
        ),
        Feature(
            title: "Custom scene templates",
            freeValue: nil,
            creatorValue: "✓",
            proValue: "✓"
        ),
        Feature(
            title: "Companion photos",
            freeValue: nil,
            creatorValue: nil,
            proValue: "✓"
        ),
        Feature(
            title: "Video Director + voice & captions",
            freeValue: nil,
            creatorValue: nil,
            proValue: "✓"
        ),
        Feature(
            title: "Max generation quality",
            freeValue: nil,
            creatorValue: nil,
            proValue: "✓"
        )
    ]
}

// MARK: - Product IDs

enum SceneMeProductID: String, CaseIterable {
    case creatorMonthly = "com.sceneme.creator.monthly"
    case creatorYearly  = "com.sceneme.creator.yearly"
    case proMonthly     = "com.sceneme.pro.monthly"
    case proYearly      = "com.sceneme.pro.yearly"

    var tier: SubscriptionTier {
        switch self {
        case .creatorMonthly, .creatorYearly: return .creator
        case .proMonthly,     .proYearly:     return .pro
        }
    }

    var isYearly: Bool {
        self == .creatorYearly || self == .proYearly
    }
}

// MARK: - Monthly usage counter

/// Tracks how many generations a user has made in the current calendar month.
/// Stored in UserDefaults, keyed by user ID + month so it's naturally isolated per account.
struct MonthlyUsageCounter {
    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    private var currentKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return "sceneme.usage.\(userId).\(formatter.string(from: Date()))"
    }

    var count: Int {
        UserDefaults.standard.integer(forKey: currentKey)
    }

    func increment() {
        let key = currentKey
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
    }

    /// Returns remaining generations this month, or nil if the tier is unlimited.
    func remaining(for tier: SubscriptionTier) -> Int? {
        guard let limit = tier.monthlyGenerationLimit else {
            return nil
        }
        return max(0, limit - count)
    }

    func hasReachedLimit(for tier: SubscriptionTier) -> Bool {
        guard let limit = tier.monthlyGenerationLimit else {
            return false
        }
        return count >= limit
    }

    /// Removes every monthly usage key for this account (used on account delete).
    static func wipeAll(for userId: String) {
        let prefix = "sceneme.usage.\(userId)."
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
