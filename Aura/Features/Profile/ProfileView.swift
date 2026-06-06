import SafariServices
import StoreKit
import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    let container: DependencyContainer

    @Environment(\.requestReview) private var requestReview
    @State private var showPrivacy = false
    @State private var showShareSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            DesignSystem.Colors.primary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    profileHeader
                    myLooksSection
                    subscriptionSection
                    privacySection
                    appSection

                    DestructiveButton(title: L10n.string("profile.signOut")) {
                        viewModel.signOut()
                    }
                    .padding(.top, DesignSystem.Spacing.md)
                }
                .padding(DesignSystem.Spacing.lg)
            }

            if let message = viewModel.errorMessage {
                ErrorBanner(message: message) {
                    withAnimation {
                        viewModel.errorMessage = nil
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }

            if viewModel.isLoading {
                LoadingOverlay(title: L10n.string("common.loading"))
            }
        }
        .navigationTitle(L10n.string("profile.title"))
        .task {
            viewModel.load()
        }
        .sheet(isPresented: $showPrivacy) {
            SafariView(url: container.privacyPolicyURL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: viewModel.shareItems)
        }
        .alert(L10n.string("profile.deleteData.title"), isPresented: $viewModel.showDeleteConfirmation) {
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("profile.deleteData.confirm"), role: .destructive) {
                viewModel.deleteAllData()
            }
        } message: {
            Text(L10n.string("profile.deleteData.message"))
        }
    }

    private var profileHeader: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text(viewModel.initials)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 92, height: 92)
                .background(DesignSystem.Colors.surfaceRaised)
                .clipShape(Circle())

            Text(viewModel.user?.email.isEmpty == false ? viewModel.user?.email ?? "" : L10n.string("profile.emailFallback"))
                .font(Typography.titleMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var myLooksSection: some View {
        profileSection(title: L10n.string("profile.myLooks")) {
            row(title: L10n.string("profile.savedCount"), value: "\(viewModel.savedCount)")
        }
    }

    private var subscriptionSection: some View {
        profileSection(title: L10n.string("profile.subscription")) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                row(title: viewModel.plan.title, value: viewModel.plan.detail)
                if viewModel.plan == .free {
                    PrimaryButton(title: L10n.string("profile.upgrade")) {
                        viewModel.upgrade()
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        profileSection(title: L10n.string("profile.privacy")) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                actionRow(title: L10n.string("profile.deleteData")) {
                    viewModel.showDeleteConfirmation = true
                }
                actionRow(title: L10n.string("profile.privacyPolicy")) {
                    showPrivacy = true
                }
            }
        }
    }

    private var appSection: some View {
        profileSection(title: L10n.string("profile.app")) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                actionRow(title: L10n.string("profile.rate")) {
                    requestReview()
                }
                actionRow(title: L10n.string("profile.share")) {
                    showShareSheet = true
                }
                row(title: L10n.string("profile.version"), value: viewModel.appVersion)
            }
        }
    }

    private func profileSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(Typography.titleMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            content()
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Typography.bodySmall)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 38)
    }

    private func actionRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Typography.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .frame(minHeight: 44)
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        _ = context
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        _ = uiViewController
        _ = context
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            viewModel: ProfileViewModel(container: PreviewData.container, coordinator: PreviewData.coordinator),
            container: PreviewData.container
        )
    }
}
