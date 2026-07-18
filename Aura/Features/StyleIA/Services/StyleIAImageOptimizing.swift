import UIKit

protocol StyleIAImageOptimizing: Sendable {
    func optimize(_ image: UIImage, suggestedCrop: CGRect?) async throws -> StyleIAOptimizedImage
}

nonisolated struct StyleIAImageOptimizationSettings: Equatable, Sendable {
    let maxLongEdge: CGFloat
    let targetMaxBytes: Int
    let initialJPEGQuality: CGFloat
    let minimumJPEGQuality: CGFloat
    let darkImageBrightnessThreshold: CGFloat
    let exposureEV: Float

    static let `default` = StyleIAImageOptimizationSettings(
        maxLongEdge: 2048,
        // Keep more detail for Kontext face lock; fal charges per image, not upload size.
        targetMaxBytes: 3_000_000,
        initialJPEGQuality: 0.90,
        minimumJPEGQuality: 0.74,
        darkImageBrightnessThreshold: 0.28,
        exposureEV: 0.22
    )
}
