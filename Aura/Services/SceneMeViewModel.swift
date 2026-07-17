import Combine
import Foundation
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
    @Published var presentVideoPlayer = false
    @Published var generationProgress = 0
    @Published var generatingSceneName = ""
    @Published var notice: String?

    /// Set to show the paywall sheet; cleared on dismiss.
    @Published var paywallTrigger: PaywallTrigger?

    @Published var currentResult: GenerationResult?
    @Published var resultImage: UIImage?
    @Published var history: [GenerationResult] = []
    @Published var favoriteIds: Set<String> = []

    let subscriptionService = SubscriptionService.shared
    private let api: APIService?
    private let analyzer: StyleIAImageAnalyzing
    private let sessionStore = SessionStore()
    private var persistence = SceneMeHistoryStore(userId: nil)
    private var usageCounter: MonthlyUsageCounter?

    private var cancellables = Set<AnyCancellable>()

    private var userPhotoS3Key: String?
    private var companionS3Key: String?
    private var suggestedCrop: CGRect?
    private var generationTask: Task<Void, Never>?
    private var currentJobId: String?

    // MARK: - Subscription convenience

    var currentTier: SubscriptionTier { subscriptionService.tier }

    var generationsRemainingThisMonth: Int? {
        usageCounter?.remaining(for: currentTier)
    }

    var hasReachedGenerationLimit: Bool {
        usageCounter?.hasReachedLimit(for: currentTier) ?? false
    }

    /// Shows the paywall sheet for a locked feature; returns false if user already has access.
    @discardableResult
    func requireTier(_ needed: SubscriptionTier, feature: String) -> Bool {
        guard currentTier < needed else { return false }
        paywallTrigger = .featureLocked(feature: feature, tierNeeded: needed)
        return true
    }

    convenience init() {
        self.init(api: APIService(), analyzer: VisionStyleIAImageAnalyzer())
    }

    init(
        api: APIService?,
        analyzer: StyleIAImageAnalyzing
    ) {
        self.api = api
        self.analyzer = analyzer
        session = sessionStore.load()
        if let session {
            persistence = SceneMeHistoryStore(userId: session.userId)
            usageCounter = MonthlyUsageCounter(userId: session.userId)
            profile = UserProfile(displayName: session.displayName)
        }
        history = persistence.loadHistory()
        favoriteIds = persistence.loadFavorites()

        // Re-render views reading currentTier when entitlements (or the debug
        // override) change, since they observe this view model, not the service.
        subscriptionService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
    }

    func signUp(email: String, password: String, fullName: String) async throws {
        guard let api else {
            throw SceneMeAPIError.failed("SceneMe is temporarily unavailable. Please try again later.")
        }
        adopt(auth: try await api.signUp(email: email, password: password, fullName: fullName))
    }

    func signInWithApple() async throws {
        guard let api else {
            throw SceneMeAPIError.failed("SceneMe is temporarily unavailable. Please try again later.")
        }

        let credential = try await SocialAuthService.shared.signInWithApple()
        adopt(auth: try await api.signInWithApple(
            identityToken: credential.identityToken,
            fullName: credential.fullName
        ))
    }

    func signInWithGoogle() async throws {
        guard let api else {
            throw SceneMeAPIError.failed("SceneMe is temporarily unavailable. Please try again later.")
        }

        let identityToken = try await SocialAuthService.shared.signInWithGoogle()
        adopt(auth: try await api.signInWithGoogle(identityToken: identityToken, fullName: ""))
    }

    func signOut() {
        sessionStore.clear()
        session = nil
        clearPersonalState()
    }

    /// Deletes the account and all server-side data, then signs out locally.
    func deleteAccount() async {
        guard let api, let token = session?.accessToken else {
            signOut()
            return
        }

        do {
            try await api.deleteAccount(token: token)
            signOut()
            notice = "Your account and all data were deleted."
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? "Could not delete your account."
        }
    }

    private func adopt(auth: APIService.AuthResponse) {
        let newSession = SceneMeSession(
            userId: auth.userId,
            email: auth.email,
            fullName: auth.fullName,
            accessToken: auth.accessToken
        )
        sessionStore.save(newSession)
        session = newSession
        profile = UserProfile(displayName: newSession.displayName)
        usageCounter = MonthlyUsageCounter(userId: newSession.userId)
        persistence = SceneMeHistoryStore(userId: newSession.userId)
        history = persistence.loadHistory()
        favoriteIds = persistence.loadFavorites()
        Task { await subscriptionService.refreshEntitlement() }
    }

    /// Called when the backend rejects our token (expired session).
    private func forceSignOut() {
        signOut()
        notice = SceneMeAPIError.unauthorized.errorDescription
    }

    private func clearPersonalState() {
        persistence = SceneMeHistoryStore(userId: nil)
        usageCounter = nil
        history = []
        favoriteIds = []
        profile = .default
        userPhoto = nil
        photoItem = nil
        companionPhoto = nil
        companionItem = nil
        userPhotoS3Key = nil
        companionS3Key = nil
        request = nil
        currentResult = nil
        resultImage = nil
        currentJobId = nil
        flow = .home
        tab = .home
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

    /// Builds a scene from the user's own description and jumps to options.
    func createCustomScene(name: String, description: String, outfit: String) {
        let scene = SceneTemplate.custom(name: name, description: description, outfit: outfit)
        request = GenerationRequest(scene: scene)
        move(to: .sceneOptions)
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
    }

    func removeCompanion() {
        companionPhoto = nil
        companionItem = nil
        companionS3Key = nil
        request?.hasCompanion = false
    }

    // MARK: - Generation

    func startGeneration() {
        guard let request else { return }

        // Check monthly generation limit before starting.
        if hasReachedGenerationLimit {
            let needed: SubscriptionTier = currentTier == .free ? .creator : .pro
            paywallTrigger = .generationLimitReached(remaining: 0, tierNeeded: needed)
            return
        }

        generatingSceneName = request.scene.name
        runGeneration(request: request, rerollOf: nil)
    }

    /// Remix from the result screen: change time/weather and regenerate in place.
    func remix(timeOfDay: TimeOfDay? = nil, weather: WeatherOption? = nil) {
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
        guard let jobId = currentJobId, let api else { return }

        isRerolling = true
        generationTask = Task {
            do {
                let token = try await token(using: api)
                let service = GenerationService(api: api)
                let result = try await service.rerollOutfit(jobId: jobId, token: token) { [weak self] progress in
                    self?.generationProgress = progress
                }
                try await adopt(result: result)
            } catch is CancellationError {
                // User cancelled; nothing to surface.
            } catch SceneMeAPIError.unauthorized {
                forceSignOut()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription ?? "Outfit reroll failed."
            }
            isRerolling = false
        }
    }

    /// Animates the current result with Video Director settings.
    /// Matching style + caption reuses the cached clip; a new direction regenerates.
    func animateScene(motionStyle: VideoMotionStyle, spokenLine: String) {
        if requireTier(.pro, feature: "Video Director") { return }
        guard let result = currentResult else { return }
        guard let api, let jobId = currentJobId else { return }

        isAnimating = true
        Task {
            do {
                let token = try await token(using: api)
                let clip = try await GenerationService(api: api).animate(
                    jobId: jobId,
                    motionStyle: motionStyle,
                    spokenLine: spokenLine,
                    token: token
                ) { _ in }

                var updated = result
                updated.videoURL = clip.videoURL
                updated.videoCaption = clip.caption?.isEmpty == false ? clip.caption : (spokenLine.isEmpty ? nil : spokenLine)
                currentResult = updated
                if let index = history.firstIndex(where: { $0.id == updated.id }) {
                    history[index] = updated
                    persistence.saveHistory(history)
                }
                presentVideoPlayer = true
            } catch is CancellationError {
                // User left the screen; nothing to surface.
            } catch SceneMeAPIError.unauthorized {
                forceSignOut()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription ?? "Video generation failed."
            }
            isAnimating = false
        }
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

                let service = GenerationService(api: api)
                let result = try await service.generate(
                    request: request,
                    s3Key: s3Key,
                    companionS3Key: request.hasCompanion ? companionS3Key : nil,
                    token: token
                ) { [weak self] progress in
                    self?.generationProgress = progress
                }

                try await adopt(result: result)
                usageCounter?.increment()
                isGenerating = false
                move(to: .result)
            } catch is CancellationError {
                isGenerating = false
            } catch SceneMeAPIError.unauthorized {
                isGenerating = false
                forceSignOut()
            } catch {
                isGenerating = false
                notice = (error as? LocalizedError)?.errorDescription ?? "Scene generation failed."
                move(to: .sceneOptions)
            }
        }
    }

    private func adopt(result: GenerationResult) async throws {
        currentResult = result
        currentJobId = result.id
        resultImage = try? await downloadImage(result.imageURL)

        history.removeAll { $0.id == result.id }
        history.insert(result, at: 0)
        persistence.saveHistory(history)
    }

    private func token(using api: APIService) async throws -> String {
        guard let token = session?.accessToken else {
            throw SceneMeAPIError.unauthorized
        }
        return token
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

        if let api, let token = session?.accessToken {
            Task {
                try? await GenerationService(api: api).cancel(jobId: result.id, token: token)
            }
        }

        notice = "Scene deleted."
    }

    // MARK: - Result helpers

    func openResult(_ result: GenerationResult) {
        currentResult = result
        currentJobId = result.id
        resultImage = nil
        if let scene = scenes.first(where: { $0.id == result.sceneId }) {
            var rebuilt = GenerationRequest(scene: scene)
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
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        notice = "Saved to your photo library."
    }

    func saveVideoToPhotoLibrary(_ url: URL) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sceneme-\(UUID().uuidString).mp4")
                try data.write(to: temporaryURL)

                guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(temporaryURL.path) else {
                    notice = "This video format can't be saved to your library."
                    return
                }

                UISaveVideoAtPathToSavedPhotosAlbum(temporaryURL.path, nil, nil, nil)
                notice = "Video saved to your photo library."
            } catch {
                notice = "Could not download the video. Please try again."
            }
        }
    }
}

private struct SceneMeHistoryStore {
    /// Scopes the on-disk files per account, so two users on the same
    /// device never see each other's generations.
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
        guard let historyURL else { return }
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
        guard let favoritesURL else { return }
        write(try? JSONEncoder().encode(ids), to: favoritesURL)
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
