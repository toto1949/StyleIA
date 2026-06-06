import Foundation
import UIKit

final class ImageCacheService {
    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 180
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func load(url: URL) async throws -> UIImage {
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await withTaskCancellationHandler {
                try await session.data(from: url)
            } onCancel: {
            }
        } catch {
            if error is CancellationError {
                throw error
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw APIError.networkError
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            let image = UIImage(data: data)
        else {
            throw APIError.networkError
        }

        cache.setObject(image, forKey: url as NSURL, cost: data.count)
        return image
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = image.pngData()?.count ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func prefetch(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = try? await self.load(url: url)
                }
            }
        }
    }
}
