import Foundation

enum JobStatus: String, Codable, Hashable {
    case pending
    case processing
    case completed
    case failed
}

struct GenerationJob: Codable, Hashable {
    let jobId: String
    var status: JobStatus
    var progress: Int
    var resultURLs: [String]
    var error: String?

    init(
        jobId: String,
        status: JobStatus,
        progress: Int = 0,
        resultURLs: [String] = [],
        error: String? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.resultURLs = resultURLs
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case progress
        case resultURLs
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(String.self, forKey: .jobId)
        status = try container.decode(JobStatus.self, forKey: .status)
        progress = try container.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        resultURLs = try container.decodeIfPresent([String].self, forKey: .resultURLs) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}
