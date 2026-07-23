import SwiftUI
import UIKit

struct ResultView: View {
    @ObservedObject var viewModel: SceneMeViewModel

    @State private var selectedFilter: CinematicFilter = .original
    @State private var filterIntensity: Double = 1
    /// Full-strength grades, cached per filter.
    @State private var filteredCache: [CinematicFilter: UIImage] = [:]
    /// The grade blended with the original at the chosen strength.
    @State private var gradedImage: UIImage?
    /// Watermarked (free tier) or clean (subscribers) copy used for save & share.
    @State private var exportImage: UIImage?
    @State private var showPostcard = false
    @State private var showFilters = false
    @State private var showVideoDirector = false
    /// Fit mode shows the entire image (uncropped) and hides the controls.
    @State private var showFullImage = false
    @State private var hasAppeared = false

    var body: some View {
        Group {
            if let result = viewModel.currentResult {
                content(for: result)
            } else {
                Color.clear.onAppear {
                    viewModel.move(to: .home)
                }
            }
        }
        .background(Color.black)
    }

    private func content(for result: GenerationResult) -> some View {
        ZStack(alignment: .bottom) {
            fullScreenImage(for: result)

            if !showFullImage {
                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.55), Color.black.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    sceneHeader(for: result)

                    actionRow(for: result)

                    if showFilters {
                        CinematicFilterView(
                            baseImage: viewModel.resultImage,
                            selection: $selectedFilter,
                            intensity: $filterIntensity
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    bottomButtons(for: result)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            } else {
                fullImageHint
            }

            topBar(for: result)
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                hasAppeared = true
            }
        }
        .onDisappear {
            hasAppeared = false
            selectedFilter = .original
            filterIntensity = 1
            filteredCache = [:]
            gradedImage = nil
            showFilters = false
            showFullImage = false
        }
        .onChange(of: viewModel.resultImage) { _, _ in
            filteredCache = [:]
            gradedImage = nil
            selectedFilter = .original
            filterIntensity = 1
            refreshExportImage()
        }
        .onChange(of: selectedFilter) { _, _ in
            // Drop the previous look immediately so strength never shows a stale grade.
            gradedImage = nil
        }
        .task(id: "\(selectedFilter.rawValue)|\(String(format: "%.2f", filterIntensity))") {
            if selectedFilter == .original {
                gradedImage = nil
                refreshExportImage()
                return
            }
            await applySelectedFilter()
            await applyIntensity()
            refreshExportImage()
        }
        .sheet(isPresented: $showPostcard) {
            if let image = displayedUIImage {
                PostcardFrameView(
                    image: image,
                    sceneName: result.sceneName,
                    date: result.createdAt
                ) { postcard in
                    viewModel.saveToPhotoLibrary(postcard)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .sheet(isPresented: $showVideoDirector) {
            AnimateDirectorSheet(
                sceneName: result.sceneName,
                sceneLocation: result.sceneLocation,
                sceneCategory: viewModel.request?.scene.category
                    ?? viewModel.scenes.first(where: { $0.id == result.sceneId })?.category,
                existingClips: viewModel.currentResult?.videoClips ?? result.videoClips,
                onGenerate: { style, line, direction in
                    viewModel.animateScene(
                        motionStyle: style,
                        spokenLine: line,
                        directionNote: direction
                    )
                },
                onPlayClip: { clip in
                    viewModel.playVideoClip(clip)
                }
            )
        }
        .fullScreenCover(isPresented: $viewModel.presentVideoPlayer) {
            let clip = viewModel.playingVideoClip
                ?? viewModel.currentResult?.videoClips.first
            if let clip {
                SceneVideoPlayerView(
                    videoURL: clip.videoURL,
                    sceneName: result.sceneName,
                    caption: clip.captionText
                ) { url in
                    viewModel.saveVideoToPhotoLibrary(url)
                }
            } else if let videoURL = viewModel.currentResult?.videoURL {
                SceneVideoPlayerView(
                    videoURL: videoURL,
                    sceneName: result.sceneName,
                    caption: viewModel.currentResult?.videoCaption
                ) { url in
                    viewModel.saveVideoToPhotoLibrary(url)
                }
            }
        }
    }

    // MARK: - Image

    private var displayedUIImage: UIImage? {
        guard let base = viewModel.resultImage else {
            return nil
        }
        guard selectedFilter != .original else {
            return base
        }
        // Prefer the intensity-blended image; while it loads, show the cached
        // full grade for this filter only — never a previous filter's grade.
        if let gradedImage {
            return gradedImage
        }
        return filteredCache[selectedFilter] ?? base
    }

    private func fullScreenImage(for result: GenerationResult) -> some View {
        GeometryReader { proxy in
            ZStack {
                ZoomableScrollView(
                    onSingleTap: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFullImage.toggle()
                        }
                    }
                ) {
                    Group {
                        if let image = displayedUIImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: showFullImage ? .fit : .fill)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        } else {
                            AsyncImage(url: result.imageURL) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: showFullImage ? .fit : .fill)
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                } else {
                                    ZStack {
                                        SceneMeTheme.surface
                                        ProgressView()
                                            .tint(SceneMeTheme.gold)
                                    }
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                }
                            }
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .overlay {
                // Always-on editorial signature — reads in screenshots & screen recordings.
                SceneMeSignatureOverlay(
                    corner: showFullImage ? .bottomTrailing : .topLeading,
                    compact: true
                )
                .padding(.top, showFullImage ? 0 : 56)
                .padding(.bottom, showFullImage ? 36 : 0)
                .allowsHitTesting(false)
            }
            .overlay {
                if viewModel.isRerolling {
                    ZStack {
                        Color.black.opacity(0.55)
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(SceneMeTheme.gold)
                            Text("Re-rolling outfit…")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SceneMeTheme.text)
                        }
                    }
                } else if viewModel.isAnimating {
                    // Non-blocking: user can leave for Profile/settings while the clip finishes.
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(SceneMeTheme.gold)
                                .scaleEffect(0.85)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Animating in the background…")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SceneMeTheme.text)
                                Text("Feel free to browse — you’ll get a notification when it’s ready.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(SceneMeTheme.subtleText)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(SceneMeTheme.panel.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                                .stroke(SceneMeTheme.gold.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 110)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Caption shown in full-image mode.
    private var fullImageHint: some View {
        Text("Pinch to zoom · double-tap · tap to return")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SceneMeTheme.subtleText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(.bottom, 24)
            .allowsHitTesting(false)
    }

    // MARK: - Top bar

    private func topBar(for result: GenerationResult) -> some View {
        VStack {
            HStack {
                SceneMeCircleButton(systemImage: "chevron.left") {
                    viewModel.move(to: .home)
                }

                Spacer()

                HStack(spacing: 10) {
                    SceneMeCircleButton(
                        systemImage: showFullImage ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFullImage.toggle()
                        }
                    }

                    SceneMeCircleButton(
                        systemImage: viewModel.isFavorite(result) ? "heart.fill" : "heart",
                        isActive: viewModel.isFavorite(result)
                    ) {
                        viewModel.toggleFavorite(result)
                    }

                    if let image = exportImage ?? displayedUIImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(result.sceneName, image: Image(uiImage: image))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SceneMeTheme.text)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                                .overlay {
                                    Circle().stroke(SceneMeTheme.hairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(SceneMePressButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)

            Spacer()
        }
    }

    // MARK: - Scene header + remix

    private func sceneHeader(for result: GenerationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SceneMeEyebrow(text: result.sceneLocation)

            HStack(spacing: 10) {
                Text(result.sceneName)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(SceneMeTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()
            }

            remixBar(for: result)
        }
    }

    /// Remix bar — change time or weather and regenerate without going back to the picker.
    private func remixBar(for result: GenerationResult) -> some View {
        let scene = viewModel.request?.scene

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scene?.availableTimes ?? [result.timeOfDay]) { time in
                    remixChip(
                        title: time.title,
                        isSelected: result.timeOfDay == time
                    ) {
                        viewModel.remix(timeOfDay: time)
                    }
                }

                ForEach(scene?.availableWeather ?? [result.weather]) { weather in
                    remixChip(
                        title: weather.title,
                        systemImage: weather.systemImage,
                        isSelected: result.weather == weather
                    ) {
                        viewModel.remix(weather: weather)
                    }
                }
            }
        }
    }

    private func remixChip(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isSelected else { return }
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .overlay {
                Capsule().stroke(isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    // MARK: - Actions

    private func actionRow(for result: GenerationResult) -> some View {
        HStack(alignment: .top) {
            OutfitRerollView(
                isRerolling: viewModel.isRerolling,
                isLocked: !viewModel.currentTier.canRerollOutfit
            ) {
                viewModel.rerollOutfit()
            }

            Spacer()

            actionButton(
                systemImage: result.hasAnyVideo ? "play.circle.fill" : "play.circle",
                title: viewModel.isAnimating
                    ? "Animating…"
                    : (result.videoClips.count > 1 ? "Clips" : "Animate"),
                isHighlighted: result.hasAnyVideo,
                isLocked: !viewModel.currentTier.canAnimateToVideo
            ) {
                guard !viewModel.isAnimating else { return }
                if viewModel.requireTier(.pro, feature: "Video Director") { return }
                showVideoDirector = true
            }

            Spacer()

            actionButton(
                systemImage: showFilters ? "photo.on.rectangle.angled" : "photo.on.rectangle",
                title: "Filters",
                isHighlighted: showFilters || selectedFilter != .original,
                isLocked: !viewModel.currentTier.canUseCinematicFilters
            ) {
                if viewModel.requireTier(.creator, feature: "Cinematic Filters") { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showFilters.toggle()
                }
            }

            Spacer()

            actionButton(systemImage: "arrow.down.to.line", title: "Save") {
                if let image = exportImage ?? displayedUIImage {
                    viewModel.saveToPhotoLibrary(image)
                }
            }
        }
    }

    private func actionButton(
        systemImage: String,
        title: String,
        isHighlighted: Bool = false,
        isLocked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isHighlighted ? SceneMeTheme.gold : SceneMeTheme.text)
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(isHighlighted ? SceneMeTheme.gold.opacity(0.7) : SceneMeTheme.hairline, lineWidth: 1)
                        }

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.88))
                            .padding(3)
                            .background(SceneMeTheme.gold)
                            .clipShape(Circle())
                            .offset(x: 2, y: -2)
                    }
                }

