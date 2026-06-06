import AVFoundation
import Photos
import SwiftUI

struct GenerateView: View {
    @Bindable var viewModel: GenerateViewModel
    @State private var showPhotoOptions = false
    @State private var permissionKind: PermissionKind?
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        ZStack(alignment: .top) {
            DesignSystem.Colors.primary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text(L10n.string("generate.title"))
                            .font(Typography.displayMedium)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.string("generate.subtitle"))
                            .font(Typography.bodySmall)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.md)

                    photoSection

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text(L10n.string("generate.styleTitle"))
                            .font(Typography.titleLarge)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)

                        StyleSelectorView(selectedGoal: $viewModel.selectedStyleGoal) { goal in
                            viewModel.select(goal: goal)
                        }
                    }

                    PrimaryButton(
                        title: L10n.string("generate.cta"),
                        isLoading: viewModel.isLoading,
                        isDisabled: !viewModel.canGenerate
                    ) {
                        viewModel.prepareGeneration()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.xl)
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
        .confirmationDialog(L10n.string("generate.photoOptions"), isPresented: $showPhotoOptions, titleVisibility: .visible) {
            Button(L10n.string("generate.takePhoto")) {
                permissionKind = .camera
            }
            Button(L10n.string("generate.chooseLibrary")) {
                permissionKind = .photoLibrary
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        }
        .sheet(item: $permissionKind) { kind in
            PermissionPrimerView(kind: kind) {
                permissionKind = nil
                requestPermission(for: kind)
            } onCancel: {
                permissionKind = nil
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                viewModel.setImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            PhotoLibraryPicker { image in
                viewModel.setImage(image)
            }
        }
    }

    private var photoSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large, style: .continuous))
                    .designShadow(DesignSystem.Shadows.card)

                Button(L10n.string("generate.changePhoto")) {
                    showPhotoOptions = true
                }
                .font(Typography.titleMedium)
                .foregroundStyle(DesignSystem.Colors.accent)
                .buttonStyle(PressScaleButtonStyle())
            } else {
                Button {
                    showPhotoOptions = true
                } label: {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .frame(width: 92, height: 92)
                            .background(DesignSystem.Colors.surfaceRaised)
                            .clipShape(Circle())

                        VStack(spacing: DesignSystem.Spacing.xs) {
                            Text(L10n.string("generate.photoCta"))
                                .font(Typography.titleLarge)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            Text(L10n.string("generate.photoCtaSubtitle"))
                                .font(Typography.bodySmall)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large, style: .continuous))
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
    }

    private func requestPermission(for kind: PermissionKind) {
        switch kind {
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                showCamera = true
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    Task { @MainActor in
                        if granted {
                            showCamera = true
                        } else {
                            viewModel.errorMessage = L10n.string("permission.camera.denied")
                        }
                    }
                }
            case .denied, .restricted:
                viewModel.errorMessage = L10n.string("permission.camera.denied")
            @unknown default:
                viewModel.errorMessage = L10n.string("permission.camera.denied")
            }
        case .photoLibrary:
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch status {
            case .authorized, .limited:
                showLibrary = true
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    Task { @MainActor in
                        if newStatus == .authorized || newStatus == .limited {
                            showLibrary = true
                        } else {
                            viewModel.errorMessage = L10n.string("permission.photos.denied")
                        }
                    }
                }
            case .denied, .restricted:
                viewModel.errorMessage = L10n.string("permission.photos.denied")
            @unknown default:
                viewModel.errorMessage = L10n.string("permission.photos.denied")
            }
        case .photoSave:
            break
        }
    }
}

#Preview {
    GenerateView(viewModel: GenerateViewModel(container: PreviewData.container, coordinator: PreviewData.coordinator))
}
