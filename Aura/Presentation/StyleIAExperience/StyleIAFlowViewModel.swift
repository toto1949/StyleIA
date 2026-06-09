import Combine
import Foundation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class StyleIAFlowViewModel: ObservableObject {
    @Published var step: StyleIAFlowStep = .splash
    @Published var selectedPersona = StyleIAPersona.samples[0]
    @Published var subjectGender: StyleIASubjectGender = .male
    @Published var selectedPhoto: UIImage?
    @Published var photoItem: PhotosPickerItem?
    @Published var previousStep: StyleIAFlowStep = .styleCard
    @Published var isPreparingJob = false
    @Published var lastPreparedJob: StyleIAJobDraft?
    @Published var jobNotice: String?
    @Published var recommendations: StyleIARecommendations?
    @Published var resultURLs: [URL] = []
    @Published var generatedLooks: [StyleIALook] = []
    @Published var generationStatus: String = "Ready"
    @Published var lastGenerationError: String?

    private let jobClient: StyleIAJobPreparing
    private let imageAnalyzer: StyleIAImageAnalyzing
    private let imageOptimizer: StyleIAImageOptimizing
    private let persistence = StyleIAFlowPersistence()

    var visibleRecommendations: StyleIARecommendations {
        recommendations ?? fallbackRecommendations(for: selectedPersona)
    }

    convenience init() {
        if let backendURL = Secrets.backendAPIBaseURL {
            self.init(
                jobClient: StyleIABackendJobClient(baseURL: backendURL),
                imageAnalyzer: VisionStyleIAImageAnalyzer(),
                imageOptimizer: CoreImageStyleIAImageOptimizer()
            )
        } else {
            self.init(
                jobClient: StyleIAPlaceholderJobClient(),
                imageAnalyzer: VisionStyleIAImageAnalyzer(),
                imageOptimizer: CoreImageStyleIAImageOptimizer()
            )
        }
    }

    init(
        jobClient: StyleIAJobPreparing,
        imageAnalyzer: StyleIAImageAnalyzing,
        imageOptimizer: StyleIAImageOptimizing
    ) {
        self.jobClient = jobClient
        self.imageAnalyzer = imageAnalyzer
        self.imageOptimizer = imageOptimizer
        let cachedLooks = persistence.loadLooks()
        generatedLooks = cachedLooks
        resultURLs = cachedLooks.map(\.imageURL)
    }

    func move(to nextStep: StyleIAFlowStep) {
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            step = nextStep
        }
    }

    func loadSelectedPhoto() async {
        guard
            let photoItem,
            let data = try? await photoItem.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            return
        }

        selectedPhoto = image
        move(to: .analysing)
    }

    func prepareJob() async {
        guard !isPreparingJob else { return }

        guard let sourcePhoto = selectedPhoto else {
            let message = StyleIAImageProcessingError.missingImage.errorDescription ?? "Upload a photo first."
            generationStatus = "Photo required"
            lastGenerationError = message
            jobNotice = message
            move(to: .upload)
            return
        }

        isPreparingJob = true
        generationStatus = "Analyzing photo"
        lastGenerationError = nil
        jobNotice = nil
        defer { isPreparingJob = false }

        let draft = makeDraft()
        generatedLooks = []
        resultURLs = []

        do {
            let validation = try await imageAnalyzer.validate(sourcePhoto)
            if !validation.isValid {
                throw StyleIAImageProcessingError.photoRejected
            }

            if !validation.warnings.isEmpty {
                jobNotice = validation.warnings.map(\.message).joined(separator: " ")
            }

            generationStatus = "Optimizing photo"
            let optimized = try await imageOptimizer.optimize(
                sourcePhoto,
                suggestedCrop: validation.suggestedCropRect
            )
            let photoPayload = StyleIAPhotoPayload(data: optimized.data, contentType: optimized.contentType)

            generationStatus = "Uploading photo"
            let receipt = try await jobClient.prepare(draft, photo: photoPayload) { [weak self] looks in
                self?.generationStatus = "Receiving generated looks"
                self?.mergeGeneratedLooks(looks)
            }
            lastPreparedJob = draft
            recommendations = receipt.recommendations ?? fallbackRecommendations(for: selectedPersona)
            resultURLs = receipt.resultURLs
            mergeGeneratedLooks(receipt.looks)
            if jobNotice == nil {
                jobNotice = receipt.message
            }
            generationStatus = "Ready"
            move(to: previousStep)
            dismissNotice(for: draft.localJobId)
        } catch let error as StyleIAImageProcessingError where error == .photoRejected {
            let message = error.errorDescription ?? "Please upload a clear front-facing photo with one person visible."
            generationStatus = "Photo check failed"
            lastGenerationError = message
            jobNotice = message
            move(to: .upload)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not prepare job"
            generationStatus = "Generation failed"
            lastGenerationError = message
            jobNotice = message
        }
    }

    private func mergeGeneratedLooks(_ looks: [StyleIALook]) {
        guard !looks.isEmpty else { return }

        var merged = generatedLooks
        for look in looks {
            if let index = merged.firstIndex(where: { $0.id == look.id }) {
                merged[index] = look
            } else {
                merged.append(look)
            }
        }

        let order = orderedStyleGoals(for: selectedPersona)
        generatedLooks = merged.sorted { lhs, rhs in
            styleRank(lhs.styleGoal, in: order) < styleRank(rhs.styleGoal, in: order)
        }
        resultURLs = generatedLooks.map(\.imageURL)
        persistence.saveLooks(generatedLooks)
    }

    private func styleRank(_ styleGoal: String, in order: [String]) -> Int {
        order.firstIndex(of: styleGoal) ?? Int.max
    }

    private func makeDraft() -> StyleIAJobDraft {
        let goals = orderedStyleGoals(for: selectedPersona)

        return StyleIAJobDraft(
            localJobId: UUID().uuidString,
            personaId: selectedPersona.id,
            personaName: selectedPersona.displayName,
            matchScore: selectedPersona.match,
            faceShape: "Oval",
            undertone: "Olive warm",
            build: "Medium",
            styleGoal: goals[0],
            styleGoals: goals,
            subjectGender: subjectGender.rawValue,
            styleProfile: makeStyleProfile(),
            photoSource: selectedPhoto == nil ? "styleia-placeholder-sample" : "local-user-photo",
            requestedOutputs: ["style-card", "style-twins", "before-after"]
        )
    }

    private func makeStyleProfile() -> StyleIAStyleProfile {
        StyleIAStyleProfile(
            subjectGender: subjectGender.rawValue,
            ageRange: "adult",
            bodyType: "medium",
            heightRange: "",
            skinTone: selectedPersona.descriptor.replacingOccurrences(of: "\n", with: " "),
            undertone: "Olive warm",
            hairColor: "",
            faceShape: "Oval",
            fitPreference: subjectGender == .female ? "clean tailored feminine fit" : "clean tailored masculine fit",
            colorPreference: selectedPersona.id == "earth-dandy" ? "earth tones and warm neutrals" : "premium neutrals with moss accents",
            modestyPreference: "balanced modern coverage",
            climate: "temperate",
            occasion: "daily style discovery",
            budget: "mid premium",
            stylePersona: selectedPersona.displayName,
            favoriteColors: selectedPersona.id == "earth-dandy" ? ["olive", "espresso", "cream"] : ["moss", "charcoal", "ivory"],
            avoid: subjectGender == .female ? ["masculinized face", "generic dress-only styling"] : ["feminized face", "generic suit-only styling"]
        )
    }

    private func orderedStyleGoals(for persona: StyleIAPersona) -> [String] {
        switch persona.id {
        case "earth-dandy":
            return ["casual", "sporty", "professional", "luxury", "streetwear"]
        case "neo-formal":
            return ["casual", "sporty", "professional", "luxury", "streetwear"]
        default:
            return ["casual", "sporty", "professional", "luxury", "streetwear"]
        }
    }

    private func fallbackRecommendations(for persona: StyleIAPersona) -> StyleIARecommendations {
        StyleIARecommendations(
            title: "\(persona.displayName) - \(persona.descriptor.replacingOccurrences(of: "\n", with: " "))",
            bullets: [
                "Lean into warm texture and soft contrast.",
                "Use structured layers to frame your face.",
                "Choose accessories that echo your natural undertone."
            ],
            tags: ["Oval", "Olive", "Casual"]
        )
    }

    private func dismissNotice(for jobId: String) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if self.lastPreparedJob?.localJobId == jobId {
                    self.jobNotice = nil
                }
            }
        }
    }
}

private struct StyleIAFlowPersistence {
    private var fileURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return directory.appendingPathComponent("styleia-generated-looks.json")
    }

    func loadLooks() -> [StyleIALook] {
        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let looks = try? JSONDecoder().decode([StyleIALook].self, from: data)
        else {
            return []
        }

        return looks
    }

    func saveLooks(_ looks: [StyleIALook]) {
        guard let fileURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(looks)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Could not persist StyleIA looks: \(error)")
        }
    }
}