                Text(title.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(SceneMeTheme.subtleText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private func bottomButtons(for result: GenerationResult) -> some View {
        HStack(spacing: 12) {
            if let image = exportImage ?? displayedUIImage {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(result.sceneName, image: Image(uiImage: image))
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("SHARE")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.8)
                    }
                    .foregroundStyle(Color.black.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(SceneMePressButtonStyle())
            }

            Button {
                showPostcard = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("POSTCARD")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(SceneMeTheme.gold)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(SceneMeTheme.panel.opacity(0.9))
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(SceneMePressButtonStyle())
        }
    }

    // MARK: - Export

    private func refreshExportImage() {
        guard let base = displayedUIImage else {
            exportImage = nil
            return
        }

        exportImage = viewModel.currentTier.removesWatermark
            ? base
            : SceneMeWatermark.apply(to: base)
    }

    // MARK: - Filters

    private func applySelectedFilter() async {
        guard
            selectedFilter != .original,
            filteredCache[selectedFilter] == nil,
            let base = viewModel.resultImage
        else {
            return
        }

        let filter = selectedFilter
        let output = await Task.detached(priority: .userInitiated) {
            CinematicFilterEngine.apply(filter, to: base)
        }.value

        filteredCache[filter] = output
    }

    /// Blends the full-strength grade with the original at the slider strength.
    private func applyIntensity() async {
        guard
            selectedFilter != .original,
            let base = viewModel.resultImage,
            let full = filteredCache[selectedFilter]
        else {
            gradedImage = nil
            return
        }

        if filterIntensity >= 0.995 {
            gradedImage = full
            return
        }

        let intensity = filterIntensity
        gradedImage = await Task.detached(priority: .userInitiated) {
            CinematicFilterEngine.blend(base, full, intensity: intensity)
        }.value
    }
}
