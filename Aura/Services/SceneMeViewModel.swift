import Combine
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum SceneMeFlowStep: Equatable {
    case home
    case scenePicker
    case sceneOptions
    case generating
    case result
}

enum SceneMeTab: String, CaseIterable, Identifiable {
    case home
    case explore
    case gallery
    case profile

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .explore:
            return "magnifyingglass"
        case .gallery:
            return "square.grid.2x2"
        case .profile:
            return "person"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .explore:
            return "magnifyingglass"
        case .gallery:
            return "square.grid.2x2.fill"
        case .profile:
            return "person.fill"
        }
    }
}

@MainActor
final class SceneMeViewModel: ObservableObject {
    @Published var flow: SceneMeFlowStep = .home
    @Published var tab: SceneMeTab = .home
    @Published var session: SceneMeSession?

    @Published var scenes: [SceneTemplate] = SceneCatalog.bundled
    /// User-authored templates saved on-device for reuse in the picker.
    @Published var customScenes: [SceneTemplate] = []
    @Published var profile = UserProfile.default

    @Published var userPhoto: UIImage?
    @Published var photoItem: PhotosPickerItem?
    @Published var photoFileName = "portrait_selfie.jpg"

    @Published var companionPhoto: UIImage?
    @Published var companionItem: PhotosPickerItem?

    @Published var request: GenerationRequest?

    @Published var isGenerating = false
    @Published var isRerolling = false
    @Published var isAnimating = false
    @Published private(set) var isDeletingAccount = false
    @Published var presentVideoPlayer = false
    /// Which directed clip is open in the fullscreen player.
    @Published var playingVideoClip: SceneVideoClip?
    @Published var generationProgress = 0
    @Published var generatingSceneName = ""
    @Published var notice: String?

    /// Set to show the paywall sheet; cleared on dismiss.
    @Published var paywallTrigger: PaywallTrigger?

    /// Explicit consent is required before photos or creative text leave the
    /// device for processing by SceneMe's third-party AI providers.
    @Published var isAIProcessingConsentPresented = false

    @Published var currentResult: GenerationResult?
    @Published var resultImage: UIImage?
    @Published var history: [GenerationResult] = []
    @Published var favoriteIds: Set<String> = []

    let subscriptionService = SubscriptionService.shared
    private let api: APIService?
    private let analyzer: StyleIAImageAnalyzing
    private let sessionStore = SessionStore()
    private var persistence = SceneMeHistoryStore(userId: nil)
    /// Display mirror of the server-owned usage counter. It is never used as
    /// authorization; the backend remains the billable source of truth.
    @Published private(set) var serverCreditBalance = 0

    private var cancellables = Set<AnyCancellable>()

    private var userPhotoS3Key: String?
    private var companionS3Key: String?
    private var suggestedCrop: CGRect?
    private var generationTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var sessionRefreshTask: Task<SceneMeSession, Error>?
    private var currentJobId: String?
    private var pendingAIConsentAction: (() -> Void)?

    // MARK: - Subscription convenience

    var currentTier: SubscriptionTier { subscriptionService.tier }

    var generationsRemainingThisMonth: Int? {
        serverCreditBalance
    }

    var hasReachedGenerationLimit: Bool {
        serverCreditBalance < GenerationCreditCost.standardImage
    }

    var hasAIProcessingConsent: Bool {
        guard let userId = session?.userId else { return false }
        return UserDefaults.standard.bool(forKey: Self.aiConsentKey(for: userId))
    }

    /// Runs an AI-backed action immediately when consent exists, or presents
    /// the disclosure and resumes only after the user explicitly allows it.
    func requestAIProcessingConsent(then action: @escaping () -> Void) {
        guard hasAIProcessingConsent else {
            pendingAIConsentAction = action
            isAIProcessingConsentPresented = true
            return
        }
        action()
    }

    func reviewAIProcessingConsent() {
        pendingAIConsentAction = nil
        isAIProcessingConsentPresented = true
    }

    func allowAIProcessing() {
        guard let userId = session?.userId else { return }
        UserDefaults.standard.set(true, forKey: Self.aiConsentKey(for: userId))
        isAIProcessingConsentPresented = false
        let action = pendingAIConsentAction
        pendingAIConsentAction = nil
        objectWillChange.send()
        action?()
    }

    func cancelAIProcessingConsentRequest() {
        pendingAIConsentAction = nil
    }

    func revokeAIProcessingConsent() {
        guard let userId = session?.userId else { return }
        UserDefaults.standard.removeObject(forKey: Self.aiConsentKey(for: userId))
        pendingAIConsentAction = nil
        userPhotoS3Key = nil
        companionS3Key = nil
        isAIProcessingConsentPresented = false
        objectWillChange.send()
        notice = "AI processing permission was withdrawn."
    }

    /// Shows the paywall sheet for a locked feature; returns false if user already has access.
    @discardableResult
    func requireTier(_ needed: SubscriptionTier, feature: String) -> Bool {
        guard currentTier < needed else { return false }
        paywallTrigger = .featureLocked(feature: feature, tierNeeded: needed)
        return true
    }

