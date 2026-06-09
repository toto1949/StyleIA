import UIKit

protocol StyleIAImageOptimizing: Sendable {
    func optimize(_ image: UIImage, suggestedCrop: CGRect?) async throws -> StyleIAOptimizedImage
}

struct StyleIAImageOptimizationSettings: Equatable, Sendable {
    let maxLongEdge: CGFloat
    let targetMaxBytes: Int
    let initialJPEGQuality: CGFloat
    let minimumJPEGQuality: CGFloat
    let darkImageBrightnessThreshold: CGFloat
    let exposureEV: Float

    static let `default` = StyleIAImageOptimizationSettings(
        maxLongEdge: 2048,
        targetMaxBytes: 2_500_000,
        initialJPEGQuality: 0.86,
        minimumJPEGQuality: 0.68,
        darkImageBrightnessThreshold: 0.28,
        exposureEV: 0.22
    )
}
