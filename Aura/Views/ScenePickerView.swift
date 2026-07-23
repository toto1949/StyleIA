import PhotosUI
import SwiftUI

struct ScenePickerView: View {
    @ObservedObject var viewModel: SceneMeViewModel
    @State private var category: SceneCategory?
    @State private var showCustomComposer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    yourPhotoCard

                    categoryChips

                    customSceneCard

                    sceneGrid
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)

            generateBar
        }
        .background(SceneMeTheme.ink)
        .sheet(isPresented: $showCustomComposer) {
            CustomSceneComposerView { name, description, outfit in
                viewModel.createCustomScene(name: name, description: description, outfit: outfit)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SceneMeCircleButton(systemImage: "chevron.left") {
                viewModel.move(to: .home)
            }

            Text("Pick a Scene")
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.text)

            Spacer()
        }
        .padding(.top, 8)
    }

    private var yourPhotoCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SceneMeTheme.surface)
                    .frame(width: 44, height: 44)

                if let photo = viewModel.userPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(SceneMeTheme.subtleText)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SceneMeTheme.gold.opacity(0.7), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR PHOTO")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(SceneMeTheme.gold)

                Text(viewModel.photoFileName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SceneMeTheme.text)
                    .lineLimit(1)
            }

            Spacer()

            PhotosPicker(selection: $viewModel.photoItem, matching: .images) {
                Text("Change")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.subtleText)
                    .underline()
            }
        }
        .padding(13)
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous)
                .stroke(SceneMeTheme.gold.opacity(0.35), lineWidth: 1)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "All", isSelected: category == nil) {
                    category = nil
                }

                ForEach(SceneCategory.pickerCases) { item in
                    categoryChip(title: item.title, isSelected: category == item) {
                        category = item
                    }
                }
            }
        }
    }

    /// Entry point for user-described custom templates.
    private var customSceneCard: some View {
        Button {
            if viewModel.currentTier.canUseCustomScene {
                showCustomComposer = true
            } else {
                viewModel.requireTier(.creator, feature: "Custom Scenes")
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.gold)
                    .frame(width: 44, height: 44)
                    .background(SceneMeTheme.gold.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("CREATE YOUR OWN")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.8)
                            .foregroundStyle(SceneMeTheme.gold)

                        if !viewModel.currentTier.canUseCustomScene {
                            Text("CREATOR+")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(Color.black.opacity(0.88))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(SceneMeTheme.gold)
                                .clipShape(Capsule())
                        }
                    }

                    Text("Describe any scene — we'll put you there")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(viewModel.currentTier.canUseCustomScene ? SceneMeTheme.text : SceneMeTheme.subtleText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.subtleText)
            }
            .padding(13)
            .background(SceneMeTheme.panel.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous)
                    .strokeBorder(
                        SceneMeTheme.gold.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                action()
            }
        } label: {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(isSelected ? Color.black.opacity(0.88) : SceneMeTheme.subtleText)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? SceneMeTheme.gold : SceneMeTheme.panel)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .overlay {
                    Capsule().stroke(isSelected ? Color.clear : SceneMeTheme.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private var filteredScenes: [SceneTemplate] {
        let all = viewModel.pickerScenes
        guard let category else {
            return all
        }
        if category == .custom {
            return viewModel.customScenes
        }
        return viewModel.scenes.filter { $0.category == category }
    }

    /// Two-column staggered layout like the design mock.
    private var sceneGrid: some View {
        let scenes = filteredScenes
        let left = scenes.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        let right = scenes.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)

        return Group {
            if scenes.isEmpty, category == .custom {
                emptyYoursState
            } else {
                HStack(alignment: .top, spacing: 12) {
                    column(for: left, tallFirst: true)
                    column(for: right, tallFirst: false)
                }
            }
        }
    }

    private var emptyYoursState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SceneMeTheme.gold)
            Text("No saved scenes yet")
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.text)
            Text("Create your own above — it stays here so you can reuse it.")
                .font(.system(size: 12))
                .foregroundStyle(SceneMeTheme.subtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 18)
        .background(SceneMeTheme.panel.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                .strokeBorder(SceneMeTheme.gold.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    private func column(for scenes: [SceneTemplate], tallFirst: Bool) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                SceneCardView(
                    scene: scene,
                    isSelected: viewModel.selectedScene?.id == scene.id,
                    height: cardHeight(index: index, tallFirst: tallFirst),
                    overrideBadgeTitle: scene.isCustom
                        ? "✦ YOURS"
                        : (scene.badge == .popular ? "MOST USED" : nil)
                ) {
                    viewModel.selectScene(scene)
                }
                .contextMenu {
                    if scene.isCustom {
                        Button(role: .destructive) {
                            viewModel.deleteCustomScene(scene)
                        } label: {
                            Label("Delete Scene", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cardHeight(index: Int, tallFirst: Bool) -> CGFloat {
        let isTall = tallFirst ? index.isMultiple(of: 2) : !index.isMultiple(of: 2)
        return isTall ? 224 : 178
    }

    private var generateBar: some View {
        VStack(spacing: 8) {
            SceneMeCTAButton(
                title: viewModel.selectedScene.map { "Generate in \($0.name)" } ?? "Pick a scene",
                systemImage: "play.fill",
                isEnabled: viewModel.selectedScene != nil
            ) {
                viewModel.move(to: .sceneOptions)
            }

            Text("~15 seconds · Uses 1 credit")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SceneMeTheme.faintText)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [SceneMeTheme.ink.opacity(0), SceneMeTheme.ink.opacity(0.92), SceneMeTheme.ink],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// Per-scene options screen: time of day, weather, pose, companion — then generate.
struct SceneOptionsView: View {
    @ObservedObject var viewModel: SceneMeViewModel

    var body: some View {
        Group {
            if let request = viewModel.request {
                content(for: request)
            } else {
                Color.clear.onAppear {
                    viewModel.move(to: .scenePicker)
                }
            }
        }
        .background(SceneMeTheme.ink)
    }

    private func content(for request: GenerationRequest) -> some View {
        let scene = request.scene

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero(for: scene)

                    VStack(alignment: .leading, spacing: 22) {
                        section(title: "Styled For") {
                            genderSelector
                        }

                        section(title: "Time of Day") {
                            TimeSliderView(
                                availableTimes: scene.availableTimes,
                                selection: timeBinding
                            )
                        }

                        section(title: "Weather") {
                            WeatherToggleView(
                                availableWeather: scene.availableWeather,
                                selection: weatherBinding
                            )
                        }

                        section(title: "Pose") {
                            PoseSelectorView(selection: poseBinding)
                        }

                        section(title: "Add Someone") {
                            if viewModel.currentTier.canAddCompanion {
                                CompanionUploadView(viewModel: viewModel)
                            } else {
                                lockedFeatureRow(label: "Companion photos", tier: .pro) {
                                    viewModel.requireTier(.pro, feature: "Companion Photos")
                                }
                            }
                        }

                        scenePreview(for: request)
                    }
                    .padding(.horizontal, 22)
                }
                .padding(.bottom, 150)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            generateBar
        }
    }

    private func hero(for scene: SceneTemplate) -> some View {
        ZStack(alignment: .bottomLeading) {
            SceneThumbnail(scene: scene)
                .frame(height: 280)

            LinearGradient(
                colors: [Color.black.opacity(0.25), .clear, SceneMeTheme.ink],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                SceneMeEyebrow(text: scene.location)

                Text(scene.name)
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(SceneMeTheme.text)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)

            VStack {
                HStack {
                    SceneMeCircleButton(systemImage: "chevron.left") {
                        viewModel.move(to: .scenePicker)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)

                Spacer()
            }
        }
        .frame(height: 280)
    }

    /// Picks who the photo shows so the outfit and identity details match.
    private var genderSelector: some View {
        HStack(spacing: 8) {
            ForEach(SubjectGender.allCases) { gender in
                let isSelected = (viewModel.request?.subjectGender ?? .auto) == gender

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.request?.subjectGender = gender
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(gender.emoji)
                            .font(.system(size: 13))
                        Text(gender.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                    }
                    .foregroundStyle(isSelected ? Color.black.opacity(0.88) : SceneMeTheme.subtleText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(isSelected ? SceneMeTheme.gold : SceneMeTheme.panel)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(isSelected ? Color.clear : SceneMeTheme.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(SceneMePressButtonStyle())
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(SceneMeTheme.subtleText)

            content()
        }
    }

    /// A row shown instead of a feature when the user doesn't have the required tier.
    private func lockedFeatureRow(label: String, tier: SubscriptionTier, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.gold)
                    .frame(width: 30, height: 30)
                    .background(SceneMeTheme.gold.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(SceneMeTheme.text.opacity(0.6))
                    Text("\(tier.displayName) plan required")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SceneMeTheme.gold)
                }

                Spacer()

                Text("UPGRADE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.black.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SceneMeTheme.gold)
                    .clipShape(Capsule())
            }
            .padding(14)
            .background(SceneMeTheme.panel.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous)
                    .strokeBorder(SceneMeTheme.gold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private func scenePreview(for request: GenerationRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SceneMeEyebrow(text: "Your scene preview")

            Text(request.previewSummary)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(SceneMeTheme.text.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SceneMeTheme.panel.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous)
                .stroke(SceneMeTheme.hairline, lineWidth: 1)
        }
    }

    private var generateBar: some View {
        VStack(spacing: 8) {
            SceneMeCTAButton(title: "Generate Now", systemImage: "play.fill") {
                viewModel.startGeneration()
            }

            Text("~15 sec · Your face will be preserved exactly")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SceneMeTheme.faintText)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [SceneMeTheme.ink.opacity(0), SceneMeTheme.ink.opacity(0.92), SceneMeTheme.ink],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var timeBinding: Binding<TimeOfDay> {
        Binding(
            get: { viewModel.request?.timeOfDay ?? .goldenHour },
            set: { viewModel.request?.timeOfDay = $0 }
        )
    }

    private var weatherBinding: Binding<WeatherOption> {
        Binding(
            get: { viewModel.request?.weather ?? .sunny },
            set: { viewModel.request?.weather = $0 }
        )
    }

    private var poseBinding: Binding<PoseOption> {
        Binding(
            get: { viewModel.request?.pose ?? .casual },
            set: { viewModel.request?.pose = $0 }
        )
    }
}
