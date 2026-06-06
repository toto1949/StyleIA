import UIKit
import Vision

enum SafetyResult: Equatable {
    case safe
    case noFaceDetected
    case potentiallyUnsafe
}

enum SafetyError: Error {
    case noFaceDetected
    case potentiallyUnsafe
}

struct SafetyService {
    func check(image: UIImage) async -> SafetyResult {
        guard let cgImage = image.normalizedCGImage() else {
            return .potentiallyUnsafe
        }
        let orientation = image.cgImagePropertyOrientation

        return await Task.detached(priority: .userInitiated) { () -> SafetyResult in
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)

            do {
                try handler.perform([request])
            } catch {
                return .potentiallyUnsafe
            }

            guard let observations = request.results, !observations.isEmpty else {
                return .noFaceDetected
            }

            let hasUsableFace = observations.contains { face in
                let area = face.boundingBox.width * face.boundingBox.height
                return area >= 0.025
            }

            return hasUsableFace ? .safe : .potentiallyUnsafe
        }.value
    }
}

private extension UIImage {
    func normalizedCGImage() -> CGImage? {
        if let cgImage {
            return cgImage
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
