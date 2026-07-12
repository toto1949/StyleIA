import PhotosUI
import SwiftUI

/// "Bring a Friend or Pet" card — toggle reveals a second photo upload.
struct CompanionUploadView: View {
    @ObservedObject var viewModel: SceneMeViewModel
    @State private var isEnabled = false

    private var companionKind: Binding<CompanionKind> {
        Binding(
            get: { viewModel.request?.companionKind ?? .friend },
            set: { viewModel.request?.companionKind = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SceneMeTheme.surface)
                        .frame(width: 42, height: 42)

                    if let companion = viewModel.companionPhoto {
                        Image(uiImage: companion)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: companionKind.wrappedValue == .pet ? "pawprint.fill" : "person.fill.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SceneMeTheme.subtleText)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bring a Friend or Pet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SceneMeTheme.text)

                    Text(companionKind.wrappedValue == .pet
                        ? "Upload your pet's photo to appear together"
                        : "Upload a second photo to appear together")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SceneMeTheme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(SceneMeTheme.gold)
            }

            if isEnabled {
                HStack(spacing: 8) {
                    ForEach(CompanionKind.allCases) { kind in
                        kindChip(kind)
                    }
                    Spacer()
                }

                let hasPhoto = viewModel.companionPhoto != nil
                PhotosPicker(selection: $viewModel.companionItem, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: hasPhoto ? "arrow.triangle.2.circlepath" : "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))

                        Text(hasPhoto ? "Change their photo" : "Add their photo")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(SceneMeTheme.gold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(SceneMeTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SceneMeTheme.gold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
            }
        }
        .padding(14)
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous)
                .stroke(SceneMeTheme.hairline, lineWidth: 1)
        }
        .onAppear {
            isEnabled = viewModel.companionPhoto != nil
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                viewModel.removeCompanion()
            }
        }
        .onChange(of: viewModel.companionItem) { _, _ in
            Task {
                await viewModel.loadCompanionPhoto()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isEnabled)
    }

    private func kindChip(_ kind: CompanionKind) -> some View {
        let isSelected = companionKind.wrappedValue == kind

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                companionKind.wrappedValue = kind
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(kind.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.88) : SceneMeTheme.subtleText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? SceneMeTheme.gold : SceneMeTheme.surface)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(isSelected ? Color.clear : SceneMeTheme.hairline, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SceneMePressButtonStyle())
    }
}