    convenience init() {
        #if targetEnvironment(simulator)
        let processInfo = ProcessInfo.processInfo
        let isUITestAuthenticated = processInfo.arguments.contains("-ui-testing-authenticated")
            || processInfo.environment["SCENEME_UI_TEST_AUTHENTICATED"] == "1"
            || UserDefaults.standard.bool(forKey: "SCENEME_UI_TEST_AUTHENTICATED")
        self.init(
            api: isUITestAuthenticated ? nil : APIService(),
            analyzer: VisionStyleIAImageAnalyzer()
        )
        #else
        self.init(api: APIService(), analyzer: VisionStyleIAImageAnalyzer())
        #endif
    }

    init(
        api: APIService?,
        analyzer: StyleIAImageAnalyzing
    ) {
        self.api = api
        self.analyzer = analyzer
        #if targetEnvironment(simulator)
        let launchArguments = ProcessInfo.processInfo.arguments
        let isUITestAuthenticated = launchArguments.contains("-ui-testing-authenticated")
            || ProcessInfo.processInfo.environment["SCENEME_UI_TEST_AUTHENTICATED"] == "1"
            || UserDefaults.standard.bool(forKey: "SCENEME_UI_TEST_AUTHENTICATED")
        if launchArguments.contains("-ui-testing-reset-session") {
            sessionStore.clear()
        }
        if isUITestAuthenticated {
            session = SceneMeSession(
                userId: "ui-test-user",
                email: "reviewer@example.com",
                fullName: "App Reviewer",
                accessToken: "ui-test-token"
            )
        } else {
            session = sessionStore.load()
        }
        #else
        session = sessionStore.load()
        #endif
        if let session {
            persistence = SceneMeHistoryStore(userId: session.userId)
            profile = UserProfile(displayName: session.displayName)
            userPhoto = persistence.loadPhoto()
            subscriptionService.bindAccount(userId: session.userId)
        }
        history = persistence.loadHistory()
        favoriteIds = persistence.loadFavorites()
        customScenes = persistence.loadCustomScenes()

        #if targetEnvironment(simulator)
        if isUITestAuthenticated {
            // A deterministic, entirely local state for UI automation. This
            // branch is excluded from device/App Store builds and never calls
            // the API.
            userPhoto = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                UIColor.systemGray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        }
        #endif

        // Re-render views reading currentTier when entitlements change, since
        // they observe this view model, not the service.
        subscriptionService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Persist every newly verified StoreKit entitlement on the backend as
        // soon as purchase, restore, renewal, or Transaction.updates changes
        // the active transaction. Protected API calls still re-verify the
        // transaction, so this is synchronization rather than authorization.
        subscriptionService.$latestTransactionID
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] transactionID in
                Task { [weak self] in
                    await self?.syncSubscriptionWithServer(transactionID: transactionID)
                }
            }
            .store(in: &cancellables)

        #if targetEnvironment(simulator)
        if session != nil, !isUITestAuthenticated {
            Task {
                await refreshAccountAccess()
                await syncHistoryFromServer()
                await syncAccountStateFromServer()
            }
        }
        #else
        if session != nil {
            Task {
                await refreshAccountAccess()
                await syncHistoryFromServer()
                await syncAccountStateFromServer()
            }
        }
        #endif
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var selectedScene: SceneTemplate? {
        request?.scene
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        guard let api else {
            throw SceneMeAPIError.failed("SceneMe is temporarily unavailable. Please try again later.")
        }
        adopt(auth: try await api.signIn(email: email, password: password))
        // Do not return control to the signed-in UI until the account-scoped
        // server entitlement has been applied. Otherwise the App Review user
        // can briefly see Free-tier paywalls after a successful login.
        await refreshAccountAccess()
    }

    func signUp(email: String, password: String, fullName: String) async throws {
        guard let api else {
            throw SceneMeAPIError.failed("SceneMe is temporarily unavailable. Please try again later.")
        }
        adopt(auth: try await api.signUp(email: email, password: password, fullName: fullName))
        await refreshAccountAccess()
    }

    func signInWithApple() async throws {
        guard let api else {
            throw SceneMeAPIError.failed("SceneMe is temporarily unavailable. Please try again later.")
        }

        let credential = try await SocialAuthService.shared.signInWithApple()
        adopt(auth: try await api.signInWithApple(
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            fullName: credential.fullName
        ))
        await refreshAccountAccess()
    }

    func signInWithGoogle() async throws {
        guard let api else {
            throw SceneMeAPIError.failed("SceneMe is temporarily unavailable. Please try again later.")
        }

        let identityToken = try await SocialAuthService.shared.signInWithGoogle()
        adopt(auth: try await api.signInWithGoogle(identityToken: identityToken, fullName: ""))
        await refreshAccountAccess()
    }

    func signOut() {
        cancelInFlightWork()
        if let api, let refreshToken = session?.refreshToken {
            Task { try? await api.signOut(refreshToken: refreshToken) }
        }
        SocialAuthService.shared.signOutGoogle()
        sessionStore.clear()
        session = nil
        subscriptionService.bindAccount(userId: nil)
        clearPersonalState()
    }

    /// Deletes the account and all server-side data, then signs out locally.
    func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        cancelInFlightWork()
        let userId = session?.userId
        guard let api else {
            wipeLocalAccountData(userId: userId)
            signOut()
            return
        }

        do {
            let token = try await token(using: api)
            try await api.deleteAccount(token: token)
            wipeLocalAccountData(userId: userId)
            signOut()
            notice = "Your account and all data were deleted."
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? "Could not delete your account."
        }
    }

    private func adopt(auth: APIService.AuthResponse) {
        cancelInFlightWork()
        clearPersonalState()

        let newSession = SceneMeSession(
            userId: auth.userId,
            email: auth.email,
            fullName: auth.fullName,
            accessToken: auth.accessToken,
            refreshToken: auth.refreshToken
        )
        sessionStore.save(newSession)
        session = newSession
        profile = UserProfile(displayName: newSession.displayName)
        persistence = SceneMeHistoryStore(userId: newSession.userId)
        history = persistence.loadHistory()
        favoriteIds = persistence.loadFavorites()
        userPhoto = persistence.loadPhoto()
        customScenes = persistence.loadCustomScenes()
        subscriptionService.bindAccount(userId: newSession.userId)
        Task {
            await syncHistoryFromServer()
            await syncAccountStateFromServer()
        }
    }

    /// Called when the backend rejects our token (expired session).
    private func forceSignOut() {
        signOut()
        notice = SceneMeAPIError.unauthorized.errorDescription
    }

    private func cancelInFlightWork() {
        generationTask?.cancel()
        generationTask = nil
        animationTask?.cancel()
        animationTask = nil
        isGenerating = false
        isRerolling = false
        isAnimating = false
    }

    private func wipeLocalAccountData(userId: String?) {
        guard let userId else { return }
        SceneMeHistoryStore(userId: userId).wipeAll()
        UserDefaults.standard.removeObject(forKey: Self.aiConsentKey(for: userId))
    }

    private static func aiConsentKey(for userId: String) -> String {
        "sceneme.aiProcessingConsent.v1.\(userId)"
    }

    private func clearPersonalState() {
        persistence = SceneMeHistoryStore(userId: nil)
        serverCreditBalance = 0
        history = []
        favoriteIds = []
        customScenes = []
        profile = .default
        userPhoto = nil
        photoItem = nil
        companionPhoto = nil
        companionItem = nil
        userPhotoS3Key = nil
        companionS3Key = nil
        suggestedCrop = nil
        request = nil
        currentResult = nil
        resultImage = nil
        currentJobId = nil
        presentVideoPlayer = false
        playingVideoClip = nil
        generatingSceneName = ""
        generationProgress = 0
        flow = .home
        tab = .home
    }

    /// Refresh the reviewer grant from the signed-in user's server session.
    /// The same serialized refresh-token path used by generation requests is
    /// required here so a restored, expired access token cannot hide a valid
    /// complimentary review entitlement.
    func refreshAccountAccess() async {
        guard let api, let signedIn = session else { return }
        do {
            let accessToken = try await token(using: api)
            let account = try await api.fetchAccountStatus(token: accessToken)
            guard session?.userId == signedIn.userId else { return }
            subscriptionService.applyAccountAccess(account.subscription, for: signedIn.userId)
            #if DEBUG
            print("[SceneMe][account-access] backend tier=\(account.subscription.tier), review=\(account.subscription.isReviewAccess == true), effective tier=\(subscriptionService.tier.displayName)")
            #endif
        } catch SceneMeAPIError.unauthorized {
            // `token(using:)` has already cleared an invalid account session.
        } catch {
            // A network failure never creates access. A previously verified
            // grant remains bounded by its server-supplied expiration date.
            #if DEBUG
            print("[SceneMe][account-access] GET /v1/me failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Re-fetch this account's history to replace expiring media URLs.
    func refreshHistoryFromServer() async {
        await syncHistoryFromServer()
    }

    private func syncHistoryFromServer() async {
        guard let api, let userId = session?.userId else { return }
        do {
            let token = try await token(using: api)
            let remote = try await GenerationService(api: api).fetchHistory(token: token)
            guard session?.userId == userId else { return }

            let merged = Self.mergeHistory(local: history, remote: remote)
            history = merged
            persistence.saveHistory(merged)
        } catch {
            // Offline / transient — keep local gallery for this user.
        }
    }

    private func syncAccountStateFromServer() async {
        guard let api, let userId = session?.userId else { return }
        do {
            let token = try await token(using: api)
            let state = try await api.fetchAccountState(token: token)
            guard session?.userId == userId else { return }
            subscriptionService.applyAccountAccess(state.subscription, for: userId)
            serverCreditBalance = state.credits.balance
        } catch {
            // Offline state remains a display hint only; the server still
            // enforces subscription features and billable quotas.
        }
    }

    /// Paywall purchases and restores wait for server verification and the
    /// account's credit balance before reporting success to the user.
    func verifyCurrentPurchase(requiredTier: SubscriptionTier) async throws {
        guard let transactionID = subscriptionService.latestTransactionID else {
            throw SubscriptionError.verificationFailed
        }
        try await verifyTransactionWithServer(transactionID, requiredTier: requiredTier)
    }

    private func syncSubscriptionWithServer(transactionID: String?) async {
        guard let userId = session?.userId else { return }
        guard let transactionID else {
            await syncAccountStateFromServer()
            return
        }
        do {
            try await verifyTransactionWithServer(transactionID, requiredTier: .creator)
        } catch {
            guard session?.userId == userId else { return }
            subscriptionService.setPurchaseVerificationError(
                (error as? LocalizedError)?.errorDescription
                    ?? "SceneMe could not verify this purchase. Use Restore Purchases or contact support."
            )
        }
    }

    private func verifyTransactionWithServer(
        _ transactionID: String,
        requiredTier: SubscriptionTier
    ) async throws {
        guard let api, let userId = session?.userId else {
            throw SceneMeAPIError.unauthorized
        }
        let accessToken = try await token(using: api)
        let verified = try await api.syncSubscription(transactionID: transactionID, token: accessToken)
        guard session?.userId == userId else { throw SceneMeAPIError.unauthorized }
        subscriptionService.applyAccountAccess(verified, for: userId)

        let state = try await api.fetchAccountState(token: accessToken)
        guard session?.userId == userId else { throw SceneMeAPIError.unauthorized }
        subscriptionService.applyAccountAccess(state.subscription, for: userId)
        serverCreditBalance = state.credits.balance

        let serverTier: SubscriptionTier
        switch state.subscription.tier {
        case "pro": serverTier = .pro
        case "creator": serverTier = .creator
        default: serverTier = .free
        }
        guard serverTier >= requiredTier else { throw SubscriptionError.verificationFailed }
        subscriptionService.setPurchaseVerificationError(nil)
    }

    private static func mergeHistory(local: [GenerationResult], remote: [GenerationResult]) -> [GenerationResult] {
        var byId: [String: GenerationResult] = [:]
        for item in local {
            byId[item.id] = item
        }
        for item in remote {
            if let existing = byId[item.id] {
                // Server history has newly signed private-media URLs; use the
                // refreshed image URL rather than locally cached expired URLs.
                var refreshed = item
                refreshed.videoClips = Self.mergeClips(local: existing.videoClips, remote: item.videoClips)
                refreshed.videoURL = refreshed.videoClips.first?.videoURL ?? item.videoURL ?? existing.videoURL
                refreshed.videoCaption = refreshed.videoClips.first?.captionText ?? item.videoCaption ?? existing.videoCaption
                byId[item.id] = refreshed
            } else {
                byId[item.id] = item
            }
        }
        return byId.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static func mergeClips(local: [SceneVideoClip], remote: [SceneVideoClip]) -> [SceneVideoClip] {
        var byKey: [String: SceneVideoClip] = [:]
        for clip in local {
            byKey[clip.cacheKey] = clip
        }
        for clip in remote {
            byKey[clip.cacheKey] = clip
        }
        return byKey.values.sorted { $0.createdAt > $1.createdAt }
    }

    var favoriteResults: [GenerationResult] {
        history.filter { favoriteIds.contains($0.id) }
    }

    func move(to step: SceneMeFlowStep) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            flow = step
        }
    }

    // MARK: - Scenes

    func refreshScenes() async {
        guard let api else { return }

        if let fetched = try? await api.fetchScenes(), !fetched.isEmpty {
            scenes = fetched
        }
    }

    func selectScene(_ scene: SceneTemplate) {
        if request?.scene.id != scene.id {
            request = GenerationRequest(scene: scene)
        }
    }

    /// Builds a scene from the user's own description, saves it for reuse, and jumps to options.
    func createCustomScene(name: String, description: String, outfit: String) {
        let scene = SceneTemplate.custom(name: name, description: description, outfit: outfit)
        customScenes.removeAll { $0.id == scene.id }
        customScenes.insert(scene, at: 0)
        persistence.saveCustomScenes(customScenes)
        request = GenerationRequest(scene: scene)
        notice = "Saved to Yours — tap it anytime to reuse."
        move(to: .sceneOptions)
    }

    func deleteCustomScene(_ scene: SceneTemplate) {
        customScenes.removeAll { $0.id == scene.id }
        persistence.saveCustomScenes(customScenes)
        if request?.scene.id == scene.id {
            request = nil
        }
        notice = "Custom scene removed."
    }

    /// Catalog scenes plus saved custom templates (customs first when browsing All / Yours).
    var pickerScenes: [SceneTemplate] {
        customScenes + scenes.filter { !$0.isCustom }
    }

    func scene(forId id: String) -> SceneTemplate? {
        if let match = customScenes.first(where: { $0.id == id }) {
            return match
        }
        return scenes.first(where: { $0.id == id })
    }

    func improveCustomScene(
        name: String,
        description: String,
        outfit: String
    ) async throws -> APIService.ImprovedSceneTemplate {
        guard let api, let token = session?.accessToken else {
            throw SceneMeAPIError.unauthorized
        }
        return try await api.improveSceneTemplate(
            name: name,
            description: description,
            outfit: outfit,
            token: token,
            appStoreTransactionID: subscriptionService.latestTransactionID
        )
    }

    // MARK: - Photos

    func loadSelectedPhoto() async {
        guard
            let photoItem,
            let data = try? await photoItem.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            return
        }

        let validation = try? await analyzer.validate(image)
        guard validation?.isValid != false else {
            notice = "Please upload a clear photo with one person fully visible."
            return
        }

        userPhoto = image
        suggestedCrop = validation?.suggestedCropRect
        userPhotoS3Key = nil
        photoFileName = "portrait_selfie.jpg"
        persistence.savePhoto(image)

        if flow == .home {
            move(to: .scenePicker)
        }
    }

    func loadCompanionPhoto() async {
        guard
            let companionItem,
            let data = try? await companionItem.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            return
        }

        companionPhoto = image
        companionS3Key = nil
        request?.hasCompanion = true
        request?.companionPhotoPermissionConfirmed = false
    }

    func removeCompanion() {
        companionPhoto = nil
        companionItem = nil
        companionS3Key = nil
        request?.hasCompanion = false
        request?.companionPhotoPermissionConfirmed = false
    }

    // MARK: - Generation

    func startGeneration() {
        requestAIProcessingConsent { [weak self] in
            self?.startGenerationAfterConsent()
        }
    }

    private func startGenerationAfterConsent() {
        guard let request else { return }

        guard !(request.hasCompanion
                && request.companionKind == .friend
                && request.companionGender == .auto) else {
            notice = "Choose your friend's gender before generating so both people are preserved correctly."
            return
        }

        guard !(request.hasCompanion
                && request.companionKind == .friend
                && !request.companionPhotoPermissionConfirmed) else {
            notice = "Confirm that you have this person's permission to use their photo."
            return
        }

        // Display-only preflight. The backend atomically enforces the ledger.
        let requiredCredits = request.imageQuality == .premium
            ? GenerationCreditCost.premiumImage
            : GenerationCreditCost.standardImage
        if serverCreditBalance < requiredCredits {
            if currentTier == .pro {
                notice = "This image needs \(requiredCredits) credits. Your next subscription-month grant will be added automatically."
                return
            }
            let needed: SubscriptionTier = currentTier == .free ? .creator : .pro
            paywallTrigger = .generationLimitReached(remaining: 0, tierNeeded: needed)
            return
        }

        generatingSceneName = request.scene.name
        runGeneration(request: request, rerollOf: nil)
    }

    /// Remix from the result screen: change time/weather and regenerate in place.
    func remix(timeOfDay: TimeOfDay? = nil, weather: WeatherOption? = nil) {
        requestAIProcessingConsent { [weak self] in
            self?.remixAfterConsent(timeOfDay: timeOfDay, weather: weather)
        }
    }

    private func remixAfterConsent(timeOfDay: TimeOfDay?, weather: WeatherOption?) {
        guard var updated = request else { return }
        if let timeOfDay {
            updated.timeOfDay = timeOfDay
        }
        if let weather {
            updated.weather = weather
        }
        request = updated
        generatingSceneName = updated.scene.name
        runGeneration(request: updated, rerollOf: nil)
    }

    /// Regenerates only the outfit, keeping the scene, face and background.
    func rerollOutfit() {
        if requireTier(.creator, feature: "Outfit Re-roll") { return }
        requestAIProcessingConsent { [weak self] in
            self?.rerollOutfitAfterConsent()
        }
    }

    private func rerollOutfitAfterConsent() {
        guard let jobId = currentJobId, let api else { return }
        guard serverCreditBalance >= GenerationCreditCost.standardImage else {
            notice = "An outfit re-roll needs 1 credit."
            return
        }

        isRerolling = true
        let ownerUserId = session?.userId
        generationTask = Task {
            do {
                let token = try await token(using: api)
                let service = GenerationService(
                    api: api,
                    appStoreTransactionID: subscriptionService.latestTransactionID
                )
                let result = try await service.rerollOutfit(
                    jobId: jobId,
                    companionConsentConfirmed: request?.companionKind != .friend
                        || request?.companionPhotoPermissionConfirmed == true,
                    token: token
                ) { [weak self] progress in
                    self?.generationProgress = progress
                }
                try Task.checkCancellation()
                try await adopt(result: result, forUserId: ownerUserId)
                await syncAccountStateFromServer()
            } catch is CancellationError {
                // User cancelled; nothing to surface.
            } catch SceneMeAPIError.unauthorized {
                forceSignOut()
            } catch {
                if session?.userId == ownerUserId {
                    notice = (error as? LocalizedError)?.errorDescription ?? "Outfit reroll failed."
                }
            }
            if session?.userId == ownerUserId {
                isRerolling = false
            }
        }
    }

    /// Animates the current result with Video Director settings.
    /// Matching style + caption + direction reuses the cached clip; a new direction regenerates
    /// and is stored alongside prior clips so all can be replayed.
    func animateScene(motionStyle: VideoMotionStyle, spokenLine: String, directionNote: String = "") {
        if requireTier(.pro, feature: "Video Director") { return }
        let requiredCredits = motionStyle == .talking
            ? GenerationCreditCost.talkingVideo
            : GenerationCreditCost.silentVideo
        guard serverCreditBalance >= requiredCredits else {
            notice = "This clip needs \(requiredCredits) credits. Your next subscription-month grant will be added automatically."
            return
        }
        requestAIProcessingConsent { [weak self] in
            self?.animateSceneAfterConsent(
                motionStyle: motionStyle,
                spokenLine: spokenLine,
                directionNote: directionNote
            )
        }
    }

    private func animateSceneAfterConsent(
        motionStyle: VideoMotionStyle,
        spokenLine: String,
        directionNote: String
    ) {
        guard let result = currentResult else { return }
        guard let api, let jobId = currentJobId else { return }

        isAnimating = true
        let ownerUserId = session?.userId
        let direction = directionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        animationTask?.cancel()
        animationTask = Task {
            await SceneMeNotifications.requestPermissionIfNeeded()
            do {
                let token = try await token(using: api)
                let clip = try await GenerationService(
                    api: api,
                    appStoreTransactionID: subscriptionService.latestTransactionID
                ).animate(
                    jobId: jobId,
                    motionStyle: motionStyle,
                    spokenLine: spokenLine,
                    directionNote: direction,
                    token: token
                ) { _ in }

                try Task.checkCancellation()
                guard session?.userId == ownerUserId else { return }

                let caption = clip.caption?.isEmpty == false ? clip.caption : (spokenLine.isEmpty ? nil : spokenLine)
                let saved = SceneVideoClip(
                    cacheKey: clip.cacheKey
                        ?? "\(motionStyle.rawValue)|\(spokenLine)|\(direction)",
                    motionStyle: clip.motionStyle ?? motionStyle.rawValue,
                    spokenLine: caption,
                    directionNote: clip.directionNote ?? (direction.isEmpty ? nil : direction),
                    videoURL: clip.videoURL,
                    createdAt: Date()
                )

                var updated = result
                if !clip.library.isEmpty {
                    updated.videoClips = Self.mergeClips(local: updated.videoClips, remote: clip.library)
                }
                updated.upsert(clip: saved)
                currentResult = updated
                playingVideoClip = saved
                if let index = history.firstIndex(where: { $0.id == updated.id }) {
                    history[index] = updated
                    persistence.saveHistory(history)
                }
                notice = "Your \(motionStyle.title.lowercased()) clip is ready."
                // Always fire a real system notification (banner + sound), even
                // while browsing Profile — not just the in-app toast title.
                SceneMeNotifications.notifyClipReady(
                    sceneName: result.sceneName,
                    styleTitle: motionStyle.title,
                    resultId: updated.id,
                    force: true
                )
                if flow == .result {
                    presentVideoPlayer = true
                    SceneMeNotifications.clearBadge()
                }
            } catch is CancellationError {
                // User left the screen; nothing to surface.
            } catch SceneMeAPIError.unauthorized {
                forceSignOut()
            } catch {
                if session?.userId == ownerUserId {
                    notice = (error as? LocalizedError)?.errorDescription ?? "Video generation failed."
                }
            }
            if session?.userId == ownerUserId {
                isAnimating = false
            }
        }
    }

    /// Opens the finished clip when the user taps the system notification.
    func openClipFromNotification(userInfo: [AnyHashable: Any]?) {
        SceneMeNotifications.clearBadge()
        guard isAuthenticated else { return }

        let resultId = userInfo?["resultId"] as? String
        if let resultId,
           let match = history.first(where: { $0.id == resultId }),
           let clip = match.videoClips.first {
            currentResult = match
            currentJobId = match.id
            playingVideoClip = clip
            move(to: .result)
            presentVideoPlayer = true
            return
        }

        if let result = currentResult,
           let clip = playingVideoClip ?? result.videoClips.first {
            playingVideoClip = clip
            move(to: .result)
            presentVideoPlayer = true
        }
    }

    /// Plays a previously directed clip from the scene's clip library.
    func playVideoClip(_ clip: SceneVideoClip) {
        playingVideoClip = clip
        presentVideoPlayer = true
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false

        if let jobId = currentJobId, let api {
            Task {
                if let token = try? await token(using: api) {
                    try? await GenerationService(api: api).cancel(jobId: jobId, token: token)
                }
            }
        }

        move(to: .sceneOptions)
    }

    private func runGeneration(request: GenerationRequest, rerollOf: String?) {
        guard let api else {
            notice = "SceneMe is temporarily unavailable. Please try again later."
            return
        }

        guard let photo = userPhoto else {
            notice = SceneMeAPIError.missingPhoto.errorDescription
            move(to: .home)
            return
        }

        isGenerating = true
        generationProgress = 0
        notice = nil
        move(to: .generating)

        let ownerUserId = session?.userId
        generationTask = Task {
            do {
                let token = try await token(using: api)
                let uploader = ImageUploadService(api: api)

                if userPhotoS3Key == nil {
                    userPhotoS3Key = try await uploader.upload(photo, suggestedCrop: suggestedCrop, token: token)
                }

                if request.hasCompanion, let companionPhoto, companionS3Key == nil {
                    companionS3Key = try await uploader.upload(companionPhoto, suggestedCrop: nil, token: token)
                }

                guard let s3Key = userPhotoS3Key else {
                    throw SceneMeAPIError.missingPhoto
                }

                let service = GenerationService(
                    api: api,
                    appStoreTransactionID: subscriptionService.latestTransactionID
                )
                let result = try await service.generate(
                    request: request,
                    s3Key: s3Key,
                    companionS3Key: request.hasCompanion ? companionS3Key : nil,
                    token: token
                ) { [weak self] progress in
                    self?.generationProgress = progress
                }

                try Task.checkCancellation()
                guard session?.userId == ownerUserId, ownerUserId != nil else { return }

                try await adopt(result: result, forUserId: ownerUserId)
                if session?.userId == ownerUserId {
                    await syncAccountStateFromServer()
                    isGenerating = false
                    move(to: .result)
                }
            } catch is CancellationError {
                isGenerating = false
            } catch SceneMeAPIError.unauthorized {
                isGenerating = false
                forceSignOut()
            } catch {
                guard session?.userId == ownerUserId else { return }
                isGenerating = false
                notice = (error as? LocalizedError)?.errorDescription ?? "Scene generation failed."
                move(to: .sceneOptions)
            }
        }
    }

    private func adopt(result: GenerationResult, forUserId ownerUserId: String?) async throws {
        guard let ownerUserId, session?.userId == ownerUserId else { return }

        currentResult = result
        currentJobId = result.id
        resultImage = try? await downloadImage(result.imageURL)

        history.removeAll { $0.id == result.id }
        history.insert(result, at: 0)
        persistence.saveHistory(history)
    }

    private func token(using api: APIService) async throws -> String {
        guard let current = session else {
            throw SceneMeAPIError.unauthorized
        }
        if let expiration = Self.accessTokenExpiration(current.accessToken),
           expiration.timeIntervalSinceNow > 120 {
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            // Legacy sessions remain usable until their signed access token
            // expires, then require one fresh sign-in to obtain rotation.
            if let expiration = Self.accessTokenExpiration(current.accessToken), expiration > Date() {
                return current.accessToken
            }
            forceSignOut()
            throw SceneMeAPIError.unauthorized
        }

        if let sessionRefreshTask {
            let refreshed = try await sessionRefreshTask.value
            return refreshed.accessToken
        }

        let task = Task<SceneMeSession, Error> {
            let auth = try await api.refreshSession(refreshToken: refreshToken)
            return SceneMeSession(
                userId: auth.userId,
                email: auth.email,
                fullName: auth.fullName,
                accessToken: auth.accessToken,
                refreshToken: auth.refreshToken
            )
        }
        sessionRefreshTask = task
        defer { sessionRefreshTask = nil }

        do {
            let refreshed = try await task.value
            guard refreshed.userId == current.userId else {
                forceSignOut()
                throw SceneMeAPIError.unauthorized
            }
            sessionStore.save(refreshed)
            session = refreshed
            return refreshed.accessToken
        } catch let error as SceneMeAPIError {
            if case .backendUnreachable = error {
                // Keep the valid Keychain session during temporary connectivity
                // loss; the next protected action/foreground refresh can retry.
                throw error
            }
            forceSignOut()
            throw SceneMeAPIError.unauthorized
        } catch {
            forceSignOut()
            throw SceneMeAPIError.unauthorized
        }
    }

    private static func accessTokenExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload.append(String(repeating: "=", count: (4 - payload.count % 4) % 4))
        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let expiry = object["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: expiry)
    }

    private func downloadImage(_ url: URL) async throws -> UIImage? {
        let (data, _) = try await URLSession.shared.data(from: url)
        return UIImage(data: data)
    }

    // MARK: - Favorites

    func toggleFavorite(_ result: GenerationResult) {
        if favoriteIds.contains(result.id) {
            favoriteIds.remove(result.id)
        } else {
            favoriteIds.insert(result.id)
        }
        persistence.saveFavorites(favoriteIds)
    }

    func isFavorite(_ result: GenerationResult) -> Bool {
        favoriteIds.contains(result.id)
    }

    // MARK: - Deletion

    /// Removes a generation from history and favorites, and cleans up the
    /// job on the backend (best effort).
    func deleteResult(_ result: GenerationResult) {
        history.removeAll { $0.id == result.id }
        favoriteIds.remove(result.id)
        persistence.saveHistory(history)
        persistence.saveFavorites(favoriteIds)

        if currentResult?.id == result.id {
            currentResult = nil
            resultImage = nil
            currentJobId = nil
            if flow == .result {
                move(to: .home)
            }
        }

        if let api {
            Task {
                if let token = try? await token(using: api) {
                    try? await GenerationService(api: api).cancel(jobId: result.id, token: token)
                }
            }
        }

        notice = "Scene deleted."
    }

    // MARK: - Result helpers

    func openResult(_ result: GenerationResult) {
        currentResult = result
        currentJobId = result.id
        resultImage = nil
        if let scene = scene(forId: result.sceneId) {
            var rebuilt = GenerationRequest(scene: scene)
            rebuilt.timeOfDay = result.timeOfDay
            rebuilt.weather = result.weather
            rebuilt.pose = result.pose
            request = rebuilt
        } else if result.sceneId.hasPrefix("custom") || result.sceneLocation.lowercased().contains("custom") {
            // Legacy / deleted custom — rebuild a one-shot template so remix still works.
            let recovered = SceneTemplate.custom(
                name: result.sceneName,
                description: "in \(result.sceneName)",
                outfit: ""
            )
            var rebuilt = GenerationRequest(scene: recovered)
            rebuilt.timeOfDay = result.timeOfDay
            rebuilt.weather = result.weather
            rebuilt.pose = result.pose
            request = rebuilt
        }
        move(to: .result)

        Task {
            resultImage = try? await downloadImage(result.imageURL)
        }
    }

    func saveToPhotoLibrary(_ image: UIImage) {
        Task {
            guard await canAddToPhotoLibrary() else { return }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                notice = "Saved to your photo library."
            } catch {
                notice = "SceneMe couldn't save this image. Check Photos access and try again."
            }
        }
    }

    func saveVideoToPhotoLibrary(_ url: URL) {
        Task {
            do {
                let (downloadedURL, response) = try await URLSession.shared.download(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sceneme-\(UUID().uuidString).mp4")
                try FileManager.default.moveItem(at: downloadedURL, to: temporaryURL)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }

                let exportURL = try await SceneMeVideoWatermark.prepareForExport(
                    sourceURL: temporaryURL,
                    apply: !currentTier.removesWatermark
                )
                defer {
                    if exportURL != temporaryURL {
                        try? FileManager.default.removeItem(at: exportURL)
                    }
                }

                guard await canAddToPhotoLibrary() else { return }

                try await PHPhotoLibrary.shared().performChanges {
                    guard PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: exportURL) != nil else {
                        return
                    }
                }
                notice = "Video saved to your photo library."
            } catch {
                notice = "SceneMe couldn't save this video. Check Photos access and try again."
            }
        }
    }

    private func canAddToPhotoLibrary() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status = current == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            : current

        guard status == .authorized || status == .limited else {
            notice = "Allow SceneMe to add photos in Settings to save this creation."
            return false
        }
        return true
    }
}

