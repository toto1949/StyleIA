import Foundation
import Observation
import SwiftUI
import UIKit

enum RootDestination {
    case onboarding
    case auth
    case main
}

enum AppTab: Hashable {
    case generate
    case history
    case profile
}

enum CoordinatorRoute: Hashable {
    case generating
    case results
}

struct GenerationInput {
    let image: UIImage
    let styleGoal: StyleGoal
}

struct ResultsInput {
    let jobId: String
    let styleGoal: StyleGoal
    let resultURLs: [String]
    let originalImage: UIImage?
    let originalPhotoURL: String
    let readOnly: Bool
    let s3Key: String?
}

@MainActor
@Observable
final class AppCoordinator {
    var root: RootDestination
    var selectedTab: AppTab = .generate
    var generatePath: [CoordinatorRoute] = []
    var historyPath: [CoordinatorRoute] = []
    var activeGenerationInput: GenerationInput?
    var activeResultsInput: ResultsInput?

    private let container: DependencyContainer
    private let defaults: UserDefaults
    @ObservationIgnored nonisolated(unsafe) private var authExpiredObserver: NSObjectProtocol?

    init(container: DependencyContainer, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults

        if !defaults.bool(forKey: "styleai.hasSeenOnboarding") {
            root = .onboarding
        } else if container.authService.retrieveToken() == nil {
            root = .auth
        } else {
            root = .main
        }

        authExpiredObserver = NotificationCenter.default.addObserver(
            forName: AuthExpiredNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.handleAuthExpired()
            }
        }
    }

    deinit {
        if let authExpiredObserver {
            NotificationCenter.default.removeObserver(authExpiredObserver)
        }
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "styleai.hasSeenOnboarding")
        root = container.authService.retrieveToken() == nil ? .auth : .main
    }

    func skipOnboarding() {
        completeOnboarding()
    }

    func signedIn() {
        root = .main
        selectedTab = .generate
        container.analytics.capture("auth_success", properties: [:])
    }

    func signOut() {
        container.authService.signOut()
        generatePath.removeAll()
        historyPath.removeAll()
        activeGenerationInput = nil
        activeResultsInput = nil
        root = .auth
    }

    func startGeneration(image: UIImage, styleGoal: StyleGoal) {
        activeGenerationInput = GenerationInput(image: image, styleGoal: styleGoal)
        generatePath.append(.generating)
    }

    func showGeneratedResults(
        jobId: String,
        styleGoal: StyleGoal,
        resultURLs: [String],
        originalImage: UIImage,
        originalPhotoURL: String,
        s3Key: String?
    ) {
        activeResultsInput = ResultsInput(
            jobId: jobId,
            styleGoal: styleGoal,
            resultURLs: resultURLs,
            originalImage: originalImage,
            originalPhotoURL: originalPhotoURL,
            readOnly: false,
            s3Key: s3Key
        )

        generatePath = [.results]
    }

    func showHistoryResults(record: GenerationRecord) {
        activeResultsInput = ResultsInput(
            jobId: record.jobId,
            styleGoal: record.styleGoal,
            resultURLs: record.resultURLs,
            originalImage: nil,
            originalPhotoURL: record.originalPhotoURL,
            readOnly: true,
            s3Key: nil
        )
        historyPath.append(.results)
    }

    func regenerateSameStyle() {
        guard
            let input = activeResultsInput,
            let image = input.originalImage
        else {
            return
        }

        activeGenerationInput = GenerationInput(image: image, styleGoal: input.styleGoal)
        activeResultsInput = nil
        generatePath = [.generating]
        selectedTab = .generate
    }

    func chooseDifferentStyle() {
        guard let image = activeResultsInput?.originalImage else {
            return
        }

        activeGenerationInput = nil
        activeResultsInput = nil
        generatePath.removeAll()
        selectedTab = .generate
        NotificationCenter.default.post(name: .styleAIReusePhoto, object: image)
    }

    func cancelGeneration() {
        activeGenerationInput = nil
        if generatePath.last == .generating {
            generatePath.removeLast()
        }
    }

    private func handleAuthExpired() {
        container.authService.signOut()
        root = .auth
    }
}

extension Notification.Name {
    static let styleAIReusePhoto = Notification.Name("StyleAI.ReusePhoto")
}
