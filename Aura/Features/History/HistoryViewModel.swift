import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class HistoryViewModel {
    var records: [GenerationRecord] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var recordPendingDeletion: GenerationRecord?
    var shareItems: [Any] = []

    private let historyService: HistoryService
    private let imageCache: ImageCacheService
    private let haptics: HapticManager
    private let crashReporter: CrashReporting
    private var page = 1
    private var hasMore = true

    init(container: DependencyContainer) {
        historyService = container.historyService
        imageCache = container.imageCacheService
        haptics = container.haptics
        crashReporter = container.crashReporter
        records = historyService.localRecords()
    }

    func loadInitial() {
        guard !isLoading else { return }
        Task {
            isLoading = true
            errorMessage = nil
            page = 1
            hasMore = true
            defer { isLoading = false }

            do {
                let remote = try await historyService.fetchRemote(page: page)
                records = remote.sorted { $0.createdAt > $1.createdAt }
                hasMore = remote.count == 20
            } catch {
                crashReporter.record(error: error)
                records = historyService.localRecords()
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        page = 1
        hasMore = true
        defer { isLoading = false }

        do {
            let remote = try await historyService.fetchRemote(page: page)
            records = remote.sorted { $0.createdAt > $1.createdAt }
            hasMore = remote.count == 20
        } catch {
            crashReporter.record(error: error)
            errorMessage = ErrorMessageMapper.message(for: error)
        }
    }

    func loadMoreIfNeeded(current record: GenerationRecord) {
        guard hasMore, !isLoadingMore, records.last?.id == record.id else {
            return
        }

        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }

            do {
                let nextPage = page + 1
                let remote = try await historyService.fetchRemote(page: nextPage)
                let existingIDs = Set(records.map(\.id))
                records.append(contentsOf: remote.filter { !existingIDs.contains($0.id) })
                records.sort { $0.createdAt > $1.createdAt }
                page = nextPage
                hasMore = remote.count == 20
            } catch {
                crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    func confirmDelete(_ record: GenerationRecord) {
        recordPendingDeletion = record
    }

    func deletePendingRecord() {
        guard let record = recordPendingDeletion else {
            return
        }

        Task {
            do {
                try await historyService.deleteRemote(jobId: record.jobId)
                haptics.deleteConfirmed()
                historyService.deleteLocally(id: record.id)
                records.removeAll { $0.id == record.id }
                recordPendingDeletion = nil
            } catch {
                crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    func prepareShare(record: GenerationRecord) async {
        if let image = await image(for: record) {
            shareItems = [image]
        } else {
            errorMessage = L10n.string("results.imageUnavailable")
        }
    }

    func save(record: GenerationRecord) {
        Task {
            guard let image = await image(for: record) else {
                errorMessage = L10n.string("results.imageUnavailable")
                return
            }

            do {
                try await requestPhotoWritePermissionIfNeeded()
                try await save(image: image)
                haptics.saveSucceeded()
            } catch {
                crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    private func image(for record: GenerationRecord) async -> UIImage? {
        if let image = UIImage(data: record.thumbnailData) {
            return image
        }

        guard let firstURLString = record.resultURLs.first, let url = URL(string: firstURLString) else {
            return nil
        }

        return try? await imageCache.load(url: url)
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
}
