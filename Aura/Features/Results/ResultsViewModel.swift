import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class ResultsViewModel {
    var selectedIndex = 0
    var isLoading = false
    var errorMessage: String?
    var originalImage: UIImage?
    var resultImages: [Int: UIImage] = [:]
    var showRegenerateSheet = false

    let input: ResultsInput
    let imageCache: ImageCacheService
    private let historyService: HistoryService
    private let coordinator: AppCoordinator
    private let haptics: HapticManager
    private let crashReporter: CrashReporting
    private var hasSavedHistory = false

    init(input: ResultsInput, container: DependencyContainer, coordinator: AppCoordinator) {
        self.input = input
        imageCache = container.imageCacheService
        historyService = container.historyService
        haptics = container.haptics
        crashReporter = container.crashReporter
        self.coordinator = coordinator
        originalImage = input.originalImage
    }

    var resultURLs: [URL] {
        input.resultURLs.compactMap { URL(string: $0) }
    }

    var currentResultImage: UIImage? {
        resultImages[selectedIndex]
    }

    var canRegenerate: Bool {
        !input.readOnly
    }

    func load() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            if originalImage == nil, let originalURL = URL(string: input.originalPhotoURL) {
                originalImage = try? await imageCache.load(url: originalURL)
            }

            await loadResult(at: selectedIndex)
            await imageCache.prefetch(urls: resultURLs)
        }
    }

    func selectedVariantChanged() {
        Task {
            await loadResult(at: selectedIndex)
        }
    }

    func saveCurrentImageToPhotos() {
        guard let image = currentResultImage else {
            errorMessage = L10n.string("results.imageUnavailable")
            return
        }

        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                try await requestPhotoWritePermissionIfNeeded()
                try await save(image: image)
                haptics.saveSucceeded()
                markRecordSaved()
            } catch {
                crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    func shareItems() -> [Any] {
        guard let image = currentResultImage else {
            return []
        }
        return [image]
    }

    func saveHistoryIfNeeded() {
        guard !input.readOnly, !hasSavedHistory else {
            return
        }

        let thumbnailImage = resultImages[0] ?? currentResultImage
        let thumbnailData = thumbnailImage?.jpegData(compressionQuality: 0.72) ?? Data()
        let record = GenerationRecord(
            jobId: input.jobId,
            styleGoal: input.styleGoal,
            thumbnailData: thumbnailData,
            resultURLs: input.resultURLs,
            originalPhotoURL: input.originalPhotoURL,
            createdAt: Date(),
            isSaved: false
        )
        historyService.saveLocally(record)
        hasSavedHistory = true
    }

    func regenerateSameStyle() {
        saveHistoryIfNeeded()
        coordinator.regenerateSameStyle()
    }

    func chooseDifferentStyle() {
        saveHistoryIfNeeded()
        coordinator.chooseDifferentStyle()
    }

    private func loadResult(at index: Int) async {
        guard resultImages[index] == nil, resultURLs.indices.contains(index) else {
            return
        }

        do {
            resultImages[index] = try await imageCache.load(url: resultURLs[index])
        } catch {
            crashReporter.record(error: error)
            errorMessage = ErrorMessageMapper.message(for: error)
        }
    }

    private func requestPhotoWritePermissionIfNeeded() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if newStatus == .authorized || newStatus == .limited {
                return
            }
            throw APIError.unauthorized
        case .denied, .restricted:
            throw APIError.unauthorized
        @unknown default:
            throw APIError.unauthorized
        }
    }

    private func save(image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: APIError.serverError(message: nil))
                }
            }
        }
    }

    private func markRecordSaved() {
        hasSavedHistory = true
        let thumbnailImage = resultImages[0] ?? currentResultImage
        let thumbnailData = thumbnailImage?.jpegData(compressionQuality: 0.72) ?? Data()
        let record = GenerationRecord(
            jobId: input.jobId,
            styleGoal: input.styleGoal,
            thumbnailData: thumbnailData,
            resultURLs: input.resultURLs,
            originalPhotoURL: input.originalPhotoURL,
            createdAt: Date(),
            isSaved: true
        )
        historyService.saveLocally(record)
    }
}
