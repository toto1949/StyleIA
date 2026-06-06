import Foundation
import SwiftData

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

#if canImport(PostHog)
import PostHog
#endif

#if canImport(RevenueCat)
import RevenueCat
#endif

enum SubscriptionPlan: Equatable {
    case free
    case pro

    var title: String {
        switch self {
        case .free: L10n.string("profile.subscription.free")
        case .pro: L10n.string("profile.subscription.pro")
        }
    }

    var detail: String {
        switch self {
        case .free: L10n.string("profile.subscription.freeDetail")
        case .pro: L10n.string("profile.subscription.proDetail")
        }
    }
}

protocol SubscriptionManaging {
    func currentPlan() async -> SubscriptionPlan
    func upgradeToPro() async throws -> SubscriptionPlan
}

protocol AnalyticsTracking {
    func capture(_ event: String, properties: [String: String])
}

protocol CrashReporting {
    func record(error: Error)
}

@MainActor
final class DependencyContainer {
    let modelContainer: ModelContainer
    let keychain: KeychainHelper
    let apiService: APIService
    let authService: AuthService
    let uploadService: UploadService
    let safetyService: SafetyService
    let generationService: GenerationService
    let imageCacheService: ImageCacheService
    let historyService: HistoryService
    let haptics: HapticManager
    let subscriptionManager: SubscriptionManaging
    let analytics: AnalyticsTracking
    let crashReporter: CrashReporting

    let privacyPolicyURL: URL
    let appShareURL: URL

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        let baseURL = Self.configuredURL(
            key: "API_BASE_URL",
            fallback: "https://api.stylist-app.com/v1"
        )
        let webSocketURL = Self.configuredURL(
            key: "WEBSOCKET_BASE_URL",
            fallback: "wss://api.stylist-app.com/ws"
        )
        let privacyURL = Self.configuredURL(
            key: "PRIVACY_POLICY_URL",
            fallback: "https://stylist-app.com/privacy"
        )
        let shareURL = Self.configuredURL(
            key: "APP_SHARE_URL",
            fallback: "https://apps.apple.com/app/styleai"
        )

        keychain = KeychainHelper()
        apiService = APIService(baseURL: baseURL, keychain: keychain)
        authService = AuthService(apiService: apiService, keychain: keychain)
        uploadService = UploadService(apiService: apiService)
        safetyService = SafetyService()
        generationService = GenerationService(
            apiService: apiService,
            webSocketBaseURL: webSocketURL,
            keychain: keychain
        )
        imageCacheService = ImageCacheService()
        historyService = HistoryService(
            apiService: apiService,
            imageCache: imageCacheService,
            modelContext: modelContainer.mainContext
        )
        haptics = HapticManager()

        let crashReporter = FirebaseCrashReporter()
        crashReporter.configure()
        self.crashReporter = crashReporter

        let analytics = PostHogAnalyticsTracker()
        analytics.configure()
        self.analytics = analytics

        let subscriptionManager = RevenueCatSubscriptionManager()
        subscriptionManager.configure()
        self.subscriptionManager = subscriptionManager

        privacyPolicyURL = privacyURL
        appShareURL = shareURL
    }

    static func makeModelContainer() -> ModelContainer {
        do {
            let schema = Schema([GenerationRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            preconditionFailure("Unable to create SwiftData container: \(error.localizedDescription)")
        }
    }

    private static func configuredURL(key: String, fallback: String) -> URL {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let candidate = value?.isEmpty == false ? value : fallback

        guard let url = URL(string: candidate ?? fallback) else {
            preconditionFailure("Invalid URL configuration for \(key)")
        }

        return url
    }
}

final class RevenueCatSubscriptionManager: SubscriptionManaging {
    func configure() {
        #if canImport(RevenueCat)
        guard
            let apiKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String,
            !apiKey.isEmpty
        else {
            return
        }
        Purchases.configure(withAPIKey: apiKey)
        #endif
    }

    func currentPlan() async -> SubscriptionPlan {
        #if canImport(RevenueCat)
        await withCheckedContinuation { continuation in
            Purchases.shared.getCustomerInfo { customerInfo, _ in
                let isPro = customerInfo?.entitlements.active["pro"] != nil
                continuation.resume(returning: isPro ? .pro : .free)
            }
        }
        #else
        return .free
        #endif
    }

    func upgradeToPro() async throws -> SubscriptionPlan {
        #if canImport(RevenueCat)
        return try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let package = offerings?.current?.monthly ?? offerings?.current?.availablePackages.first else {
                    continuation.resume(throwing: APIError.notFound)
                    return
                }

                Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
                    if userCancelled {
                        continuation.resume(returning: .free)
                        return
                    }
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let isPro = customerInfo?.entitlements.active["pro"] != nil
                    continuation.resume(returning: isPro ? .pro : .free)
                }
            }
        }
        #else
        return .free
        #endif
    }
}

final class PostHogAnalyticsTracker: AnalyticsTracking {
    func configure() {
        #if canImport(PostHog)
        guard
            let apiKey = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
            !apiKey.isEmpty
        else {
            return
        }

        let host = (Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String) ?? "https://us.i.posthog.com"
        let config = PostHogConfig(projectToken: apiKey, host: host)
        PostHogSDK.shared.setup(config)
        #endif
    }

    func capture(_ event: String, properties: [String: String] = [:]) {
        #if canImport(PostHog)
        PostHogSDK.shared.capture(event, properties: properties)
        #else
        _ = event
        _ = properties
        #endif
    }
}

final class FirebaseCrashReporter: CrashReporting {
    func configure() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else { return }
        let rootPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
        let resourcesPath = Bundle.main.path(
            forResource: "GoogleService-Info",
            ofType: "plist",
            inDirectory: "Resources"
        )

        guard
            let path = rootPath ?? resourcesPath,
            let options = FirebaseOptions(contentsOfFile: path)
        else {
            #if DEBUG
            print(
                "Firebase: GoogleService-Info.plist not found or invalid in bundle. " +
                "Download it for bundle ID toto.StyleAI and add to Aura/Resources/."
            )
            #endif
            return
        }
        FirebaseApp.configure(options: options)
        #endif
    }

    func record(error: Error) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().record(error: error)
        #else
        _ = error
        #endif
    }
}
