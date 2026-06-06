import SwiftData
import SwiftUI

@main
struct StyleAIApp: App {
    @State private var container: DependencyContainer
    @State private var coordinator: AppCoordinator

    init() {
        let modelContainer = DependencyContainer.makeModelContainer()
        let container = DependencyContainer(modelContainer: modelContainer)
        _container = State(initialValue: container)
        _coordinator = State(initialValue: AppCoordinator(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container, coordinator: coordinator)
                .modelContainer(container.modelContainer)
                .tint(DesignSystem.Colors.accent)
        }
    }
}

struct RootView: View {
    let container: DependencyContainer
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.root {
        case .onboarding:
            OnboardingView(viewModel: OnboardingViewModel(), coordinator: coordinator)
        case .auth:
            AuthView(viewModel: AuthViewModel(container: container, coordinator: coordinator))
        case .main:
            MainTabView(container: container, coordinator: coordinator)
        }
    }
}

struct MainTabView: View {
    let container: DependencyContainer
    @Bindable var coordinator: AppCoordinator

    @State private var generateViewModel: GenerateViewModel
    @State private var historyViewModel: HistoryViewModel
    @State private var profileViewModel: ProfileViewModel

    init(container: DependencyContainer, coordinator: AppCoordinator) {
        self.container = container
        self.coordinator = coordinator
        _generateViewModel = State(initialValue: GenerateViewModel(container: container, coordinator: coordinator))
        _historyViewModel = State(initialValue: HistoryViewModel(container: container))
        _profileViewModel = State(initialValue: ProfileViewModel(container: container, coordinator: coordinator))
    }

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            NavigationStack(path: $coordinator.generatePath) {
                GenerateView(viewModel: generateViewModel)
                    .navigationDestination(for: CoordinatorRoute.self) { route in
                        switch route {
                        case .generating:
                            if let input = coordinator.activeGenerationInput {
                                GeneratingView(
                                    viewModel: GeneratingViewModel(input: input, container: container, coordinator: coordinator)
                                )
                            } else {
                                EmptyStateView(title: L10n.string("generate.validation"))
                            }
                        case .results:
                            if let input = coordinator.activeResultsInput {
                                ResultsView(
                                    viewModel: ResultsViewModel(input: input, container: container, coordinator: coordinator)
                                )
                            } else {
                                EmptyStateView(title: L10n.string("results.imageUnavailable"))
                            }
                        }
                    }
            }
            .tabItem {
                Label(L10n.string("tab.generate"), systemImage: "sparkles")
            }
            .tag(AppTab.generate)

            NavigationStack(path: $coordinator.historyPath) {
                HistoryView(viewModel: historyViewModel, coordinator: coordinator)
                    .navigationDestination(for: CoordinatorRoute.self) { route in
                        switch route {
                        case .results:
                            if let input = coordinator.activeResultsInput {
                                ResultsView(
                                    viewModel: ResultsViewModel(input: input, container: container, coordinator: coordinator)
                                )
                            } else {
                                EmptyStateView(title: L10n.string("results.imageUnavailable"))
                            }
                        case .generating:
                            EmptyStateView(title: L10n.string("generate.validation"))
                        }
                    }
            }
            .tabItem {
                Label(L10n.string("tab.history"), systemImage: "clock.arrow.circlepath")
            }
            .tag(AppTab.history)

            NavigationStack {
                ProfileView(viewModel: profileViewModel, container: container)
            }
            .tabItem {
                Label(L10n.string("tab.profile"), systemImage: "person.crop.circle")
            }
            .tag(AppTab.profile)
        }
    }
}

#Preview {
    RootView(container: PreviewData.container, coordinator: PreviewData.coordinator)
}
