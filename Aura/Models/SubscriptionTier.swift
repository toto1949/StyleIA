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

    /// Non-expiring credits granted for each subscription month.
    var monthlyCreditGrant: Int {
        switch self {
        case .free:    return 3
        case .creator: return 30
        case .pro:     return 100
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
            title: "Generation credits",
            freeValue: "3 starter",
            creatorValue: "30 / month",
            proValue: "100 / month"
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
            title: "Premium image option (2 credits)",
            freeValue: nil,
            creatorValue: nil,
            proValue: "✓"
        )
    ]
}

enum GenerationCreditCost {
    static let standardImage = 1
    static let premiumImage = 2
    static let silentVideo = 6
    static let talkingVideo = 23
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
