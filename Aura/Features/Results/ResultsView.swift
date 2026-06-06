import SwiftUI
import UIKit

struct ResultsView: View {
    @Bindable var viewModel: ResultsViewModel
    @State private var showShareSheet = false
    @State private var permissionKind: PermissionKind?

    var body: some View {
        ZStack(alignment: .top) {
            DesignSystem.Colors.primary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        header

                        comparison
                            .frame(height: 490)
                            .padding(.horizontal, DesignSystem.Spacing.lg)

                        ResultVariantStrip(
                            urls: viewModel.resultURLs,
                            selectedIndex: $viewModel.selectedIndex,
                            imageCache: viewModel.imageCache
                        )
                    }
                    .padding(.bottom, 112)
                }

                actionBar
            }

            if let message = viewModel.errorMessage {
                ErrorBanner(message: message) {
                    withAnimation {
                        viewModel.errorMessage = nil
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
        }
        .navigationTitle(L10n.string("results.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.load()
        }
        .onChange(of: viewModel.selectedIndex) { _, _ in
            viewModel.selectedVariantChanged()
        }
        .onDisappear {
            viewModel.saveHistoryIfNeeded()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: viewModel.shareItems())
        }
        .sheet(item: $permissionKind) { kind in
            PermissionPrimerView(kind: kind) {
                permissionKind = nil
                viewModel.saveCurrentImageToPhotos()
            } onCancel: {
                permissionKind = nil
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(L10n.string("results.regenerate.title"), isPresented: $viewModel.showRegenerateSheet, titleVisibility: .visible) {
            Button(L10n.string("results.regenerate.same")) {
                viewModel.regenerateSameStyle()
            }
            Button(L10n.string("results.regenerate.different")) {
                viewModel.chooseDifferentStyle()
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(viewModel.input.styleGoal.label)
                .font(Typography.displayMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(L10n.string("results.subtitle"))
                .font(Typography.bodySmall)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
    }

    @ViewBuilder
    private var comparison: some View {
        if let original = viewModel.originalImage, let result = viewModel.currentResultImage {
            ComparisonSlider(beforeImage: original, afterImage: result)
        } else {
            VStack(spacing: DesignSystem.Spacing.md) {
                ProgressView()
                    .tint(DesignSystem.Colors.accent)
                Text(L10n.string("results.loading"))
                    .font(Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large, style: .continuous))
        }
    }

    private var actionBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            actionButton(title: L10n.string("results.save"), systemImage: "square.and.arrow.down") {
                permissionKind = .photoSave
            }

            actionButton(title: L10n.string("results.share"), systemImage: "square.and.arrow.up") {
                showShareSheet = true
            }

            if viewModel.canRegenerate {
                actionButton(title: L10n.string("results.regenerate"), systemImage: "arrow.clockwise") {
                    viewModel.showRegenerateSheet = true
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(.ultraThinMaterial)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        _ = context
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        _ = uiViewController
        _ = context
    }
}

#Preview {
    ResultsView(
        viewModel: ResultsViewModel(
            input: PreviewData.resultsInput,
            container: PreviewData.container,
            coordinator: PreviewData.coordinator
        )
    )
}