private struct SceneMeHistoryStore {
    /// Scopes the on-disk files per account, so two users on the same
    /// device never see each other's generations, photo, or favorites.
    let userId: String?

    private var suffix: String {
        userId.map { "-\($0)" } ?? ""
    }

    private var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private var historyURL: URL? {
        directory?.appendingPathComponent("sceneme-generations\(suffix).json")
    }

    private var favoritesURL: URL? {
        directory?.appendingPathComponent("sceneme-favorites\(suffix).json")
    }

    private var photoURL: URL? {
        guard userId != nil else { return nil }
        return directory?.appendingPathComponent("sceneme-photo\(suffix).jpg")
    }

    private var customScenesURL: URL? {
        directory?.appendingPathComponent("sceneme-custom-scenes\(suffix).json")
    }

    func loadHistory() -> [GenerationResult] {
        guard
            let historyURL,
            let data = try? Data(contentsOf: historyURL),
            let results = try? decoder().decode([GenerationResult].self, from: data)
        else {
            return []
        }
        return results
    }

    func saveHistory(_ results: [GenerationResult]) {
        guard let historyURL, userId != nil else { return }
        write(try? encoder().encode(results), to: historyURL)
    }

    func loadFavorites() -> Set<String> {
        guard
            let favoritesURL,
            let data = try? Data(contentsOf: favoritesURL),
            let ids = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            return []
        }
        return ids
    }

    func saveFavorites(_ ids: Set<String>) {
        guard let favoritesURL, userId != nil else { return }
        write(try? JSONEncoder().encode(ids), to: favoritesURL)
    }

    func loadPhoto() -> UIImage? {
        guard let photoURL, let data = try? Data(contentsOf: photoURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    func savePhoto(_ image: UIImage?) {
        guard let photoURL, userId != nil else { return }
        if let image, let data = image.jpegData(compressionQuality: 0.9) {
            write(data, to: photoURL)
        } else {
            try? FileManager.default.removeItem(at: photoURL)
        }
    }

    func loadCustomScenes() -> [SceneTemplate] {
        guard
            let customScenesURL,
            let data = try? Data(contentsOf: customScenesURL),
            let scenes = try? decoder().decode([SceneTemplate].self, from: data)
        else {
            return []
        }
        return scenes
    }

    func saveCustomScenes(_ scenes: [SceneTemplate]) {
        guard let customScenesURL, userId != nil else { return }
        write(try? encoder().encode(scenes), to: customScenesURL)
    }

    /// Permanently removes this account's local history, favorites, photo, and custom scenes.
    func wipeAll() {
        for url in [historyURL, favoritesURL, photoURL, customScenesURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func write(_ data: Data?, to url: URL) {
        guard let data else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic])
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
