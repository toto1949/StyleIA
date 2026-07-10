import UIKit

/// Optimizes a photo and uploads it through the backend's presigned upload flow.
struct ImageUploadService {
    let api: APIService
    var optimizer: StyleIAImageOptimizing = CoreImageStyleIAImageOptimizer()

    private struct PresignResponse: Decodable {
        let uploadURL: URL
        let s3Key: String
    }

    /// Returns the backend `s3Key` for the uploaded photo.
    func upload(_ image: UIImage, suggestedCrop: CGRect?, token: String) async throws -> String {
        let optimized = try await optimizer.optimize(image, suggestedCrop: suggestedCrop)
        let presign: PresignResponse = try await api.post("upload/presign", body: APIService.EmptyBody(), token: token)
        try await api.upload(data: optimized.data, contentType: optimized.contentType, to: presign.uploadURL)
        return presign.s3Key
    }
}
