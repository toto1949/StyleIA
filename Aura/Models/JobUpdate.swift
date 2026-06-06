import Foundation

struct JobUpdate: Hashable {
    enum Payload: Hashable {
        case progress(percent: Int)
        case completed(resultURLs: [String])
        case failed(error: String)
    }

    let jobId: String
    let payload: Payload
}

struct JobWebSocketMessage: Decodable {
    let type: String
    let percent: Int?
    let resultURLs: [String]?
    let error: String?
}
