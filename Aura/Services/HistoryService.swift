import Foundation
import SwiftData
import UIKit

@MainActor
final class HistoryService {
    private let apiService: APIService
    private let imageCache: ImageCacheService
    private let modelContext: ModelContext

    init(
        apiService: APIService,
        imageCache: ImageCacheService,
        modelContext: ModelContext
    ) {
        self.apiService = apiService
        self.imageCache = imageCache
        self.modelContext = modelContext
    }

    func fetchRemote(page: Int) async throws -> [GenerationRecord] {
        let response: HistoryResponse = try await apiService.request(
            Endpoint(
                path: "/history",
                method: .get,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "limit", value: "20")
                ]
            )
        )

        var records: [GenerationRecord] = []

        for item in response.items {
            let thumbnailData = await thumbnailData(for: item)
            let record = item.makeRecord(thumbnailData: thumbnailData)
            saveLocally(record)
            records.append(record)
        }

        let thumbnailURLs = response.items.compactMap { item -> URL? in
            let candidate = item.thumbnailURL ?? item.resultURLs.first
            guard let candidate else { return nil }
            return URL(string: candidate)
        }
        await imageCache.prefetch(urls: thumbnailURLs)

        return records
    }

    func saveLocally(_ record: GenerationRecord) {
        if let existing = existingRecord(jobId: record.jobId) {
            existing.styleGoal = record.styleGoal
            existing.thumbnailData = record.thumbnailData
            existing.resultURLs = record.resultURLs
            existing.originalPhotoURL = record.originalPhotoURL
            existing.createdAt = record.createdAt
            existing.isSaved = record.isSaved
        } else {
            modelContext.insert(record)
        }

        try? modelContext.save()
    }

    func deleteLocally(id: UUID) {
        let descriptor = FetchDescriptor<GenerationRecord>(
            predicate: #Predicate { record in
                record.id == id
            }
        )

        if let record = try? modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try? modelContext.save()
        }
    }

    func deleteRemote(jobId: String) async throws {
        let _: DeleteResponse = try await apiService.request(
            Endpoint(path: "/jobs/\(jobId)", method: .delete)
        )
    }

    func localRecords() -> [GenerationRecord] {
        let descriptor = FetchDescriptor<GenerationRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func deleteAllLocal() {
        for record in localRecords() {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private func existingRecord(jobId: String) -> GenerationRecord? {
        let descriptor = FetchDescriptor<GenerationRecord>(
            predicate: #Predicate { record in
                record.jobId == jobId
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func thumbnailData(for item: GenerationRecordDTO) async -> Data {
        let candidate = item.thumbnailURL ?? item.resultURLs.first
        guard let candidate, let url = URL(string: candidate) else {
            return Data()
        }

        guard let image = try? await imageCache.load(url: url) else {
            return Data()
        }

        return image.jpegData(compressionQuality: 0.7) ?? Data()
    }
}
