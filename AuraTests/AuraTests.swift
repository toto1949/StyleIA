import CoreGraphics
import Testing
import UIKit
@testable import Aura

struct AuraTests {
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

    @Test func sceneCatalogContainsFifteenUniqueScenes() {
        let scenes = SceneCatalog.bundled

        #expect(scenes.count == 15)
        #expect(Set(scenes.map(\.id)).count == 15)
        #expect(scenes.allSatisfy { !$0.basePrompt.isEmpty })
        #expect(scenes.allSatisfy { !$0.defaultOutfit.isEmpty })
        #expect(scenes.allSatisfy { !$0.availableTimes.isEmpty })
        #expect(scenes.allSatisfy { !$0.availableWeather.isEmpty })
        #expect(scenes.allSatisfy { $0.availableTimes.contains($0.defaultTime) })
        #expect(scenes.allSatisfy { $0.availableWeather.contains($0.defaultWeather) })
    }

    @Test func generationRequestDefaultsFollowScene() throws {
        let scene = try #require(SceneCatalog.bundled.first { $0.id == "times-square" })
        let request = GenerationRequest(scene: scene)

        #expect(request.timeOfDay == .night)
        #expect(request.pose == .casual)
        #expect(request.subjectGender == .auto)
        #expect(request.hasCompanion == false)
        #expect(request.previewSummary.contains("Times Square"))
    }

    @Test func scenesProvideGenderedOutfits() {
        let scenes = SceneCatalog.bundled

        #expect(scenes.allSatisfy { $0.maleOutfit?.isEmpty == false })
        #expect(scenes.allSatisfy { $0.femaleOutfit?.isEmpty == false })
        #expect(scenes.allSatisfy { $0.maleOutfit != $0.femaleOutfit })
    }

    @Test func customSceneBuildsFromUserDescription() {
        let scene = SceneTemplate.custom(
            name: "  Marrakech Rooftop  ",
            description: "standing on a riad rooftop in Marrakech at sunset",
            outfit: ""
        )

        #expect(scene.isCustom)
        #expect(scene.id == "custom")
        #expect(scene.name == "Marrakech Rooftop")
        #expect(scene.basePrompt.contains("Marrakech"))
        #expect(!scene.defaultOutfit.isEmpty)
        #expect(scene.availableTimes == TimeOfDay.allCases)
        #expect(scene.availableWeather == WeatherOption.allCases)

        var request = GenerationRequest(scene: scene)
        request.subjectGender = .female
        #expect(request.previewSummary.contains("woman"))
    }

    @Test func cinematicFiltersApplyClientSide() {
        #expect(CinematicFilter.nonOriginal.count == 4)

        let input = solidImage(size: CGSize(width: 64, height: 64))
        for filter in CinematicFilter.nonOriginal {
            let output = CinematicFilterEngine.apply(filter, to: input)
            #expect(output.size.width > 0)
            #expect(output.size.height > 0)
        }
    }

    @Test func postcardRendererComposesFrameAndStrip() {
        let input = solidImage(size: CGSize(width: 200, height: 300))
        let postcard = PostcardRenderer.render(
            image: input,
            sceneName: "Times Square",
            date: Date(),
            caption: "Wish you were here"
        )

        #expect(postcard.size.width > input.size.width)
        #expect(postcard.size.height > input.size.height)
    }

    @Test func sceneMeWatermarkKeepsDimensions() {
        let input = solidImage(size: CGSize(width: 320, height: 480))
        let branded = SceneMeWatermark.apply(to: input)
        #expect(branded.size == input.size)
    }

    private func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
