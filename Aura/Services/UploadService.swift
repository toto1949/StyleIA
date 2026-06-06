import Foundation
import UIKit

struct PresignUploadResponse: Decodable {
    let uploadURL: String
    let s3Key: String
}

nonisolated final class UploadProgressEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Double>.Continuation] = [:]

    func stream() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    func send(_ value: Double) {
        let activeContinuations = currentContinuations()
        activeContinuations.forEach { $0.yield(value) }
    }

    func finish() {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        activeContinuations.forEach { $0.finish() }
    }

    private func currentContinuations() -> [AsyncStream<Double>.Continuation] {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        lock.unlock()
        return activeContinuations
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}

nonisolated final class URLSessionTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?

    func set(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

struct UploadService {
    private let apiService: APIService
    private let compressor: ImageCompressor
    private let session: URLSession
    private let progressEmitter: UploadProgressEmitter

    init(
        apiService: APIService,
        compressor: ImageCompressor = ImageCompressor(),
        session: URLSession = .shared,
        progressEmitter: UploadProgressEmitter = UploadProgressEmitter()
    ) {
        self.apiService = apiService
        self.compressor = compressor
        self.session = session
        self.progressEmitter = progressEmitter
    }

    func uploadProgress() -> AsyncStream<Double> {
        progressEmitter.stream()
    }

    func upload(image: UIImage) async throws -> String {
        let data = try compressor.compressedJPEGData(from: image)
        let presign: PresignUploadResponse = try await apiService.request(
            Endpoint(path: "/upload/presign", method: .post)
        )

        guard let uploadURL = URL(string: presign.uploadURL) else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = HTTPMethod.put.rawValue
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        try await upload(data: data, request: request)
        progressEmitter.send(1)
        progressEmitter.finish()
        return presign.s3Key
    }

    private func upload(data: Data, request: URLRequest) async throws {
        let taskBox = URLSessionTaskBox()
        var observation: NSKeyValueObservation?

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.uploadTask(with: request, from: data) { _, response, error in
                    observation?.invalidate()

                    if let error {
                        if let urlError = error as? URLError, urlError.code == .cancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: APIError.networkError)
                        }
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.resume(throwing: APIError.networkError)
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        continuation.resume(throwing: APIError.serverError(message: nil))
                        return
                    }

                    continuation.resume()
                }

                observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                    progressEmitter.send(progress.fractionCompleted)
                }

                taskBox.set(task)
                task.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }
}
