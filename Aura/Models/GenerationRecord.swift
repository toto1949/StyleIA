import Foundation
import SwiftData

@Model
final class GenerationRecord {
    @Attribute(.unique) var id: UUID
    var jobId: String
    var styleGoal: StyleGoal
    var thumbnailData: Data
    var resultURLs: [String]
    var originalPhotoURL: String
    var createdAt: Date
    var isSaved: Bool

    init(
        id: UUID = UUID(),
        jobId: String,
        styleGoal: StyleGoal,
        thumbnailData: Data,
        resultURLs: [String],
        originalPhotoURL: String,
        createdAt: Date = Date(),
        isSaved: Bool = false
    ) {
        self.id = id
        self.jobId = jobId
        self.styleGoal = styleGoal
        self.thumbnailData = thumbnailData
        self.resultURLs = resultURLs
        self.originalPhotoURL = originalPhotoURL
        self.createdAt = createdAt
        self.isSaved = isSaved
    }
}

struct HistoryResponse: Decodable {
    let items: [GenerationRecordDTO]
    let total: Int
}

struct GenerationRecordDTO: Decodable, Hashable {
    let id: UUID
    let jobId: String
    let styleGoal: StyleGoal
    let thumbnailURL: String?
    let resultURLs: [String]
    let originalPhotoURL: String
    let createdAt: Date
    let isSaved: Bool?

    func makeRecord(thumbnailData: Data) -> GenerationRecord {
        GenerationRecord(
            id: id,
            jobId: jobId,
            styleGoal: styleGoal,
            thumbnailData: thumbnailData,
            resultURLs: resultURLs,
            originalPhotoURL: originalPhotoURL,
            createdAt: createdAt,
            isSaved: isSaved ?? false
        )
    }
}
