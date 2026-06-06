import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GenerateViewModel {
    var selectedImage: UIImage?
    var selectedStyleGoal: StyleGoal?
    var isLoading = false
    var errorMessage: String?

    private let safetyService: SafetyService
    private let coordinator: AppCoordinator
    private let haptics: HapticManager
    private let crashReporter: CrashReporting
    @ObservationIgnored private var reuseObserver: NSObjectProtocol?

    init(container: DependencyContainer, coordinator: AppCoordinator) {
        safetyService = container.safetyService
        haptics = container.haptics
        crashReporter = container.crashReporter
        self.coordinator = coordinator

        reuseObserver = NotificationCenter.default.addObserver(
            forName: .styleAIReusePhoto,
            object: nil,
            queue: .main
        ) { notification in
            guard let image = notification.object as? UIImage else { return }
            Task { @MainActor [weak self] in
                self?.selectedImage = image
            }
        }
    }

    deinit {
        if let reuseObserver {
            NotificationCenter.default.removeObserver(reuseObserver)
        }
    }

    var canGenerate: Bool {
        selectedImage != nil && selectedStyleGoal != nil && !isLoading
    }

    func setImage(_ image: UIImage) {
        selectedImage = image
        errorMessage = nil
    }

    func select(goal: StyleGoal) {
        haptics.styleSelected()
        selectedStyleGoal = goal
    }

    func prepareGeneration() {
        guard let image = selectedImage, let goal = selectedStyleGoal else {
            errorMessage = L10n.string("generate.validation")
            return
        }

        haptics.primaryTap()

        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            let safety = await safetyService.check(image: image)
            switch safety {
            case .safe:
                coordinator.startGeneration(image: image, styleGoal: goal)
            case .noFaceDetected:
                errorMessage = ErrorMessageMapper.message(for: SafetyError.noFaceDetected)
            case .potentiallyUnsafe:
                let error = SafetyError.potentiallyUnsafe
                crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }
}
