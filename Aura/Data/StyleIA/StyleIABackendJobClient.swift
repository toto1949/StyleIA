import Foundation

enum StyleIABackendError: Error, LocalizedError {
    case missingPhoto
    case invalidResponse
    case localNetworkBlocked(URL)
    case backendUnreachable(URL)
    case failed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingPhoto:
            return "Upload a photo first to run style generation."
        case .invalidResponse:
            return "The backend returned an unexpected response."
        case .localNetworkBlocked(let url):
            return "Local Network is blocked for StyleAI. Enable StyleAI in iPhone Settings > Privacy & Security > Local Network, then retry \(url.host ?? "the backend"). If StyleAI is not listed there, delete the app from the device and install it from Xcode again."
        case .backendUnreachable(let url):
            return "Could not reach the backend at \(url.absoluteString). Make sure the backend is running and your iPhone is on the same Wi-Fi."
        case .failed(let message):
            return message
        case .timedOut:
            return "Style generation timed out. Please try again."
        }
    }
}

struct StyleIABackendJobClient: StyleIAJobPreparing {
    let baseURL: URL
    var session: URLSession = .shared
    var email: String = "styleia-ios-dev@local.test"
    var password: String = "StyleIATest12345"

    private struct AuthRequest: Encodable {
        let email: String
        let password: String
    }

    private struct AuthResponse: Decodable {
        let accessToken: String
    }

    private struct PresignResponse: Decodable {
        let uploadURL: URL
        let s3Key: String
    }

    private struct JobRequest: Encodable {
        let s3Key: String
        let styleGoal: String
        let styleGoals: [String]
        let subjectGender: String
        let styleProfile: StyleIAStyleProfile
        let seed: Int?
    }

    private struct JobResponse: Decodable {
        let jobId: String
        let status: String
        let progress: Int
        let resultURLs: [URL]
        let looks: [StyleIALook]?
        let error: String?
    }

    private struct EmptyBody: Encodable {}

    func prepare(
        _ draft: StyleIAJobDraft,
        photo: StyleIAPhotoPayload?,
        onPartialLooks: @MainActor @escaping ([StyleIALook]) -> Void
    ) async throws -> StyleIAJobReceipt {
        guard let photo else {
            throw StyleIABackendError.missingPhoto
        }

        let token = try await authenticate()
        let upload = try await presignUpload(token: token)
        try await uploadPhoto(photo, to: upload.uploadURL)

        let job = try await createJob(
            token: token,
            s3Key: upload.s3Key,
            styleGoal: draft.styleGoal,
            styleGoals: draft.styleGoals,
            subjectGender: draft.subjectGender,
            styleProfile: draft.styleProfile
        )
        let completedJob = try await waitForCompletion(
            token: token,
            jobId: job.jobId,
            draft: draft,
            onPartialLooks: onPartialLooks
        )

        return StyleIAJobReceipt(
            localJobId: draft.localJobId,
            message: "Style images ready",
            recommendations: nil,
            resultURLs: completedJob.resultURLs,
            looks: completedJob.looks ?? fallbackLooks(from: completedJob.resultURLs, draft: draft)
        )
    }

    private func authenticate() async throws -> String {
        let response: AuthResponse = try await post(
            "auth/email",
            body: AuthRequest(email: email, password: password),
            token: nil
        )
        return response.accessToken
    }

    private func presignUpload(token: String) async throws -> PresignResponse {
        try await post("upload/presign", body: EmptyBody(), token: token)
    }

    private func createJob(
        token: String,
        s3Key: String,
        styleGoal: String,
        styleGoals: [String],
        subjectGender: String,
        styleProfile: StyleIAStyleProfile
    ) async throws -> JobResponse {
        try await post(
            "jobs",
            body: JobRequest(
                s3Key: s3Key,
                styleGoal: styleGoal,
                styleGoals: styleGoals,
                subjectGender: subjectGender,
                styleProfile: styleProfile,
                seed: Int.random(in: 1...999_999_999)
            ),
            token: token
        )
    }

    private func waitForCompletion(
        token: String,
        jobId: String,
        draft: StyleIAJobDraft,
        onPartialLooks: @MainActor @escaping ([StyleIALook]) -> Void
    ) async throws -> JobResponse {
        let startedAt = Date()
        var lastLookIDs: [String] = []

        while Date().timeIntervalSince(startedAt) < 190 {
            let response: JobResponse = try await get("jobs/\(jobId)", token: token)
            let currentLooks = response.looks ?? fallbackLooks(from: response.resultURLs, draft: draft)
            let currentIDs = currentLooks.map(\.id)

            if !currentLooks.isEmpty, currentIDs != lastLookIDs {
                await MainActor.run {
                    onPartialLooks(currentLooks)
                }
                lastLookIDs = currentIDs
            }

            switch response.status {
            case "completed":
                return response
            case "failed":
                throw StyleIABackendError.failed(response.error ?? "Style generation failed.")
            case "cancelled":
                throw StyleIABackendError.failed("Style generation was cancelled.")
            default:
                try await Task.sleep(for: .milliseconds(1_500))
            }
        }

        throw StyleIABackendError.timedOut
    }

    private func uploadPhoto(_ photo: StyleIAPhotoPayload, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(photo.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = photo.data

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        try validate(response: response, data: data)
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        _ path: String,
        body: RequestBody,
        token: String?
    ) async throws -> ResponseBody {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        return try await decode(request)
    }

    private func get<ResponseBody: Decodable>(_ path: String, token: String) async throws -> ResponseBody {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await decode(request)
    }

    private func decode<ResponseBody: Decodable>(_ request: URLRequest) async throws -> ResponseBody {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        try validate(response: response, data: data)
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw StyleIABackendError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            if
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = payload["error"] as? String
            {
                throw StyleIABackendError.failed(message)
            }

            throw StyleIABackendError.failed("Backend request failed with status \(http.statusCode).")
        }
    }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }

    private func fallbackLooks(from urls: [URL], draft: StyleIAJobDraft) -> [StyleIALook] {
        let titles = [
            "Sport Fit",
            "Professional Fit",
            "Casual Fit",
            "Luxury Fit",
            "Streetwear Fit"
        ]
        let subtitles = [
            "Premium active layers",
            "Tailored work polish",
            "Easy everyday style",
            "Editorial evening edge",
            "Layered urban mood"
        ]

        return urls.enumerated().map { index, url in
            StyleIALook(
                id: "\(draft.localJobId)-\(index)",
                styleGoal: draft.styleGoals.indices.contains(index) ? draft.styleGoals[index] : draft.styleGoal,
                title: titles.indices.contains(index) ? titles[index] : "Style Fit",
                subtitle: subtitles.indices.contains(index) ? subtitles[index] : "Generated look",
                imageURL: url,
                assetURLs: StyleIALookAssetURLs(
                    outfit: url,
                    shoes: url,
                    frames: url,
                    accessories: url
                ),
                products: []
            )
        }
    }

    private func mapTransportError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        case .notConnectedToInternet where baseURL.isPrivateNetworkURL:
            return StyleIABackendError.localNetworkBlocked(baseURL)
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
            return StyleIABackendError.backendUnreachable(baseURL)
        default:
            return error
        }
    }
}

private extension URL {
    var isPrivateNetworkURL: Bool {
        guard let host else {
            return false
        }

        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }

        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 {
            return true
        }

        if parts[0] == 172 && (16...31).contains(parts[1]) {
            return true
        }

        if parts[0] == 192 && parts[1] == 168 {
            return true
        }

        return parts[0] == 169 && parts[1] == 254
    }
}
