import CoreGraphics
import Foundation

enum StyleIAImageWarning: Equatable, Sendable {
    case noFaceDetected
    case multipleFacesDetected(count: Int)
    case multiplePeopleDetected(count: Int)
    case personTooSmall
    case lowConfidence(Double)
    case offCenterSubject
    case poseNotDetected
    case simulatorLimitedAnalysis

    var message: String {
        switch self {
        case .noFaceDetected:
            return "We couldn't clearly detect a face. A front-facing portrait works best."
        case .multipleFacesDetected(let count):
            return "We detected \(count) faces. One person in frame gives the best results."
        case .multiplePeopleDetected(let count):
            return "We detected \(count) people. Try a photo with just you in frame."
        case .personTooSmall:
            return "The person looks small in this photo. Move closer or crop tighter."
        case .lowConfidence(let confidence):
            return "Photo quality looks uncertain (\(Int(confidence * 100))% confidence). A clearer shot may help."
        case .offCenterSubject:
            return "Try centering yourself in the frame for more consistent styling."
        case .poseNotDetected:
            return "We couldn't detect body pose. A full or upper-body shot usually works better."
        case .simulatorLimitedAnalysis:
            return "Simulator photo checks are limited. Test on a real device for best validation."
        }
    }
}

struct StyleIAImageValidationResult: Equatable, Sendable {
    let isValid: Bool
    let confidence: Double
    let warnings: [StyleIAImageWarning]
    /// Normalized rect in UIKit coordinates (origin top-left, 0...1).
    let suggestedCropRect: CGRect?
    /// Normalized rect in UIKit coordinates (origin top-left, 0...1).
    let personBoundingBox: CGRect?
}

struct StyleIAOptimizedImage: Equatable, Sendable {
    let data: Data
    let contentType: String
    let pixelSize: CGSize
    let byteCount: Int
}

enum StyleIAImageProcessingError: Error, LocalizedError, Equatable {
    case missingImage
    case unreadableImage
    case analysisFailed(String)
    case optimizationFailed(String)
    case photoRejected

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "Upload a photo first to run style generation."
        case .unreadableImage:
            return "We couldn't read that photo. Try choosing a different image."
        case .analysisFailed(let detail):
            return "Photo analysis failed. \(detail)"
        case .optimizationFailed(let detail):
            return "Photo optimization failed. \(detail)"
        case .photoRejected:
            return "Please upload a clear front-facing photo with one person visible."
        }
    }
}

/// Pure validation rules used by Vision analysis and unit tests.
enum StyleIAImageValidationPolicy {
    struct Signals: Equatable, Sendable {
        let humanCount: Int
        let humanConfidence: Double
        let faceCount: Int
        let faceConfidence: Double
        let personBoundingBox: CGRect?
        let hasPose: Bool
        let isSimulator: Bool
    }

    static let minimumPersonArea: CGFloat = 0.08
    static let minimumValidityConfidence: Double = 0.45
    static let offCenterThreshold: CGFloat = 0.18

    static func evaluate(_ signals: Signals) -> StyleIAImageValidationResult {
        var warnings: [StyleIAImageWarning] = []
        var confidence = combinedConfidence(from: signals)

        if signals.isSimulator, signals.humanCount == 0, signals.faceCount == 0 {
            warnings.append(.simulatorLimitedAnalysis)
            return StyleIAImageValidationResult(
                isValid: true,
                confidence: max(confidence, 0.5),
                warnings: warnings,
                suggestedCropRect: signals.personBoundingBox,
                personBoundingBox: signals.personBoundingBox
            )
        }

        if signals.humanCount == 0, signals.faceCount == 0 {
            return invalidResult(
                confidence: confidence,
                warnings: warnings,
                personBoundingBox: signals.personBoundingBox
            )
        }

        if signals.humanCount > 1 {
            warnings.append(.multiplePeopleDetected(count: signals.humanCount))
            confidence -= 0.12
        }

        if signals.faceCount == 0 {
            warnings.append(.noFaceDetected)
            confidence -= 0.18
        } else if signals.faceCount > 1 {
            warnings.append(.multipleFacesDetected(count: signals.faceCount))
            confidence -= 0.15
        }

        if let box = signals.personBoundingBox {
            let area = box.width * box.height
            if area < minimumPersonArea {
                warnings.append(.personTooSmall)
                confidence -= 0.2
            }

            if isOffCenter(box) {
                warnings.append(.offCenterSubject)
                confidence -= 0.05
            }
        }

        if !signals.hasPose, signals.humanCount > 0 {
            warnings.append(.poseNotDetected)
            confidence -= 0.04
        }

        confidence = min(max(confidence, 0), 1)

        if confidence < minimumValidityConfidence {
            warnings.append(.lowConfidence(confidence))
        }

        let hasSubject = signals.humanCount > 0 || signals.faceCount > 0
        let hasStrongFace = signals.faceCount == 1 && signals.faceConfidence >= 0.55
        let hasStrongHuman = signals.humanCount >= 1 && signals.humanConfidence >= 0.5
        let personLargeEnough: Bool
        if let box = signals.personBoundingBox {
            personLargeEnough = (box.width * box.height) >= minimumPersonArea
        } else {
            personLargeEnough = signals.faceCount > 0
        }

        let isValid = hasSubject
            && (hasStrongFace || hasStrongHuman)
            && personLargeEnough
            && confidence >= minimumValidityConfidence
            && signals.humanCount <= 2

        if !isValid {
            return invalidResult(
                confidence: confidence,
                warnings: warnings,
                personBoundingBox: signals.personBoundingBox
            )
        }

        return StyleIAImageValidationResult(
            isValid: true,
            confidence: confidence,
            warnings: warnings,
            suggestedCropRect: suggestedCropRect(for: signals.personBoundingBox),
            personBoundingBox: signals.personBoundingBox
        )
    }

    static func suggestedCropRect(for personBox: CGRect?, padding: CGFloat = 0.08) -> CGRect? {
        guard let personBox else { return nil }

        let expanded = personBox.insetBy(dx: -personBox.width * padding, dy: -personBox.height * padding)
        return clampNormalizedRect(expanded)
    }

    static func unionBoundingBox(_ boxes: [CGRect]) -> CGRect? {
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    static func clampNormalizedRect(_ rect: CGRect) -> CGRect {
        let minX = max(0, min(1, rect.minX))
        let minY = max(0, min(1, rect.minY))
        let maxX = max(minX, min(1, rect.maxX))
        let maxY = max(minY, min(1, rect.maxY))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func combinedConfidence(from signals: Signals) -> Double {
        var values: [Double] = []
        if signals.humanCount > 0 {
            values.append(signals.humanConfidence)
        }
        if signals.faceCount > 0 {
            values.append(signals.faceConfidence)
        }
        if values.isEmpty {
            return 0
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func isOffCenter(_ box: CGRect) -> Bool {
        let center = CGPoint(x: box.midX, y: box.midY)
        return abs(center.x - 0.5) > offCenterThreshold || abs(center.y - 0.5) > offCenterThreshold
    }

    private static func invalidResult(
        confidence: Double,
        warnings: [StyleIAImageWarning],
        personBoundingBox: CGRect?
    ) -> StyleIAImageValidationResult {
        StyleIAImageValidationResult(
            isValid: false,
            confidence: confidence,
            warnings: warnings,
            suggestedCropRect: suggestedCropRect(for: personBoundingBox),
            personBoundingBox: personBoundingBox
        )
    }
}
