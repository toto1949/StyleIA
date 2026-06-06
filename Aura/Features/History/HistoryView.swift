import SwiftUI

struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel
    let coordinator: AppCoordinator
    @State private var showShareSheet = false
    @State private var permissionKind: PermissionKind?
    @State private var recordPendingSave: GenerationRecord?

    private let columns = [
        GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
        GridItem(.flexible(), spacing: DesignSystem.Spacing.md)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            DesignSystem.Colors.primary
                .ignoresSafeArea()

            if viewModel.records.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    title: L10n.string("history.empty.title"),
                    subtitle: L10n.string("history.empty.subtitle"),
                    buttonTitle: L10n.string("history.empty.cta")
                ) {
                    coordinator.selectedTab = .generate
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.md) {
                        ForEach(viewModel.records) { record in
                            HistoryGridCell(record: record)
                                .onTapGesture {
                                    coordinator.showHistoryResults(record: record)
                                }
                                .contextMenu {
                                    Button(L10n.string("results.save"), systemImage: "square.and.arrow.down") {
                                        recordPendingSave = record
                                        permissionKind = .photoSave
                                    }
                                    Button(L10n.string("results.share"), systemImage: "square.and.arrow.up") {
                                        Task {
                                            await viewModel.prepareShare(record: record)
                                            showShareSheet = !viewModel.shareItems.isEmpty
                                        }
                                    }
                                    Button(L10n.string("common.delete"), systemImage: "trash", role: .destructive) {
                                        viewModel.confirmDelete(record)
                                    }
                                }
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(current: record)
                                }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(DesignSystem.Colors.accent)
                            .padding(.bottom, DesignSystem.Spacing.lg)
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
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
        .navigationTitle(L10n.string("history.title"))
        .task {
            viewModel.loadInitial()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: viewModel.shareItems)
        }
        .sheet(item: $permissionKind) { kind in
            PermissionPrimerView(kind: kind) {
                permissionKind = nil
                if let record = recordPendingSave {
                    viewModel.save(record: record)
                }
            } onCancel: {
                permissionKind = nil
                recordPendingSave = nil
            }
            .presentationDetents([.medium])
        }
        .alert(L10n.string("history.delete.title"), isPresented: Binding(
            get: { viewModel.recordPendingDeletion != nil },
            set: { if !$0 { viewModel.recordPendingDeletion = nil } }
        )) {
            Button(L10n.string("common.cancel"), role: .cancel) {
                viewModel.recordPendingDeletion = nil
            }
            Button(L10n.string("common.delete"), role: .destructive) {
                viewModel.deletePendingRecord()
            }
        } message: {
            Text(L10n.string("history.delete.message"))
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(viewModel: HistoryViewModel(container: PreviewData.container), coordinator: PreviewData.coordinator)
    }
}
