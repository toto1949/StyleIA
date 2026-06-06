import Foundation
import Observation

@MainActor
@Observable
final class GeneratingViewModel {
    var progress = 0
    var currentTipIndex = 0
    var isLoading = false
    var errorMessage: String?
    var showFailureSheet = false

    let tips = [
        L10n.string("generating.tip.features"),
        L10n.string("generating.tip.colors"),
        L10n.string("generating.tip.outfit"),
        L10n.string("generating.tip.finishing")
    ]

    private let input: GenerationInput
    private let uploadService: UploadService
    private let generationService: GenerationService
    private let coordinator: AppCoordinator
    private let haptics: HapticManager
    private let analytics: AnalyticsTracking
    private let crashReporter: CrashReporting
    private var didStart = false
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var tipTask: Task<Void, Never>?

    private(set) var jobId: String?
    private(set) var s3Key: String?

    init(input: GenerationInput, container: DependencyContainer, coordinator: AppCoordinator) {
        self.input = input
        uploadService = container.uploadService
        generationService = container.generationService
        haptics = container.haptics
        analytics = container.analytics
        crashReporter = container.crashReporter
        self.coordinator = coordinator
    }

    deinit {
        generationTask?.cancel()
        tipTask?.cancel()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        startTips()
        runGeneration()
    }

    func retry() {
        generationTask?.cancel()
        progress = 0
        errorMessage = nil
        showFailureSheet = false
        didStart = true
        runGeneration()
    }

    func cancel() {
        generationTask?.cancel()
        Task {
            if let jobId {
                try? await generationService.cancel(jobId: jobId)
            }
            coordinator.cancelGeneration()
        }
    }

    func goBackAfterFailure() {
        showFailureSheet = false
        coordinator.cancelGeneration()
    }

    private func startTips() {
        tipTask?.cancel()
        tipTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { return }
                currentTipIndex = (currentTipIndex + 1) % tips.count
            }
        }
    }

    private func runGeneration() {
        generationTask = Task {
            isLoading = true
            errorMessage = nil
            analytics.capture("generation_started", properties: ["style_goal": input.styleGoal.rawValue])

            let progressTask = Task {
                for await uploadProgress in uploadService.uploadProgress() {
                    let mapped = Int(uploadProgress * 12)
                    progress = max(progress, min(mapped, 12))
                }
            }

            do {
                let uploadedKey = try await uploadService.upload(image: input.image)
                s3Key = uploadedKey
                progress = max(progress, 14)

                let seed = Int.random(in: 1...999_999)
                let job = try await generationService.submit(s3Key: uploadedKey, goal: input.styleGoal, seed: seed)
                jobId = job.jobId
                progress = max(progress, max(job.progress, 18))

                for await update in generationService.observe(jobId: job.jobId) {
                    switch update.payload {
                    case .progress(let percent):
                        progress = max(18, min(percent, 99))
                    case .completed(let resultURLs):
                        progress = 100
                        haptics.generationComplete()
                        analytics.capture("generation_completed", properties: ["style_goal": input.styleGoal.rawValue])
                        coordinator.showGeneratedResults(
                            jobId: job.jobId,
                            styleGoal: input.styleGoal,
                            resultURLs: resultURLs,
                            originalImage: input.image,
                            originalPhotoURL: uploadedKey,
                            s3Key: uploadedKey
                        )
                        progressTask.cancel()
                        isLoading = false
                        return
                    case .failed:
                        throw APIError.serverError(message: nil)
                    }
                }

                throw APIError.networkError
            } catch {
                progressTask.cancel()
                if error is CancellationError {
                    isLoading = false
                    return
                }

                crashReporter.record(error: error)
                haptics.generationFailed()
                analytics.capture("generation_failed", properties: ["style_goal": input.styleGoal.rawValue])
                errorMessage = ErrorMessageMapper.generationFailed
                showFailureSheet = true
                isLoading = false
            }
        }
    }
}
