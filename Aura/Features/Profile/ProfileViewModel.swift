import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var user: User?
    var plan: SubscriptionPlan = .free
    var savedCount = 0
    var isLoading = false
    var errorMessage: String?
    var showDeleteConfirmation = false
    var shareItems: [Any] = []

    private let container: DependencyContainer
    private let coordinator: AppCoordinator

    init(container: DependencyContainer, coordinator: AppCoordinator) {
        self.container = container
        self.coordinator = coordinator
        user = container.authService.currentUser()
        shareItems = [container.appShareURL]
    }

    var initials: String {
        let email = user?.email ?? ""
        let base = email.split(separator: "@").first.map(String.init) ?? L10n.string("profile.avatarFallback")
        let letters = base.split(separator: ".").compactMap { $0.first }
        if letters.isEmpty {
            return String(base.prefix(2)).uppercased()
        }
        return String(letters.prefix(2)).uppercased()
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    func load() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            savedCount = container.historyService.localRecords().count
            plan = await container.subscriptionManager.currentPlan()
        }
    }

    func upgrade() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                plan = try await container.subscriptionManager.upgradeToPro()
            } catch {
                container.crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    func deleteAllData() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                let _: DeleteResponse = try await container.apiService.request(
                    Endpoint(path: "/account", method: .delete)
                )
                container.historyService.deleteAllLocal()
                coordinator.signOut()
            } catch {
                container.crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    func signOut() {
        coordinator.signOut()
    }
}
