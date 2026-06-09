import CoreVideo
import UIKit
import Vision

final class VisionStyleIAImageAnalyzer: StyleIAImageAnalyzing, @unchecked Sendable {
    func validate(_ image: UIImage) async throws -> StyleIAImageValidationResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.analyze(image)
        }.value
    }

    private static func analyze(_ image: UIImage) throws -> StyleIAImageValidationResult {
        guard let cgImage = image.cgImage ?? image.normalizedCGImage() else {
            throw StyleIAImageProcessingError.unreadableImage
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = false

        let faceRequest = VNDetectFaceRectanglesRequest()
        let poseRequest = VNDetectHumanBodyPoseRequest()

        var segmentationMask: VNPixelBufferObservation?
        if #available(iOS 15.0, *) {
            let segmentationRequest = VNGeneratePersonSegmentationRequest()
            segmentationRequest.qualityLevel = .balanced
            try handler.perform([humanRequest, faceRequest, poseRequest, segmentationRequest])
            segmentationMask = segmentationRequest.results?.first
        } else {
            try handler.perform([humanRequest, faceRequest, poseRequest])
        }

        let humanBoxes = (humanRequest.results ?? []).map { visionRectToUIKit($0.boundingBox) }
        let faceBoxes = (faceRequest.results ?? []).map { visionRectToUIKit($0.boundingBox) }
        let poseObservations = poseRequest.results ?? []

        let segmentationBox = segmentationMask.flatMap(personBoundingBox(from:))
        let humanUnion = StyleIAImageValidationPolicy.unionBoundingBox(humanBoxes)
        let faceUnion = StyleIAImageValidationPolicy.unionBoundingBox(faceBoxes)
        let personBoundingBox = StyleIAImageValidationPolicy.unionBoundingBox(
            [humanUnion, faceUnion, segmentationBox].compactMap { $0 }
        )

        let humanConfidence = averageConfidence(humanRequest.results?.map(\.confidence) ?? [])
        let faceConfidence = averageConfidence(faceRequest.results?.map(\.confidence) ?? [])

        let signals = StyleIAImageValidationPolicy.Signals(
            humanCount: humanBoxes.count,
            humanConfidence: humanConfidence,
            faceCount: faceBoxes.count,
            faceConfidence: faceConfidence,
            personBoundingBox: personBoundingBox,
            hasPose: !poseObservations.isEmpty,
            isSimulator: ProcessInfo.processInfo.isiOSAppOnMac || isSimulatorEnvironment()
        )

        return StyleIAImageValidationPolicy.evaluate(signals)
    }

    private static func averageConfidence(_ values: [Float]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func visionRectToUIKit(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: 1 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    @available(iOS 15.0, *)
    private static func personBoundingBox(from observation: VNPixelBufferObservation) -> CGRect? {
        let pixelBuffer = observation.pixelBuffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
            width > 0,
            height > 0
        else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in 0..<height {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                if row[x] > 96 {
                    found = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard found, maxX > minX, maxY > minY else { return nil }

        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height)
        )
    }

    private static func isSimulatorEnvironment() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

private extension UIImage {
    func normalizedCGImage() -> CGImage? {
        guard imageOrientation != .up else { return cgImage }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
