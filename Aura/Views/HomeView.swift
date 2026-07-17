import PhotosUI
import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: SceneMeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                hero

                stats

                featuredScenes

                yourGenerations
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(SceneMeTheme.ink)
    }

    private var header: some View {
        HStack {
            (
                Text("Scene")
                    .foregroundStyle(SceneMeTheme.text)
                +
                Text("Me")
                    .foregroundStyle(SceneMeTheme.gold)
            )
            .font(.system(size: 24, weight: .regular, design: .serif))

            Spacer()

            Button {
                viewModel.tab = .profile
            } label: {
                Text(viewModel.profile.initial)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(SceneMeTheme.gold)
                    .frame(width: 44, height: 44)
                    .background(SceneMeTheme.panel)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .overlay {
                        Circle().stroke(SceneMeTheme.gold.opacity(0.7), lineWidth: 1)
                    }
            }
            .buttonStyle(SceneMePressButtonStyle())
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            SceneMeEyebrow(text: "Your world, expanded")
                .padding(.top, 38)

            (
                Text("Place yourself\n")
                    .foregroundStyle(SceneMeTheme.text)
                +
                Text("anywhere.")
                    .italic()
                    .foregroundStyle(SceneMeTheme.gold)
            )
            .font(.system(size: 42, weight: .regular, design: .serif))
            .lineSpacing(2)

            Text("Upload one photo. Pick a scene. Be there.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SceneMeTheme.subtleText)

            PhotosPicker(selection: $viewModel.photoItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))

                    Text("UPLOAD YOUR PHOTO")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(2)
                }
                .foregroundStyle(Color.black.opacity(0.88))
                .padding(.horizontal, 28)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: SceneMeTheme.gold.opacity(0.3), radius: 14, y: 6)
            }
            .padding(.top, 8)
        }
    }

    private var stats: some View {
        HStack(spacing: 1) {
            statTile(value: "\(viewModel.scenes.count)", label: "Scenes")
            statTile(value: "\(CinematicFilter.nonOriginal.count)", label: "Filters")
            statTile(value: "∞", label: "Poses")
        }
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                .stroke(SceneMeTheme.hairline, lineWidth: 1)
        }
        .padding(.top, 14)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.text)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(SceneMeTheme.subtleText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
    }

    private var featuredScenes: some View {
        VStack(alignment: .leading, spacing: 14) {
            SceneMeSectionHeader(title: "Featured Scenes", actionTitle: "See all") {
                viewModel.tab = .explore
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featured) { scene in
                        SceneCardView(scene: scene, height: 200) {
                            viewModel.selectScene(scene)
                            if viewModel.userPhoto != nil {
                                viewModel.move(to: .sceneOptions)
                            } else {
                                viewModel.notice = "Upload your photo first to enter this scene."
                            }
                        }
                        .frame(width: 150)
                    }
                }
            }
        }
    }

    private var featured: [SceneTemplate] {
        let badged = viewModel.scenes.filter { $0.badge != nil }
        let rest = viewModel.scenes.filter { $0.badge == nil }
        return Array((badged + rest).prefix(6))
    }

    private var yourGenerations: some View {
        VStack(alignment: .leading, spacing: 14) {
            SceneMeSectionHeader(
                title: "Your Generations",
                actionTitle: viewModel.history.isEmpty ? nil : "History",
                action: viewModel.history.isEmpty ? nil : { viewModel.tab = .gallery }
            )

            if viewModel.history.isEmpty {
                emptyGenerations
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(viewModel.history.prefix(4))) { result in
                        GenerationCard(
                            result: result,
                            isFavorite: viewModel.isFavorite(result),
                            onToggleFavorite: { viewModel.toggleFavorite(result) },
                            onDelete: { viewModel.deleteResult(result) }
                        ) {
                            viewModel.openResult(result)
                        }
                    }
                }
            }
        }
    }

    private var emptyGenerations: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 26))
                .foregroundStyle(SceneMeTheme.faintText)

            Text("Your generated scenes will appear here.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(SceneMeTheme.subtleText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .background(SceneMeTheme.panel.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                .stroke(SceneMeTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        }
    }
}

/// Past generation tile used on Home and in the Gallery tab.
/// Long-press for delete and favorite actions.
struct GenerationCard: View {
    let result: GenerationResult
    var isFavorite = false
    var onToggleFavorite: (() -> Void)?
    var onDelete: (() -> Void)?
    let onTap: () -> Void

    @State private var confirmDelete = false

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Color.clear + overlay keeps scaledToFill from expanding the
                // hit-test region past the card bounds (steals taps from chips above).
                Color.clear
                    .overlay {
                        AsyncImage(url: result.imageURL) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                SceneMeTheme.surface
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.system(size: 18))
                                            .foregroundStyle(SceneMeTheme.faintText)
                                    }
                            }
                        }
                    }
                    .clipped()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                HStack(alignment: .bottom) {
                    Text(result.sceneName.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(SceneMeTheme.text)

                    Spacer(minLength: 8)

                    if result.hasAnyVideo {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                            if result.videoClips.count > 1 {
                                Text("\(result.videoClips.count)")
                                    .font(.system(size: 9, weight: .heavy))
                            }
                        }
                        .foregroundStyle(SceneMeTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(SceneMeTheme.gold.opacity(0.45), lineWidth: 1)
                        }
                    }
                }
                .padding(10)
                .allowsHitTesting(false)
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(cardShape)
            .contentShape(cardShape)
            .overlay {
                cardShape.stroke(SceneMeTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
        .contextMenu {
            if let onToggleFavorite {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(
                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: isFavorite ? "heart.slash" : "heart"
                    )
                }
            }

            if onDelete != nil {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this scene?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(result.sceneName) will be removed from your gallery. This can't be undone.")
        }
    }
}
