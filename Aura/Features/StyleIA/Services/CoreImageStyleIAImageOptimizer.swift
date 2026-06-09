import CoreImage
import UIKit

final class CoreImageStyleIAImageOptimizer: StyleIAImageOptimizing, @unchecked Sendable {
    private let settings: StyleIAImageOptimizationSettings
    private let context: CIContext

    init(
        settings: StyleIAImageOptimizationSettings = .default,
        context: CIContext = CIContext(options: [.useSoftwareRenderer: false])
    ) {
        self.settings = settings
        self.context = context
    }

    func optimize(_ image: UIImage, suggestedCrop: CGRect?) async throws -> StyleIAOptimizedImage {
        try await Task.detached(priority: .userInitiated) {
            try Self.optimize(
                image,
                suggestedCrop: suggestedCrop,
                settings: self.settings,
                context: self.context
            )
        }.value
    }

    private static func optimize(
        _ image: UIImage,
        suggestedCrop: CGRect?,
        settings: StyleIAImageOptimizationSettings,
        context: CIContext
    ) throws -> StyleIAOptimizedImage {
        guard let source = CIImage(image: image.normalizedUIImage()) else {
            throw StyleIAImageProcessingError.unreadableImage
        }

        let cropped = applyCrop(source, suggestedCrop: suggestedCrop)
        let resized = resize(cropped, maxLongEdge: settings.maxLongEdge)
        let enhanced = applySafeEnhancementIfNeeded(resized, settings: settings, context: context)

        guard let cgImage = context.createCGImage(enhanced, from: enhanced.extent) else {
            throw StyleIAImageProcessingError.optimizationFailed("Could not render optimized image.")
        }

        let optimizedUIImage = UIImage(cgImage: cgImage)
        let data = try jpegData(
            for: optimizedUIImage,
            targetMaxBytes: settings.targetMaxBytes,
            initialQuality: settings.initialJPEGQuality,
            minimumQuality: settings.minimumJPEGQuality
        )

        return StyleIAOptimizedImage(
            data: data,
            contentType: "image/jpeg",
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            byteCount: data.count
        )
    }

    private static func applyCrop(_ image: CIImage, suggestedCrop: CGRect?) -> CIImage {
        guard let crop = suggestedCrop, crop.width > 0.05, crop.height > 0.05 else {
            return image
        }

        let extent = image.extent
        let rect = CGRect(
            x: extent.minX + crop.minX * extent.width,
            y: extent.minY + (1 - crop.maxY) * extent.height,
            width: crop.width * extent.width,
            height: crop.height * extent.height
        ).integral

        return image.cropped(to: rect)
    }

    private static func resize(_ image: CIImage, maxLongEdge: CGFloat) -> CIImage {
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }

        let scale = maxLongEdge / longEdge
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private static func applySafeEnhancementIfNeeded(
        _ image: CIImage,
        settings: StyleIAImageOptimizationSettings,
        context: CIContext
    ) -> CIImage {
        guard averageBrightness(image, context: context) < settings.darkImageBrightnessThreshold else {
            return image
        }

        guard let filter = CIFilter(name: "CIExposureAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(settings.exposureEV, forKey: kCIInputEVKey)
        return filter.outputImage ?? image
    }

    private static func averageBrightness(_ image: CIImage, context: CIContext) -> CGFloat {
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return 1
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)

        guard let output = filter.outputImage else {
            return 1
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let red = CGFloat(pixel[0]) / 255
        let green = CGFloat(pixel[1]) / 255
        let blue = CGFloat(pixel[2]) / 255
        return (red + green + blue) / 3
    }

    private static func jpegData(
        for image: UIImage,
        targetMaxBytes: Int,
        initialQuality: CGFloat,
        minimumQuality: CGFloat
    ) throws -> Data {
        var quality = initialQuality
        var data = image.jpegData(compressionQuality: quality) ?? Data()

        while data.count > targetMaxBytes, quality > minimumQuality {
            quality -= 0.06
            guard let next = image.jpegData(compressionQuality: quality) else {
                throw StyleIAImageProcessingError.optimizationFailed("Could not compress image.")
            }
            data = next
        }

        guard !data.isEmpty else {
            throw StyleIAImageProcessingError.optimizationFailed("Compressed image was empty.")
        }

        return data
    }
}

private extension UIImage {
    func normalizedUIImage() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
