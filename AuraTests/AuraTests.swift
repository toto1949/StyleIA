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

    @Test func sceneCatalogContainsUniqueValidScenes() {
        let scenes = SceneCatalog.bundled

        // Catalog has grown past the original 15; keep a floor and require unique IDs.
        #expect(scenes.count >= 15)
        #expect(Set(scenes.map(\.id)).count == scenes.count)
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

    @Test func companionGenderSelectionIsPreserved() throws {
        let scene = try #require(SceneCatalog.bundled.first { $0.id == "times-square" })
        var request = GenerationRequest(scene: scene)
        request.subjectGender = .male
        request.hasCompanion = true
        request.companionKind = .friend
        request.companionGender = .male

        #expect(request.companionGender == .male)
        #expect(request.previewSummary.contains("man friend"))
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
        #expect(scene.id.hasPrefix("custom-"))
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
        #expect(CinematicFilter.nonOriginal.count == CinematicFilter.allCases.count - 1)

        let input = solidImage(size: CGSize(width: 64, height: 64))
        for filter in CinematicFilter.nonOriginal {
            let output = CinematicFilterEngine.apply(filter, to: input)
            #expect(output.size.width > 0)
            #expect(output.size.height > 0)

            let originalStrength = CinematicFilterEngine.blend(input, output, intensity: 0)
            let fullStrength = CinematicFilterEngine.blend(input, output, intensity: 1)
            #expect(originalStrength.size == input.size)
            #expect(fullStrength.size == output.size)
        }

        let graded = CinematicFilterEngine.apply(.portra, to: input)
        let blended = CinematicFilterEngine.blend(input, graded, intensity: 0.4)
        #expect(blended.size.width > 0)
        #expect(blended.size.height > 0)

        let nearOriginal = CinematicFilterEngine.blend(input, graded, intensity: 0)
        #expect(nearOriginal.size == input.size)
    }

    @Test func customScenesGetUniqueReusableIds() {
        let first = SceneTemplate.custom(name: "Rooftop", description: "standing on a rooftop in Marrakech with mosaic tiles", outfit: "")
        let second = SceneTemplate.custom(name: "Rooftop", description: "standing on a rooftop in Marrakech with mosaic tiles", outfit: "")
        #expect(first.isCustom)
        #expect(second.isCustom)
        #expect(first.id != second.id)
        #expect(first.id.hasPrefix("custom-"))
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
