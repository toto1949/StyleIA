import CoreGraphics
import Testing
@testable import Aura

struct StyleIAImageValidationPolicyTests {
    @Test func rejectsEmptyPhotoOnDevice() {
        let result = StyleIAImageValidationPolicy.evaluate(
            .init(
                humanCount: 0,
                humanConfidence: 0,
                faceCount: 0,
                faceConfidence: 0,
                personBoundingBox: nil,
                hasPose: false,
                isSimulator: false
            )
        )

        #expect(result.isValid == false)
        #expect(result.confidence == 0)
    }

    @Test func allowsSimulatorFallbackWhenVisionFindsNothing() {
        let result = StyleIAImageValidationPolicy.evaluate(
            .init(
                humanCount: 0,
                humanConfidence: 0,
                faceCount: 0,
                faceConfidence: 0,
                personBoundingBox: nil,
                hasPose: false,
                isSimulator: true
            )
        )

        #expect(result.isValid == true)
        #expect(result.warnings.contains(.simulatorLimitedAnalysis))
    }

    @Test func acceptsSingleFaceWithLargeSubject() {
        let box = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        let result = StyleIAImageValidationPolicy.evaluate(
            .init(
                humanCount: 1,
                humanConfidence: 0.82,
                faceCount: 1,
                faceConfidence: 0.9,
                personBoundingBox: box,
                hasPose: true,
                isSimulator: false
            )
        )

        #expect(result.isValid == true)
        #expect(result.personBoundingBox == box)
        #expect(result.suggestedCropRect != nil)
    }

    @Test func rejectsTinySubject() {
        let tinyBox = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let result = StyleIAImageValidationPolicy.evaluate(
            .init(
                humanCount: 1,
                humanConfidence: 0.7,
                faceCount: 1,
                faceConfidence: 0.7,
                personBoundingBox: tinyBox,
                hasPose: false,
                isSimulator: false
            )
        )

        #expect(result.isValid == false)
        #expect(result.warnings.contains(.personTooSmall))
    }

    @Test func unionBoundingBoxCombinesRegions() {
        let first = CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3)
        let second = CGRect(x: 0.25, y: 0.15, width: 0.3, height: 0.4)
        let union = StyleIAImageValidationPolicy.unionBoundingBox([first, second])

        #expect(union == first.union(second))
    }

    @Test func suggestedCropAddsPaddingAndClamps() {
        let box = CGRect(x: 0.02, y: 0.02, width: 0.4, height: 0.9)
        let crop = StyleIAImageValidationPolicy.suggestedCropRect(for: box)

        #expect(crop != nil)
        #expect(crop?.minX == 0)
        #expect(crop?.minY == 0)
        #expect((crop?.width ?? 0) > box.width)
    }
}
