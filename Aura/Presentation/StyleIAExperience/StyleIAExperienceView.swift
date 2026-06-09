import Photos
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Root Experience View

@MainActor
struct StyleIAExperienceView: View {
    @StateObject private var viewModel: StyleIAFlowViewModel

    init() {
        _viewModel = StateObject(wrappedValue: StyleIAFlowViewModel())
    }

    init(viewModel: StyleIAFlowViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            StyleIABackground()

            Group {
                switch viewModel.step {
                case .splash:
                    StyleIASplashScreen {
                        viewModel.move(to: .inspiration)
                    }
                case .inspiration:
                    StyleIAInspirationScreen(
                        selectedPersona: $viewModel.selectedPersona,
                        subjectGender: $viewModel.subjectGender
                    ) {
                        viewModel.move(to: .splash)
                    } onSkip: {
                        viewModel.move(to: .upload)
                    } onContinue: {
                        viewModel.move(to: .upload)
                    }
                case .upload:
                    StyleIAUploadScreen(photoItem: $viewModel.photoItem, selectedPhoto: viewModel.selectedPhoto) {
                        viewModel.move(to: .inspiration)
                    } onContinue: {
                        viewModel.move(to: .analysing)
                    }
                case .analysing:
                    StyleIAAnalysingScreen(persona: viewModel.selectedPersona, selectedPhoto: viewModel.selectedPhoto) {
                        viewModel.previousStep = .styleCard
                        viewModel.move(to: .styleCard)
                        if viewModel.selectedPhoto != nil {
                            Task { await viewModel.prepareJob() }
                        }
                    }
                case .styleCard:
                    StyleIAStyleCardScreen(
                        persona: viewModel.selectedPersona,
                        selectedPhoto: viewModel.selectedPhoto,
                        generatedLooks: viewModel.generatedLooks,
                        isPreparingJob: viewModel.isPreparingJob,
                        recommendations: viewModel.visibleRecommendations
                    ) {
                        viewModel.move(to: .analysing)
                    } onTwins: {
                        viewModel.move(to: .twins)
                    }
                case .twins:
                    StyleIATwinsScreen(selectedPhoto: viewModel.selectedPhoto, recommendations: viewModel.visibleRecommendations) {
                        viewModel.move(to: .styleCard)
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.985)))

            if let notice = viewModel.jobNotice {
                StyleIAJobToast(message: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 10)
            }

            if viewModel.step == .analysing {
                ProcessingOverlay()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .tint(StyleIATheme.moss)
        .onChange(of: viewModel.photoItem) { _, _ in
            Task { await viewModel.loadSelectedPhoto() }
        }
    }
}

// MARK: - Screens & Components

private struct StyleIASplashScreen: View {
    let onBegin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            VStack(spacing: 0) {
                Spacer(minLength: layout.vertical(30))

                VStack(spacing: 10) {
                    Text("StyleIA")
                        .font(.system(size: layout.brandSize, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(StyleIATheme.text)
                        .shadow(color: StyleIATheme.moss.opacity(0.28), radius: 28)
                        .minimumScaleFactor(0.72)

                    Text("PERSONAL STYLE FROM ONE PHOTO")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(4)
                        .foregroundStyle(StyleIATheme.moss.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .padding(.horizontal, layout.sidePadding)

                Spacer(minLength: layout.vertical(24))

                StyleIASplashEditorialHero(layout: layout)
                    .padding(.horizontal, layout.sidePadding)

                HStack(spacing: 8) {
                    StyleIASplashMetric(title: "FACE", value: "Identity locked")
                    StyleIASplashMetric(title: "LOOKS", value: "5 contexts")
                    StyleIASplashMetric(title: "SHOP", value: "Shoes + frames")
                }
                .padding(.horizontal, layout.sidePadding)
                .padding(.top, layout.vertical(14))

                Spacer(minLength: layout.vertical(20))

                VStack(spacing: 16) {
                    Button(action: onBegin) {
                        Text("BEGIN YOUR STYLE")
                            .font(.system(size: layout.ctaSize, weight: .semibold))
                            .tracking(4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .frame(height: layout.primaryButtonHeight)
                            .background(StyleIATheme.moss)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(StyleIAPressButtonStyle())

                    VStack(spacing: 8) {
                        Text("Upload one clear photo. StyleIA keeps the face identity fixed, builds complete looks, then links shoes and frames for each style direction.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StyleIATheme.text.opacity(0.48))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)

                        Text("No account step. No setup friction.")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(StyleIATheme.faintText)
                    }
                }
                .padding(.horizontal, layout.sidePadding)

                Spacer(minLength: layout.vertical(28))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StyleIASplashMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(StyleIATheme.moss.opacity(0.78))

            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StyleIATheme.text.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(StyleIATheme.panel.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

private struct StyleIASplashEditorialHero: View {
    let layout: StyleIALayout

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(StyleIATheme.panel.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(StyleIATheme.hairline, lineWidth: 1)
                }

            StyleIAFaceSignalMesh()
                .opacity(0.48)
                .padding(12)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [StyleIATheme.moss.opacity(0.3), StyleIATheme.surfaceGreen],
                                center: .center,
                                startRadius: 12,
                                endRadius: 96
                            )
                        )
                    Circle()
                        .stroke(StyleIATheme.moss.opacity(0.44), lineWidth: 1)
                    Text("S")
                        .font(.system(size: 48, weight: .regular, design: .serif))
                        .foregroundStyle(StyleIATheme.text)
                }
                .frame(width: min(layout.size.width * 0.42, 160), height: min(layout.size.width * 0.42, 160))
                .overlay(alignment: .topTrailing) {
                    StyleIAFloatingLabel("Warm colors")
                        .offset(x: 54, y: 8)
                }
                .overlay(alignment: .topLeading) {
                    StyleIAFloatingLabel("Dark eyes")
                        .offset(x: -48, y: 18)
                }
                .overlay(alignment: .bottomTrailing) {
                    StyleIAFloatingLabel("Oval face")
                        .offset(x: 42, y: -2)
                }
                .overlay(alignment: .bottomLeading) {
                    StyleIAFloatingLabel("Casual edge")
                        .offset(x: -44, y: -4)
                }

                Spacer()

                VStack(spacing: 8) {
                    Text("From selfie to style session")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(StyleIATheme.text)
                    Text("Outfits, shoes, frames, accessories")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(2.7)
                        .foregroundStyle(StyleIATheme.moss.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 22)
        }
        .frame(height: min(max(layout.size.height * 0.46, 330), 430))
    }
}

private struct StyleIAFaceSignalMesh: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let points = [
                    CGPoint(x: proxy.size.width * 0.12, y: proxy.size.height * 0.26),
                    CGPoint(x: proxy.size.width * 0.32, y: proxy.size.height * 0.18),
                    CGPoint(x: proxy.size.width * 0.55, y: proxy.size.height * 0.34),
                    CGPoint(x: proxy.size.width * 0.78, y: proxy.size.height * 0.2),
                    CGPoint(x: proxy.size.width * 0.88, y: proxy.size.height * 0.62),
                    CGPoint(x: proxy.size.width * 0.58, y: proxy.size.height * 0.72),
                    CGPoint(x: proxy.size.width * 0.28, y: proxy.size.height * 0.64),
                    CGPoint(x: proxy.size.width * 0.1, y: proxy.size.height * 0.78)
                ]

                for index in points.indices {
                    path.move(to: points[index])
                    path.addLine(to: points[(index + 2) % points.count])
                    if index.isMultiple(of: 2) {
                        path.move(to: points[index])
                        path.addLine(to: points[(index + 3) % points.count])
                    }
                }
            }
            .stroke(StyleIATheme.text.opacity(0.12), lineWidth: 1)

            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(StyleIATheme.text.opacity(index.isMultiple(of: 2) ? 0.22 : 0.1))
                    .frame(width: 5, height: 5)
                    .position(nodePosition(index, in: proxy.size))
            }
        }
    }

    private func nodePosition(_ index: Int, in size: CGSize) -> CGPoint {
        let positions = [
            CGPoint(x: size.width * 0.12, y: size.height * 0.26),
            CGPoint(x: size.width * 0.32, y: size.height * 0.18),
            CGPoint(x: size.width * 0.55, y: size.height * 0.34),
            CGPoint(x: size.width * 0.78, y: size.height * 0.2),
            CGPoint(x: size.width * 0.88, y: size.height * 0.62),
            CGPoint(x: size.width * 0.58, y: size.height * 0.72),
            CGPoint(x: size.width * 0.28, y: size.height * 0.64),
            CGPoint(x: size.width * 0.1, y: size.height * 0.78)
        ]
        return positions[index]
    }
}

private struct StyleIAFloatingLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(StyleIATheme.text.opacity(0.76))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(StyleIATheme.panel.opacity(0.92))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(StyleIATheme.hairline, lineWidth: 1)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct StyleIAInspirationScreen: View {
    @Binding var selectedPersona: StyleIAPersona
    @Binding var subjectGender: StyleIASubjectGender
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            VStack(spacing: 0) {
                StyleIATopBar(
                    mode: .brandSkip,
                    progress: 1,
                    total: 4,
                    onBack: onBack,
                    onTrailing: onSkip
                )
                .padding(.horizontal, layout.sidePadding)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: layout.vertical(22)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Choose your\nstyle direction")
                                .font(.system(size: layout.heroTitleSize, weight: .regular, design: .serif))
                                .foregroundStyle(StyleIATheme.text)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("This guides the first style session. Your photo does the real matching.")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(StyleIATheme.text.opacity(0.54))
                                .lineSpacing(4)
                        }

                        StyleIAGenderSelector(selection: $subjectGender)

                        HStack(spacing: layout.cardGap) {
                            ForEach(StyleIAPersona.samples) { persona in
                                StyleIAPersonaCard(
                                    persona: persona,
                                    isSelected: selectedPersona.id == persona.id,
                                    layout: layout
                                ) {
                                    selectedPersona = persona
                                }
                            }
                        }

                        StyleIAOnboardingIntelligencePanel()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("PROFILE SIGNALS")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(4.2)
                                .foregroundStyle(StyleIATheme.moss.opacity(0.82))

                            HStack(spacing: 8) {
                                StyleIAFeaturePill(title: "Face\nshape")
                                StyleIAFeaturePill(title: "Skin\ntone")
                                StyleIAFeaturePill(title: "Build\nbalance")
                            }
                        }
                    }
                    .padding(.horizontal, layout.sidePadding)
                    .padding(.top, layout.vertical(30))
                    .padding(.bottom, layout.primaryButtonHeight + 34)
                }

                StyleIAPrimaryButton(title: "CONTINUE TO PHOTO", action: onContinue)
                    .padding(.horizontal, layout.sidePadding)
                    .padding(.bottom, max(layout.safeBottom, 14))
            }
        }
    }
}

private struct StyleIAOnboardingIntelligencePanel: View {
    private let rows = [
        ("1", "Pick a direction", "Start with a style mood, then refine after results."),
        ("2", "Upload once", "One photo powers full-body looks, shoes, frames, and product links."),
        ("3", "Review modules", "Open each look or jump straight to the matching product.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW STYLEIA BUILDS")
                .font(.system(size: 12, weight: .heavy))
                .tracking(3)
                .foregroundStyle(StyleIATheme.moss.opacity(0.78))

            VStack(spacing: 12) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.0)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(width: 26, height: 26)
                            .background(StyleIATheme.moss)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.1)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(StyleIATheme.text.opacity(0.88))

                            Text(row.2)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StyleIATheme.text.opacity(0.42))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(StyleIATheme.panel.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

private struct StyleIAGenderSelector: View {
    @Binding var selection: StyleIASubjectGender

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GENERATE FOR")
                .font(.system(size: 12, weight: .heavy))
                .tracking(3)
                .foregroundStyle(StyleIATheme.moss.opacity(0.78))

            HStack(spacing: 8) {
                ForEach(StyleIASubjectGender.allCases) { gender in
                    Button {
                        selection = gender
                    } label: {
                        Text(gender.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(selection == gender ? Color.black.opacity(0.82) : StyleIATheme.text.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(selection == gender ? StyleIATheme.moss : StyleIATheme.panel.opacity(0.76))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(selection == gender ? .clear : StyleIATheme.hairline, lineWidth: 1)
                            }
                    }
                    .buttonStyle(StyleIAPressButtonStyle())
                }
            }
        }
    }
}

private struct StyleIAUploadScreen: View {
    @Binding var photoItem: PhotosPickerItem?
    let selectedPhoto: UIImage?
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            VStack(spacing: 0) {
                StyleIATopBar(
                    mode: .progress,
                    progress: 2,
                    total: 4,
                    onBack: onBack,
                    onTrailing: {}
                )
                .padding(.horizontal, layout.sidePadding)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: layout.vertical(26)) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("STEP 2 OF 4")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(4.2)
                                .foregroundStyle(StyleIATheme.moss.opacity(0.72))

                            Text("Upload your\nbest photo")
                                .font(.system(size: layout.heroTitleSize, weight: .regular, design: .serif))
                                .foregroundStyle(StyleIATheme.text)
                                .lineSpacing(3)
                        }

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            uploadCard(layout: layout)
                        }
                        .buttonStyle(StyleIAPressButtonStyle())

                        HStack(spacing: 10) {
                            StyleIAUploadHint(title: "Clear face", detail: "Natural light, front-facing")
                            StyleIAUploadHint(title: "Simple expression", detail: "No heavy sunglasses")
                            StyleIAUploadHint(title: "Useful framing", detail: "Head and shoulders visible")
                        }
                    }
                    .padding(.horizontal, layout.sidePadding)
                    .padding(.top, layout.vertical(28))
                    .padding(.bottom, layout.primaryButtonHeight + max(layout.safeBottom, 40))
                }

                StyleIAPrimaryButton(
                    title: selectedPhoto == nil ? "SELECT PHOTO TO CONTINUE" : "ANALYSE MY STYLE",
                    isDisabled: selectedPhoto == nil
                ) {
                    onContinue()
                }
                .padding(.horizontal, layout.sidePadding)
                .padding(.bottom, max(layout.safeBottom, 14))
            }
        }
    }

    @ViewBuilder
    private func uploadCard(layout: StyleIALayout) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(StyleIATheme.panel.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(StyleIATheme.hairline, lineWidth: 1)
                }

            if let selectedPhoto {
                Image(uiImage: selectedPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(alignment: .bottom) {
                        Text("Photo selected")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(StyleIATheme.text)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 18)
                    }
            } else {
                VStack(spacing: 18) {
                    Text("DROP YOUR SELFIE HERE")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(3.4)
                        .foregroundStyle(StyleIATheme.moss.opacity(0.78))

                    Text("Tap to choose a front-facing photo")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(StyleIATheme.text)
                        .multilineTextAlignment(.center)

                    Text("StyleIA keeps the face identity fixed while building outfit, shoes, frames, and accessories.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StyleIATheme.text.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 28)
                }
            }
        }
        .frame(height: layout.uploadHeight)
    }
}

private struct StyleIAAnalysingScreen: View {
    let persona: StyleIAPersona
    let selectedPhoto: UIImage?
    let onComplete: () -> Void

    @State private var activeStep = 0
    @State private var isRotating = false

    private let rows = [
        "Face shape detected",
        "Undertone mapped",
        "Matching style DNA...",
        "Building your card"
    ]

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            VStack(spacing: 0) {
                Spacer(minLength: layout.vertical(64))

                Text("StyleIA")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(StyleIATheme.moss.opacity(0.54))

                Spacer(minLength: layout.vertical(22))

                ZStack {
                    StyleIAScanningRings(isRotating: isRotating)
                    if let image = selectedPhoto {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: layout.avatarLarge, height: layout.avatarLarge)
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(StyleIATheme.moss, lineWidth: 2)
                            }
                    } else {
                        StyleIAPersonAvatar(persona: persona, expression: .neutral)
                            .frame(width: layout.avatarLarge, height: layout.avatarLarge)
                    }
                }
                .frame(width: layout.analysisMarkSize, height: layout.analysisMarkSize)

                VStack(spacing: 5) {
                    Text("Reading your")
                        .font(.system(size: layout.resultTitleSize, weight: .regular, design: .serif))
                        .foregroundStyle(StyleIATheme.text)
                    Text("unique features")
                        .font(.system(size: layout.resultTitleSize, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(StyleIATheme.moss)
                }
                .padding(.top, layout.vertical(18))

                Spacer(minLength: layout.vertical(34))

                VStack(spacing: 18) {
                    ForEach(rows.indices, id: \.self) { index in
                        StyleIAAnalysisRow(index: index, title: rows[index], activeStep: activeStep)
                    }
                }
                .padding(.horizontal, layout.sidePadding + 10)

                Spacer(minLength: max(layout.safeBottom, 26))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            isRotating = true
            activeStep = 0
            Task {
                for index in 0..<rows.count {
                    try? await Task.sleep(for: .milliseconds(index == 0 ? 250 : 650))
                    await MainActor.run {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            activeStep = index
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(900))
                await MainActor.run { onComplete() }
            }
        }
    }
}

private struct StyleIAStyleCardScreen: View {
    let persona: StyleIAPersona
    let selectedPhoto: UIImage?
    let generatedLooks: [StyleIALook]
    let isPreparingJob: Bool
    let recommendations: StyleIARecommendations
    let onRefresh: () -> Void
    let onTwins: () -> Void

    @State private var selectedLookIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            ZStack {
                VStack(spacing: 0) {
                    StyleIATopBar(
                        mode: .cardActions,
                        progress: 3,
                        total: 4,
                        onBack: onTwins,
                        onTrailing: onRefresh
                    )
                    .padding(.horizontal, layout.sidePadding)

                    ScrollView(showsIndicators: false) {
                        StyleIAStyleFeedView(
                            persona: persona,
                            selectedPhoto: selectedPhoto,
                            generatedLooks: generatedLooks,
                            isPreparingJob: isPreparingJob,
                            recommendations: recommendations,
                            layout: layout,
                            onSelectLook: { selectedLookIndex = $0 },
                            onTwins: onTwins
                        )
                    }
                }

                if let selectedLookIndex, !generatedLooks.isEmpty {
                    StyleIALookDetailOverlay(
                        looks: generatedLooks,
                        selectedIndex: Binding(
                            get: { min(selectedLookIndex, generatedLooks.count - 1) },
                            set: { self.selectedLookIndex = $0 }
                        )
                    ) {
                        self.selectedLookIndex = nil
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
        }
        .toolbar(selectedLookIndex == nil ? .visible : .hidden, for: .tabBar)
    }
}

private struct StyleIATwinsScreen: View {
    let selectedPhoto: UIImage?
    let recommendations: StyleIARecommendations
    let onBack: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            VStack(spacing: 0) {
                StyleIATopBar(
                    mode: .twins,
                    progress: 4,
                    total: 4,
                    onBack: onBack,
                    onTrailing: onBack
                )
                .padding(.horizontal, layout.sidePadding)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: layout.vertical(22)) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Style Twins")
                                .font(.system(size: 27, weight: .regular, design: .serif))
                                .foregroundStyle(StyleIATheme.text)

                            Text("RECOMMENDED TAGS")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(4.2)
                                .foregroundStyle(StyleIATheme.moss.opacity(0.78))
                                .lineSpacing(7)

                            if !recommendations.tags.isEmpty {
                                HStack(spacing: 10) {
                                    ForEach(Array(recommendations.tags.prefix(6)), id: \.self) { tag in
                                        StyleIATinyTag(tag.uppercased())
                                    }
                                }
                            }
                        }

                        if let image = selectedPhoto {
                            ZStack {
                                Circle().fill(StyleIATheme.surfaceGreen)
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .clipShape(Circle())
                            }
                            .frame(width: 140, height: 140)
                            .overlay { Circle().stroke(StyleIATheme.moss, lineWidth: 2) }
                        }

                        if !recommendations.bullets.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("WHY THESE TAGS")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(4)
                                    .foregroundStyle(StyleIATheme.moss.opacity(0.6))
                                ForEach(recommendations.bullets, id: \.self) { item in
                                    Text("• \(item)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(StyleIATheme.text.opacity(0.9))
                                }
                            }
                        }

                        StyleIAPrimaryButton(title: "BACK TO STYLE SESSION", action: onBack)
                    }
                    .padding(.horizontal, layout.sidePadding)
                    .padding(.top, layout.vertical(18))
                    .padding(.bottom, max(layout.safeBottom, 24))
                }
            }
        }
    }
}

private struct StyleIAJobToast: View {
    let message: String

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StyleIATheme.moss)

                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StyleIATheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(StyleIATheme.hairline, lineWidth: 1)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

private struct StyleIATopBar: View {
    enum Mode {
        case brandSkip
        case progress
        case cardActions
        case twins
    }

    let mode: Mode
    let progress: Int
    let total: Int
    let onBack: () -> Void
    let onTrailing: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if mode == .cardActions {
                Text("StyleIA")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(StyleIATheme.moss)
                Spacer()
            } else {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(StyleIATheme.text.opacity(0.52))
                        .frame(width: 54, height: 54)
                        .background(StyleIATheme.surfaceGreen)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(StyleIATheme.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(StyleIAPressButtonStyle())

                if mode == .brandSkip {
                    Spacer()
                    Text("StyleIA")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(StyleIATheme.text.opacity(0.62))
                    Spacer()
                    Button("SKIP", action: onTrailing)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(StyleIATheme.text.opacity(0.34))
                        .buttonStyle(StyleIAPressButtonStyle())
                } else {
                    StyleIAProgressBars(progress: progress, total: total)
                    Spacer()
                }
            }

            if mode == .cardActions {
                HStack(spacing: 10) {
                    Button(action: onTrailing) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 52, height: 52)
                            .background(StyleIATheme.surfaceGreen)
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(StyleIATheme.hairline, lineWidth: 1)
                            }
                    }
                }
                .foregroundStyle(StyleIATheme.text.opacity(0.44))
                .buttonStyle(StyleIAPressButtonStyle())
            }

            if mode == .twins {
                Button(action: onTrailing) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(StyleIATheme.text.opacity(0.5))
                        .frame(width: 54, height: 54)
                        .background(StyleIATheme.surfaceGreen)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(StyleIATheme.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(StyleIAPressButtonStyle())
            }
        }
        .frame(height: 66)
        .padding(.top, 8)
    }
}

private struct StyleIAProgressBars: View {
    let progress: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < progress ? StyleIATheme.moss : StyleIATheme.surfaceGreen)
                    .frame(width: 36, height: 5)
            }
        }
    }
}

private struct StyleIAOrbitalMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(StyleIATheme.moss.opacity(index == 2 ? 0.58 : 0.18), lineWidth: index == 2 ? 2.2 : 1)
                        .frame(width: size * (0.66 + CGFloat(index) * 0.15), height: size * (0.66 + CGFloat(index) * 0.15))
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [StyleIATheme.moss.opacity(0.23), StyleIATheme.panel.opacity(0.35)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.42
                        )
                    )
                    .frame(width: size * 0.64, height: size * 0.64)

                Text("S")
                    .font(.system(size: size * 0.21, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(StyleIATheme.text)

                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(StyleIATheme.moss)
                        .frame(width: size * 0.036, height: size * 0.036)
                        .offset(y: -size * (0.33 + CGFloat(index) * 0.075))
                        .rotationEffect(.degrees(Double(index) * 120))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StyleIAScanningRings: View {
    let isRotating: Bool

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .stroke(
                        index == 1 ? StyleIATheme.moss.opacity(0.64) : StyleIATheme.moss.opacity(0.14),
                        style: StrokeStyle(lineWidth: index == 1 ? 2.5 : 1.2, dash: index > 1 ? [4, 5] : [])
                    )
                    .scaleEffect(0.54 + CGFloat(index) * 0.12)
            }
        }
        .rotationEffect(.degrees(isRotating ? 360 : 0))
        .animation(.linear(duration: 7).repeatForever(autoreverses: false), value: isRotating)
    }
}

private struct StyleIAPersonaCard: View {
    let persona: StyleIAPersona
    let isSelected: Bool
    let layout: StyleIALayout
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Text(persona.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StyleIATheme.text.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(isSelected ? "SET" : "\(persona.match)%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? StyleIATheme.text : persona.badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isSelected ? StyleIATheme.moss : persona.badgeColor).opacity(0.18))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(isSelected ? StyleIATheme.moss : persona.badgeColor, lineWidth: 1)
                        }
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [persona.badgeColor.opacity(0.82), StyleIATheme.surfaceGreen.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                    .clipShape(Capsule())

                Text(persona.descriptor)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StyleIATheme.moss.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(signalLines, id: \.self) { signal in
                        Text(signal)
                    }
                }
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(StyleIATheme.text.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

                Spacer(minLength: 0)

                Text(isSelected ? "SELECTED DIRECTION" : "TAP TO SELECT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(isSelected ? StyleIATheme.moss : StyleIATheme.faintText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: layout.personaAvatarHeight + 82, alignment: .topLeading)
            .background(persona.cardTint.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? StyleIATheme.moss : StyleIATheme.hairline, lineWidth: isSelected ? 3 : 1)
            }
            .shadow(color: isSelected ? StyleIATheme.moss.opacity(0.32) : .clear, radius: 10)
        }
        .buttonStyle(StyleIAPressButtonStyle())
    }

    private var signalLines: [String] {
        persona.descriptor
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }
}

private struct StyleIAFeaturePill: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StyleIATheme.moss.opacity(0.76))
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Rectangle()
                .fill(StyleIATheme.hairline)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .padding(.horizontal, 12)
        .background(StyleIATheme.panel.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(StyleIATheme.hairline.opacity(0.74), lineWidth: 1)
        }
    }
}

private struct StyleIAUploadHint: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(StyleIATheme.moss.opacity(0.78))
                .lineLimit(2)
                .minimumScaleFactor(0.68)

            Text(detail)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StyleIATheme.text.opacity(0.42))
                .lineSpacing(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 108)
        .padding(14)
        .background(StyleIATheme.panel.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StyleIATheme.hairline.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct StyleIAAnalysisRow: View {
    let index: Int
    let title: String
    let activeStep: Int

    private var isComplete: Bool { index < activeStep }
    private var isActive: Bool { index == activeStep }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isActive || isComplete ? StyleIATheme.moss.opacity(0.18) : StyleIATheme.surfaceGreen.opacity(0.55))
                Circle()
                    .stroke(isActive || isComplete ? StyleIATheme.moss : StyleIATheme.hairline, lineWidth: 2)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(StyleIATheme.moss)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isActive ? StyleIATheme.moss : StyleIATheme.text.opacity(0.28))
                }
            }
            .frame(width: 42, height: 42)

            Capsule()
                .fill(isActive || isComplete ? StyleIATheme.moss : StyleIATheme.surfaceGreen)
                .frame(width: isActive ? 88 : 74, height: 4)
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: activeStep)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(isActive || isComplete ? StyleIATheme.moss.opacity(0.72) : StyleIATheme.text.opacity(0.18))
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Spacer(minLength: 0)
        }
    }
}

private struct StyleIAStyleFeedView: View {
    let persona: StyleIAPersona
    let selectedPhoto: UIImage?
    let generatedLooks: [StyleIALook]
    let isPreparingJob: Bool
    let recommendations: StyleIARecommendations
    let layout: StyleIALayout
    let onSelectLook: (Int) -> Void
    let onTwins: () -> Void

    private var modules: [StyleIAFeedModule] {
        StyleIAFeedModule.modules(for: generatedLooks)
    }

    var body: some View {
        VStack(spacing: layout.vertical(30)) {
            VStack(spacing: 10) {
                Text("StyleIA")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(StyleIATheme.text)

                Rectangle()
                    .fill(StyleIATheme.hairline)
                    .frame(height: 1)
            }
            .padding(.horizontal, layout.sidePadding)

            StyleIATopPicksSection(
                looks: generatedLooks,
                persona: persona,
                selectedPhoto: selectedPhoto,
                isLoading: isPreparingJob,
                layout: layout,
                onSelect: onSelectLook
            )

            if !generatedLooks.isEmpty {
                StyleIAStyleSessionSummary(looks: generatedLooks)
                    .padding(.horizontal, layout.sidePadding)

                StyleIAAllLooksGridSection(
                    looks: generatedLooks,
                    layout: layout,
                    onSelectLook: onSelectLook
                )
            }

            ForEach(modules) { module in
                StyleIAFeedModuleSection(module: module, layout: layout, onSelectLook: onSelectLook)
            }

            if !recommendations.bullets.isEmpty {
                StyleIAInsightStrip(recommendations: recommendations)
                    .padding(.horizontal, layout.sidePadding)
            }

            HStack(spacing: 12) {
                StyleIASecondaryAction(title: "STYLE TWINS", systemImage: "person.2.fill", action: onTwins)
                StyleIASecondaryAction(title: "REFINE", systemImage: "slider.horizontal.3", action: onTwins)
            }
            .padding(.horizontal, layout.sidePadding)
        }
        .padding(.top, layout.vertical(18))
        .padding(.bottom, max(layout.safeBottom, 28))
    }
}

private struct StyleIATopPicksSection: View {
    let looks: [StyleIALook]
    let persona: StyleIAPersona
    let selectedPhoto: UIImage?
    let isLoading: Bool
    let layout: StyleIALayout
    let onSelect: (Int) -> Void

    @State private var activeIndex = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var selectedProduct: StyleIAProductRecommendation?

    private var cardWidth: CGFloat {
        layout.topPickCardWidth
    }

    private var activeLook: StyleIALook? {
        guard !looks.isEmpty else { return nil }
        return looks[min(activeIndex, looks.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TOP PICKS FOR YOU")
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(StyleIATheme.text.opacity(0.7))
                .frame(maxWidth: .infinity)

            Group {
                if let activeLook {
                    StyleIATopPickPagerCard(
                        look: activeLook,
                        index: min(activeIndex, looks.count - 1),
                        count: looks.count,
                        width: cardWidth,
                        imageScale: isDragging ? 0.92 : 1,
                        dragTranslation: dragTranslation,
                        onSelectLook: { onSelect(min(activeIndex, looks.count - 1)) },
                        onSelectProduct: { selectedProduct = $0 }
                    )
                    .padding(.horizontal, layout.sidePadding)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .gesture(swipeGesture)
                    .onChange(of: looks.count) { _, count in
                        activeIndex = min(activeIndex, max(count - 1, 0))
                    }
                } else {
                    StyleIASmartGeneratingCard(
                        persona: persona,
                        selectedPhoto: selectedPhoto,
                        width: cardWidth,
                        isLoading: isLoading
                    )
                    .padding(.horizontal, layout.sidePadding)
                }
            }
        }
        .sheet(item: $selectedProduct) { product in
            StyleIAProductDetailSheet(product: product)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                dragTranslation = value.translation.width
                if abs(value.translation.width) > 8 {
                    isDragging = true
                }
            }
            .onEnded { value in
                let threshold = cardWidth * 0.18
                let proposedIndex: Int
                if value.translation.width < -threshold {
                    proposedIndex = min(activeIndex + 1, looks.count - 1)
                } else if value.translation.width > threshold {
                    proposedIndex = max(activeIndex - 1, 0)
                } else {
                    proposedIndex = activeIndex
                }

                withAnimation(.easeInOut(duration: 0.3)) {
                    activeIndex = proposedIndex
                    dragTranslation = 0
                    isDragging = false
                }
            }
    }
}

private struct StyleIAStyleSessionSummary: View {
    let looks: [StyleIALook]

    private var totalAssets: Int {
        looks.count * 4
    }

    private var readyAssets: Int {
        looks.reduce(0) { total, look in
            total
                + (look.assetURL(for: .outfit) == nil ? 0 : 1)
                + (look.assetURL(for: .shoes) == nil ? 0 : 1)
                + (look.assetURL(for: .frames) == nil ? 0 : 1)
                + (look.assetURL(for: .accessories) == nil ? 0 : 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STYLE SESSION")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(3.2)
                        .foregroundStyle(StyleIATheme.moss.opacity(0.78))
                    Text("\(looks.count) looks styled for your profile")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(StyleIATheme.text)
                }

                Spacer()

                Text("\(readyAssets)/\(max(totalAssets, 1))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(StyleIATheme.moss)
            }

            HStack(spacing: 8) {
                StyleIASessionChip(title: "Outfits", count: looks.filter { $0.assetURL(for: .outfit) != nil }.count)
                StyleIASessionChip(title: "Shoes", count: looks.filter { $0.assetURL(for: .shoes) != nil }.count)
                StyleIASessionChip(title: "Frames", count: looks.filter { $0.assetURL(for: .frames) != nil }.count)
                StyleIASessionChip(title: "Details", count: looks.filter { $0.assetURL(for: .accessories) != nil }.count)
            }
        }
        .padding(16)
        .background(StyleIATheme.panel.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

private struct StyleIASessionChip: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 15, weight: .bold))
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.2)
        }
        .foregroundStyle(count > 0 ? StyleIATheme.moss : StyleIATheme.text.opacity(0.28))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(StyleIATheme.surfaceGreen)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StyleIATopPickPagerCard: View {
    let look: StyleIALook
    let index: Int
    let count: Int
    let width: CGFloat
    let imageScale: CGFloat
    let dragTranslation: CGFloat
    let onSelectLook: () -> Void
    let onSelectProduct: (StyleIAProductRecommendation) -> Void

    private var imageWidth: CGFloat { width * 0.7 }
    private var sideWidth: CGFloat { width - imageWidth }
    private var height: CGFloat { min(width * 1.09, 420) }

    var body: some View {
        Group {
            if width < 380 {
                VStack(spacing: 0) {
                    StyleIATopPickImagePanel(
                        look: look,
                        index: index,
                        count: count,
                        width: width,
                        height: min(width * 1.08, 360),
                        scale: imageScale,
                        dragTranslation: dragTranslation,
                        onSelect: onSelectLook
                    )

                    StyleIATopPickProductPanel(
                        look: look,
                        index: index,
                        width: width,
                        height: min(width * 0.62, 220),
                        onSelectProduct: onSelectProduct
                    )
                    .frame(width: width, height: min(width * 0.62, 220))
                    .background(Color(red: 0.41, green: 0.38, blue: 0.31))
                }
            } else {
                HStack(spacing: 0) {
                    StyleIATopPickImagePanel(
                        look: look,
                        index: index,
                        count: count,
                        width: imageWidth,
                        height: height,
                        scale: imageScale,
                        dragTranslation: dragTranslation,
                        onSelect: onSelectLook
                    )

                    StyleIATopPickProductPanel(
                        look: look,
                        index: index,
                        width: sideWidth,
                        height: height,
                        onSelectProduct: onSelectProduct
                    )
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .frame(width: sideWidth, height: height)
                    .background(Color(red: 0.41, green: 0.38, blue: 0.31))
                }
            }
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

private struct StyleIATopPickImagePanel: View {
    let look: StyleIALook
    let index: Int
    let count: Int
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let dragTranslation: CGFloat
    let onSelect: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: look.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                case .failure:
                    StyleIALookImageFallback()
                default:
                    StyleIALookImageLoading()
                }
            }
            .id(look.id)
            .frame(width: width, height: height)
            .scaleEffect(scale)
            .offset(x: dragTranslation * 0.08)
            .clipped()
            .animation(.easeInOut(duration: 0.3), value: scale)
            .animation(.easeInOut(duration: 0.4), value: look.id)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { item in
                        Capsule()
                            .fill(item == index ? Color.white : Color.white.opacity(0.32))
                            .frame(width: item == index ? 26 : 13, height: 4)
                    }
                }

                VStack(spacing: 2) {
                    Text("WALK AROUND")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(2.8)
                    Text(displayTitle(for: look).uppercased())
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .foregroundStyle(.white)

                HStack(spacing: 14) {
                    StyleIAFeedCircleAction(systemImage: "heart")
                    StyleIAFeedCircleAction(systemImage: "square.and.arrow.up")
                    StyleIAFeedCircleAction(systemImage: "arrow.down.to.line")
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct StyleIATopPickProductPanel: View {
    let look: StyleIALook
    let index: Int
    let width: CGFloat
    let height: CGFloat
    let onSelectProduct: (StyleIAProductRecommendation) -> Void

    private var products: [StyleIAProductRecommendation] {
        StyleIAProductRecommendation.products(for: look)
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text(index == 0 ? "TOP" : "LOOK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(StyleIATheme.moss)
                    .clipShape(Capsule())

                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.white)
            }

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: max(width - 38, 42), height: 1)

            Text(displayTitle(for: look).uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.58)
                .frame(width: max(width - 18, 72))

            Spacer()

            VStack(spacing: 14) {
                ForEach(products.prefix(2)) { product in
                    Button {
                        onSelectProduct(product)
                    } label: {
                        StyleIAProductCircle(
                            product: product,
                            imageURL: look.imageURL(for: product.assetModule),
                            diameter: 66
                        )
                    }
                    .buttonStyle(StyleIAPressButtonStyle())
                }
            }
            .padding(.bottom, 12)
        }
        .padding(.top, 18)
        .padding(.horizontal, 8)
        .frame(width: width, height: height)
    }
}

@MainActor
private struct StyleIAProductRecommendation: Identifiable {
    let id: String
    let label: String
    let name: String
    let detail: String
    let assetModule: StyleIALookAssetModule
    let systemImage: String
    let tint: Color
    let productURL: URL

    static func products(for styleGoal: String) -> [StyleIAProductRecommendation] {
        switch styleGoal {
        case "sporty":
            return [
                StyleIAProductRecommendation(
                    id: "sporty-running-shoes",
                    label: "SHOES",
                    name: "Running shoes",
                    detail: "Light performance trainers that match the active silhouette.",
                    assetModule: .shoes,
                    systemImage: "shoeprints.fill",
                    tint: StyleIATheme.moss,
                    productURL: shopURL("men clean performance trainers")
                ),
                StyleIAProductRecommendation(
                    id: "sporty-gym-bag",
                    label: "BAG",
                    name: "Gym bag",
                    detail: "A compact technical bag keeps the look practical without adding bulk.",
                    assetModule: .accessories,
                    systemImage: "duffle.bag.fill",
                    tint: Color(red: 0.34, green: 0.48, blue: 0.82),
                    productURL: shopURL("men compact gym bag")
                )
            ]
        case "professional":
            return [
                StyleIAProductRecommendation(
                    id: "professional-oxford-shoes",
                    label: "SHOES",
                    name: "Oxford shoes",
                    detail: "Polished leather oxfords ground the tailored office look.",
                    assetModule: .shoes,
                    systemImage: "shoe.2.fill",
                    tint: Color(red: 0.36, green: 0.27, blue: 0.2),
                    productURL: shopURL("men polished leather oxford shoes")
                ),
                StyleIAProductRecommendation(
                    id: "professional-briefcase",
                    label: "BAG",
                    name: "Leather briefcase",
                    detail: "Structured leather keeps the outfit clean and work-ready.",
                    assetModule: .accessories,
                    systemImage: "briefcase.fill",
                    tint: Color(red: 0.18, green: 0.22, blue: 0.28),
                    productURL: shopURL("men structured leather briefcase")
                )
            ]
        case "luxury":
            return [
                StyleIAProductRecommendation(
                    id: "night-out-dress-shoes",
                    label: "SHOES",
                    name: "Dress shoes",
                    detail: "Sleek dress shoes keep the night-out profile sharp.",
                    assetModule: .shoes,
                    systemImage: "shoe.2.fill",
                    tint: Color(red: 0.12, green: 0.1, blue: 0.09),
                    productURL: shopURL("men sleek black dress shoes")
                ),
                StyleIAProductRecommendation(
                    id: "night-out-cologne",
                    label: "SCENT",
                    name: "Evening cologne",
                    detail: "A warm evening scent completes the polished luxury direction.",
                    assetModule: .accessories,
                    systemImage: "drop.fill",
                    tint: StyleIATheme.gold,
                    productURL: shopURL("men warm evening cologne")
                )
            ]
        case "streetwear":
            return [
                StyleIAProductRecommendation(
                    id: "streetwear-sneakers",
                    label: "SHOES",
                    name: "Statement sneakers",
                    detail: "Bold sneakers support the relaxed streetwear proportions.",
                    assetModule: .shoes,
                    systemImage: "shoeprints.fill",
                    tint: Color(red: 0.42, green: 0.56, blue: 0.9),
                    productURL: shopURL("men statement sneakers streetwear")
                ),
                StyleIAProductRecommendation(
                    id: "streetwear-cap",
                    label: "CAP",
                    name: "Clean cap",
                    detail: "A simple cap finishes the look without competing with layers.",
                    assetModule: .accessories,
                    systemImage: "baseball.cap.fill",
                    tint: Color(red: 0.16, green: 0.17, blue: 0.18),
                    productURL: shopURL("men clean streetwear cap")
                )
            ]
        default:
            return [
                StyleIAProductRecommendation(
                    id: "casual-white-sneakers",
                    label: "SHOES",
                    name: "White sneakers",
                    detail: "Low-profile white sneakers keep the casual outfit clean.",
                    assetModule: .shoes,
                    systemImage: "shoeprints.fill",
                    tint: StyleIATheme.moss,
                    productURL: shopURL("men white low profile sneakers")
                ),
                StyleIAProductRecommendation(
                    id: "casual-watch",
                    label: "WATCH",
                    name: "Everyday watch",
                    detail: "A simple watch adds finish without making the outfit formal.",
                    assetModule: .accessories,
                    systemImage: "applewatch",
                    tint: Color(red: 0.55, green: 0.47, blue: 0.36),
                    productURL: shopURL("men simple everyday watch")
                )
            ]
        }
    }

    static func products(for look: StyleIALook) -> [StyleIAProductRecommendation] {
        let backendProducts = (look.products ?? []).compactMap(fromBackend)
        return backendProducts.isEmpty ? products(for: look.styleGoal) : backendProducts
    }

    static func primary(for styleGoal: String, module: StyleIALookAssetModule) -> StyleIAProductRecommendation {
        switch module {
        case .frames:
            return frameProduct(for: styleGoal)
        case .shoes:
            return products(for: styleGoal).first { $0.assetModule == .shoes } ?? products(for: styleGoal)[0]
        case .outfit, .accessories:
            return products(for: styleGoal)[0]
        }
    }

    static func primary(for look: StyleIALook, module: StyleIALookAssetModule) -> StyleIAProductRecommendation {
        let products = products(for: look)
        if let match = products.first(where: { $0.assetModule == module }) {
            return match
        }

        return primary(for: look.styleGoal, module: module)
    }

    private static func fromBackend(_ product: StyleIAProductMatch) -> StyleIAProductRecommendation? {
        let module: StyleIALookAssetModule
        let systemImage: String
        let tint: Color

        switch product.category.lowercased() {
        case "frames", "eyeglasses", "glasses":
            module = .frames
            systemImage = "eyeglasses"
            tint = StyleIATheme.moss
        case "shoes", "footwear", "sneakers":
            module = .shoes
            systemImage = "shoeprints.fill"
            tint = StyleIATheme.moss
        default:
            module = .accessories
            systemImage = "sparkles"
            tint = StyleIATheme.gold
        }

        return StyleIAProductRecommendation(
            id: product.id,
            label: product.category.uppercased(),
            name: product.name,
            detail: product.matchReason,
            assetModule: module,
            systemImage: systemImage,
            tint: tint,
            productURL: product.merchantURL
        )
    }

    private static func frameProduct(for styleGoal: String) -> StyleIAProductRecommendation {
        switch styleGoal {
        case "professional":
            return StyleIAProductRecommendation(
                id: "professional-clear-angular-frames",
                label: "FRAMES",
                name: "Clear angular frames",
                detail: "Transparent angular frames keep the face open while reinforcing a precise work look.",
                assetModule: .frames,
                systemImage: "eyeglasses",
                tint: StyleIATheme.moss,
                productURL: shopURL("men clear angular eyeglasses")
            )
        case "luxury":
            return StyleIAProductRecommendation(
                id: "luxury-rounded-dark-frames",
                label: "FRAMES",
                name: "Rounded dark frames",
                detail: "Rounded dark frames soften sharp lines and add a premium evening finish.",
                assetModule: .frames,
                systemImage: "eyeglasses",
                tint: StyleIATheme.gold,
                productURL: shopURL("men rounded dark eyeglasses")
            )
        case "streetwear":
            return StyleIAProductRecommendation(
                id: "streetwear-bold-acetate-frames",
                label: "FRAMES",
                name: "Bold acetate frames",
                detail: "Heavier acetate frames add visual weight to layered streetwear.",
                assetModule: .frames,
                systemImage: "eyeglasses",
                tint: Color(red: 0.42, green: 0.56, blue: 0.9),
                productURL: shopURL("men bold acetate eyeglasses")
            )
        default:
            return StyleIAProductRecommendation(
                id: "casual-soft-rectangular-frames",
                label: "FRAMES",
                name: "Soft rectangular frames",
                detail: "Soft rectangular frames keep the face balanced and natural.",
                assetModule: .frames,
                systemImage: "eyeglasses",
                tint: StyleIATheme.moss,
                productURL: shopURL("men soft rectangular eyeglasses")
            )
        }
    }

    private static func shopURL(_ query: String) -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://www.google.com/search?tbm=shop&q=\(encoded)")!
    }
}

private struct StyleIAProductCircle: View {
    let product: StyleIAProductRecommendation
    var imageURL: URL?
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: -6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.96))
                Circle()
                    .stroke(product.tint, lineWidth: 3)
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: product.systemImage)
                                .font(.system(size: diameter * 0.33, weight: .bold))
                                .foregroundStyle(product.tint)
                        }
                    }
                    .clipShape(Circle())
                    .padding(4)
                } else {
                    Image(systemName: product.systemImage)
                        .font(.system(size: diameter * 0.33, weight: .bold))
                        .foregroundStyle(product.tint)
                }
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)

            VStack(spacing: 1) {
                Text(product.label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1)
                Text(product.name)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .foregroundStyle(Color.black)
            .frame(width: max(diameter * 0.92, 58))
            .padding(.vertical, 7)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.16), radius: 7, y: 3)
        }
    }
}

private struct StyleIAProductDetailSheet: View {
    let product: StyleIAProductRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                StyleIAProductCircle(product: product, imageURL: nil, diameter: 74)

                VStack(alignment: .leading, spacing: 6) {
                    Text(product.label)
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(2.8)
                        .foregroundStyle(StyleIATheme.moss)
                    Text(product.name)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(StyleIATheme.text)
                }
            }

            Text(product.detail)
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(StyleIATheme.text.opacity(0.82))

            Text("Matched to this generated look based on outfit category, context, and finishing details.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StyleIATheme.moss.opacity(0.78))

            Link(destination: product.productURL) {
                Label("View matching products", systemImage: "bag.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(StyleIATheme.moss)
                    .clipShape(Capsule())
            }
            .buttonStyle(StyleIAPressButtonStyle())

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StyleIATheme.panel)
        .preferredColorScheme(.dark)
    }
}

private struct StyleIASmartGeneratingCard: View {
    let persona: StyleIAPersona
    let selectedPhoto: UIImage?
    let width: CGFloat
    let isLoading: Bool

    @State private var phase = 0
    @State private var scanPulse = false
    @State private var iconIndex = 0

    private var height: CGFloat { min(width * 1.09, 420) }
    private let icons = ["tshirt.fill", "shoeprints.fill", "eyeglasses", "briefcase.fill"]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(StyleIATheme.panel)

            VStack(spacing: 24) {
                smartVisual
                    .frame(height: height * 0.48)

                VStack(spacing: 10) {
                    Text(message)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(StyleIATheme.text)
                        .multilineTextAlignment(.center)
                        .id(phase)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Text("Your first look will appear here as soon as it is ready.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StyleIATheme.moss.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                progressBar
            }
            .padding(24)
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
        .onAppear {
            scanPulse = true
        }
        .task(id: isLoading) {
            guard isLoading else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeInOut(duration: 0.35)) {
                    phase = min(phase + 1, 3)
                    iconIndex = (iconIndex + 1) % icons.count
                }
            }
        }
    }

    @ViewBuilder
    private var smartVisual: some View {
        switch phase {
        case 0:
            ZStack {
                Circle()
                    .stroke(StyleIATheme.moss.opacity(scanPulse ? 0.18 : 0.54), lineWidth: 2)
                    .scaleEffect(scanPulse ? 1.28 : 0.82)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: scanPulse)
                if let selectedPhoto {
                    Image(uiImage: selectedPhoto)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                        .padding(20)
                } else {
                    StyleIAPersonAvatar(persona: persona, expression: .smile)
                        .padding(24)
                }
            }
        case 1:
            HStack(spacing: 18) {
                ForEach(0..<icons.count, id: \.self) { item in
                    Image(systemName: icons[item])
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(item == iconIndex ? StyleIATheme.moss : StyleIATheme.text.opacity(0.22))
                        .frame(width: 54, height: 54)
                        .background(StyleIATheme.surfaceGreen)
                        .clipShape(Circle())
                        .scaleEffect(item == iconIndex ? 1.12 : 1)
                }
            }
        case 2:
            StyleIAShimmerImagePlaceholder()
        default:
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(StyleIATheme.moss)
                Text("90%")
                    .font(.system(size: 42, weight: .regular, design: .serif))
                    .foregroundStyle(StyleIATheme.text)
            }
        }
    }

    private var message: String {
        switch phase {
        case 0:
            return "Analyzing your features..."
        case 1:
            return "Matching styles to your profile..."
        case 2:
            return "Generating your Casual look..."
        default:
            return "Almost ready - adding finishing touches..."
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(StyleIATheme.moss)
                    .frame(width: proxy.size.width * progress)
                    .animation(.easeInOut(duration: 0.45), value: progress)
            }
        }
        .frame(height: 5)
    }

    private var progress: CGFloat {
        switch phase {
        case 0: return 0.18
        case 1: return 0.42
        case 2: return 0.68
        default: return 0.9
        }
    }
}

private struct StyleIAShimmerImagePlaceholder: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(StyleIATheme.surfaceGreen)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.16),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.55)
                    .offset(x: proxy.size.width * offset)
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: offset)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .onAppear { offset = 1.6 }
    }
}

private func displayTitle(for look: StyleIALook) -> String {
    look.styleGoal == "luxury" ? "Night Out Fit" : look.title
}

private struct StyleIATopPickLoadingCard: View {
    let index: Int
    let persona: StyleIAPersona
    let selectedPhoto: UIImage?
    let width: CGFloat

    private var height: CGFloat { min(width * 1.09, 420) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(StyleIATheme.panel)

            VStack {
                Spacer()
                ZStack {
                    Circle().fill(StyleIATheme.moss.opacity(0.14))
                    if let selectedPhoto {
                        Image(uiImage: selectedPhoto)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                            .padding(14)
                    } else {
                        StyleIAPersonAvatar(persona: persona, expression: .smile)
                            .padding(16)
                    }
                }
                .frame(width: 130, height: 130)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                ProgressView().tint(StyleIATheme.moss)
                Text(index == 0 ? "TOP PICK" : "BUILDING LOOK")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(StyleIATheme.text)
            }
            .padding(22)
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

private struct StyleIAFeedModule: Identifiable {
    let id: String
    let title: String
    let items: [StyleIAFeedItem]

    static func modules(for looks: [StyleIALook]) -> [StyleIAFeedModule] {
        [
            StyleIAFeedModule(id: "shoes", title: "SHOES FOR YOUR DAY", items: looks.enumerated().map { index, look in
                let product = StyleIAProductRecommendation.primary(for: look, module: .shoes)
                return StyleIAFeedItem(
                    id: "shoes-\(look.id)",
                    lookIndex: index,
                    imageURL: look.assetURL(for: product.assetModule),
                    title: product.name,
                    body: shoeBody(for: look.styleGoal),
                    badge: product.label,
                    product: product
                )
            }),
            StyleIAFeedModule(id: "frames", title: "FRAMES FOR YOU", items: looks.enumerated().map { index, look in
                let product = StyleIAProductRecommendation.primary(for: look, module: .frames)
                return StyleIAFeedItem(
                    id: "frames-\(look.id)",
                    lookIndex: index,
                    imageURL: look.assetURL(for: product.assetModule),
                    title: product.name,
                    body: frameBody(for: look.styleGoal),
                    badge: product.label,
                    product: product
                )
            })
        ].filter { !$0.items.isEmpty }
    }

    private static func shoeBody(for goal: String) -> String {
        switch goal {
        case "professional": return "Structured leather styles that support a tailored office look."
        case "luxury": return "Sleek polished footwear that holds the evening silhouette."
        case "streetwear": return "Bold soles that keep the layered shape intentional."
        case "sporty": return "Clean performance shapes that keep the outfit athletic."
        default: return "Simple low-profile shoes that balance relaxed proportions."
        }
    }

    private static func frameBody(for goal: String) -> String {
        switch goal {
        case "professional": return "Sharper lines reinforce a clean work-ready face shape."
        case "luxury": return "Rounded shapes soften the jaw while keeping the look elevated."
        case "streetwear": return "Heavier frames add visual weight to layered outfits."
        default: return "Balanced proportions that keep the face open and natural."
        }
    }
}

private struct StyleIAFeedItem: Identifiable {
    let id: String
    let lookIndex: Int
    let imageURL: URL?
    let title: String
    let body: String
    let badge: String
    let product: StyleIAProductRecommendation
}

private struct StyleIAFeedModuleSection: View {
    let module: StyleIAFeedModule
    let layout: StyleIALayout
    let onSelectLook: (Int) -> Void

    private var cardWidth: CGFloat {
        layout.feedCardWidth
    }

    private var cardHeight: CGFloat {
        layout.feedCardHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(module.title)
                .font(.system(size: 25, weight: .regular, design: .serif))
                .foregroundStyle(StyleIATheme.text.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.sidePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(module.items) { item in
                        StyleIAFeedModuleCard(item: item, width: cardWidth, height: cardHeight) {
                            onSelectLook(item.lookIndex)
                        }
                    }
                }
                .padding(.horizontal, layout.sidePadding)
            }
        }
    }
}

private struct StyleIAFeedModuleCard: View {
    let item: StyleIAFeedItem
    let width: CGFloat
    let height: CGFloat
    let onSelectLook: () -> Void

    private var imageWidth: CGFloat { min(width * 0.52, width - 132) }
    private var infoWidth: CGFloat { max(width - imageWidth, 120) }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let imageURL = item.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            StyleIALookImageFallback()
                        default:
                            StyleIALookImageLoading()
                        }
                    }
                } else {
                    StyleIAAssetGeneratingPlaceholder(badge: item.badge)
                }
            }
            .frame(width: imageWidth, height: height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelectLook)

            VStack(alignment: .leading, spacing: 12) {
                Text(item.body)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StyleIATheme.text.opacity(0.9))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)

                Link(destination: item.product.productURL) {
                    StyleIAInlineProductLink(
                        product: item.product,
                        imageURL: item.imageURL,
                        width: max(infoWidth - 28, 88)
                    )
                }
                .buttonStyle(StyleIAPressButtonStyle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2.2)
                        .lineLimit(1)
                    Button(action: onSelectLook) {
                        Text("Tap to view full look")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StyleIATheme.moss)
                    }
                    .buttonStyle(StyleIAPressButtonStyle())
                }
                .foregroundStyle(StyleIATheme.text)
            }
            .padding(16)
            .frame(width: infoWidth, height: height, alignment: .leading)
            .background(Color.white.opacity(0.04))
        }
        .frame(width: width, height: height)
        .background(StyleIATheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

private struct StyleIAInlineProductLink: View {
    let product: StyleIAProductRecommendation
    let imageURL: URL?
    let width: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)

                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Image(systemName: product.systemImage)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(StyleIATheme.moss)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .padding(4)
                } else {
                    Image(systemName: product.systemImage)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(StyleIATheme.moss)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(product.label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(product.tint)
                    .clipShape(Capsule())

                Text("View product")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StyleIATheme.moss)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct StyleIAAssetGeneratingPlaceholder: View {
    let badge: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    StyleIATheme.surfaceGreen,
                    StyleIATheme.panel,
                    StyleIATheme.surfaceGreen.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(StyleIATheme.moss.opacity(pulse ? 0.16 : 0.48), lineWidth: 2)
                        .frame(width: 104, height: 104)
                        .scaleEffect(pulse ? 1.18 : 0.92)
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(StyleIATheme.moss)
                        .frame(width: 72, height: 72)
                        .background(StyleIATheme.moss.opacity(0.12))
                        .clipShape(Circle())
                }

                VStack(spacing: 5) {
                    Text("GENERATING")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2.6)
                    Text(badge)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                }
                .foregroundStyle(StyleIATheme.text.opacity(0.78))
            }
        }
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
    }

    private var icon: String {
        switch badge {
        case "SHOES":
            return "shoeprints.fill"
        case "FRAMES":
            return "eyeglasses"
        default:
            return "sparkles"
        }
    }
}

private struct StyleIAFeedCircleAction: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 48, height: 48)
            .background(Color.black.opacity(0.72))
            .clipShape(Circle())
    }
}

private struct StyleIAInsightStrip: View {
    let recommendations: StyleIARecommendations

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(recommendations.bullets, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StyleIATheme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(StyleIATheme.panel.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(StyleIATheme.hairline, lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct StyleIAProfileCard: View {
    let persona: StyleIAPersona
    let layout: StyleIALayout
    let selectedPhoto: UIImage?
    let recommendations: StyleIARecommendations

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STYLEIA\nSESSION")
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text("SUMMER\n2026")
            }
            .font(.system(size: 13, weight: .bold))
            .tracking(4)
            .foregroundStyle(Color.black.opacity(0.76))
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(StyleIATheme.moss)

            VStack(spacing: 20) {
                if !recommendations.tags.isEmpty {
                    let display = Array(recommendations.tags.prefix(3))
                    HStack(spacing: 18) {
                        ForEach(display, id: \.self) { tag in
                            StyleIATag(tag.uppercased(), isFilled: false)
                        }
                    }
                }

                ZStack {
                    Circle()
                        .fill(StyleIATheme.moss.opacity(0.17))
                    Circle()
                        .stroke(StyleIATheme.moss, lineWidth: 4)
                    if let image = selectedPhoto {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                            .padding(12)
                    } else {
                        StyleIAPersonAvatar(persona: persona, expression: .smile)
                            .padding(12)
                    }
                }
                .frame(width: layout.profileAvatarSize, height: layout.profileAvatarSize)

                if !recommendations.title.isEmpty {
                    Text(recommendations.title)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(StyleIATheme.moss)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay {
                            Capsule()
                                .stroke(StyleIATheme.moss, lineWidth: 1.5)
                        }
                }

                if !recommendations.bullets.isEmpty {
                    VStack(spacing: 10) {
                        Text("Recommendations")
                            .font(.system(size: layout.resultTitleSize, weight: .regular, design: .serif))
                            .foregroundStyle(StyleIATheme.text)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(recommendations.bullets, id: \.self) { item in
                                Text("• \(item)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(StyleIATheme.moss.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        }
        .background(StyleIATheme.panel.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

private struct StyleIALookImageLoading: View {
    var body: some View {
        ZStack {
            StyleIATheme.surfaceGreen
            ProgressView()
                .tint(StyleIATheme.moss)
        }
    }
}

private struct StyleIALookImageFallback: View {
    var body: some View {
        ZStack {
            StyleIATheme.surfaceGreen
            Image(systemName: "photo")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(StyleIATheme.moss.opacity(0.72))
        }
    }
}

private struct StyleIALookDetailOverlay: View {
    let looks: [StyleIALook]
    @Binding var selectedIndex: Int
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                        StyleIALookDetailPage(
                            look: look,
                            index: index,
                            count: looks.count,
                            size: proxy.size,
                            onClose: onClose
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }
}

private struct StyleIALookDetailPage: View {
    let look: StyleIALook
    let index: Int
    let count: Int
    let size: CGSize
    let onClose: () -> Void

    @State private var isSaving = false
    @State private var notice: String?
    @State private var didLike = false
    @State private var didDislike = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: look.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    StyleIALookDetailFallback()
                default:
                    StyleIALookDetailLoading()
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.14),
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                StyleIALookDetailTopBar(
                    look: look,
                    index: index,
                    count: count,
                    onDownload: { saveLook(message: "Saved to Photos") },
                    onClose: onClose
                )
                    .padding(.top, 10)
                    .padding(.horizontal, 22)

                Spacer()

                VStack(spacing: 4) {
                    Text("WALK AROUND")
                        .font(.system(size: 24, weight: .heavy))
                        .tracking(4.5)
                        .foregroundStyle(Color.white)

                    Text(displayTitle(for: look).uppercased())
                        .font(.system(size: min(size.width * 0.18, 74), weight: .regular, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [StyleIATheme.gold, Color.white, StyleIATheme.moss],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 10, y: 5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)

                StyleIALookShopTray(
                    look: look,
                    isSaving: isSaving,
                    didLike: didLike,
                    didDislike: didDislike,
                    onAddToLockscreen: { saveLook(message: "Saved to Photos for Lock Screen") },
                    onDownload: { saveLook(message: "Saved to Photos") },
                    onLike: {
                        didLike.toggle()
                        if didLike { didDislike = false }
                        showNotice(didLike ? "Added to favorites" : "Removed from favorites")
                    },
                    onDislike: {
                        didDislike.toggle()
                        if didDislike { didLike = false }
                        showNotice(didDislike ? "Feedback saved" : "Feedback removed")
                    }
                )
            }

            if let notice {
                VStack {
                    Spacer()
                    Text(notice)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                        .padding(.bottom, 156)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func saveLook(message: String) {
        guard !isSaving else { return }

        isSaving = true
        Task {
            do {
                try await StyleIALookPhotoSaver.saveImage(from: look.imageURL)
                await MainActor.run {
                    isSaving = false
                    showNotice(message)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    showNotice((error as? LocalizedError)?.errorDescription ?? "Could not save image")
                }
            }
        }
    }

    private func showNotice(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            notice = message
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if notice == message {
                    withAnimation(.easeOut(duration: 0.2)) {
                        notice = nil
                    }
                }
            }
        }
    }
}

private struct StyleIALookDetailTopBar: View {
    let look: StyleIALook
    let index: Int
    let count: Int
    let onDownload: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.36))
                    .clipShape(Circle())
            }
            .buttonStyle(StyleIAPressButtonStyle())

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { item in
                    Capsule()
                        .fill(item == index ? Color.white : Color.white.opacity(0.3))
                        .frame(width: item == index ? 30 : 18, height: 4)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 37)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())

            Spacer()

            ShareLink(item: look.imageURL) {
                StyleIALookCircleIcon(systemImage: "square.and.arrow.up")
            }

            StyleIALookCircleButton(systemImage: "arrow.down.to.line", action: onDownload)
        }
        .foregroundStyle(Color.white.opacity(0.9))
    }
}

private struct StyleIALookShopTray: View {
    let look: StyleIALook
    let isSaving: Bool
    let didLike: Bool
    let didDislike: Bool
    let onAddToLockscreen: () -> Void
    let onDownload: () -> Void
    let onLike: () -> Void
    let onDislike: () -> Void

    @State private var selectedProduct: StyleIAProductRecommendation?

    private var products: [StyleIAProductRecommendation] {
        StyleIAProductRecommendation.products(for: look)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SHOP\nSIMILAR PRODUCTS")
                        .font(.system(size: 19, weight: .heavy))
                        .tracking(1.8)
                        .foregroundStyle(Color.black.opacity(0.58))
                        .lineSpacing(5)

                    Text(productSummary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .lineLimit(2)

                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 130, height: 1)
                }

                Spacer()

                HStack(spacing: 14) {
                    ForEach(products.prefix(2)) { product in
                        Button {
                            selectedProduct = product
                        } label: {
                            StyleIAProductCircle(
                                product: product,
                                imageURL: look.imageURL(for: product.assetModule),
                                diameter: 62
                            )
                        }
                        .buttonStyle(StyleIAPressButtonStyle())
                    }
                }
            }

            HStack(spacing: 13) {
                Button(action: onAddToLockscreen) {
                    Text(isSaving ? "Saving..." : "Add to Lock Screen")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(StyleIAPressButtonStyle())
                .disabled(isSaving)

                StyleIALookCircleButton(systemImage: didLike ? "hand.thumbsup.fill" : "hand.thumbsup", action: onLike, dark: true, isSelected: didLike)

                ShareLink(item: look.imageURL) {
                    StyleIALookCircleIcon(systemImage: "arrowshape.turn.up.right", dark: true)
                }

                StyleIALookCircleButton(systemImage: "arrow.down.to.line", action: onDownload, dark: true)
                    .disabled(isSaving)

                StyleIALookCircleButton(systemImage: didDislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", action: onDislike, dark: true, isSelected: didDislike)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 26)
        .padding(.bottom, max(bottomInset + 18, 32))
        .background(Color(red: 0.86, green: 0.86, blue: 0.85))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .ignoresSafeArea(edges: .bottom)
        .sheet(item: $selectedProduct) { product in
            StyleIAProductDetailSheet(product: product)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var productSummary: String {
        let names = products.prefix(2).map(\.name)
        return names.isEmpty ? look.subtitle : names.joined(separator: " + ")
    }

    private var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom }
            .first ?? 0
    }
}

private struct StyleIALookCircleButton: View {
    let systemImage: String
    let action: () -> Void
    var dark = false
    var isSelected = false

    var body: some View {
        Button(action: action) {
            StyleIALookCircleIcon(systemImage: systemImage, dark: dark, isSelected: isSelected)
        }
        .buttonStyle(StyleIAPressButtonStyle())
    }
}

private struct StyleIALookCircleIcon: View {
    let systemImage: String
    var dark = false
    var isSelected = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: dark ? 44 : 52, height: dark ? 44 : 52)
            .background(background)
            .clipShape(Circle())
    }

    private var foreground: Color {
        if isSelected {
            return dark ? Color.white : Color.black
        }

        return dark ? Color.black.opacity(0.8) : Color.white.opacity(0.9)
    }

    private var background: Color {
        if isSelected {
            return dark ? Color.black.opacity(0.78) : Color.white.opacity(0.9)
        }

        return dark ? Color.black.opacity(0.12) : Color.black.opacity(0.36)
    }
}

private struct StyleIALookDetailLoading: View {
    var body: some View {
        ZStack {
            StyleIATheme.surfaceGreen
            ProgressView()
                .tint(StyleIATheme.moss)
        }
    }
}

private struct StyleIALookDetailFallback: View {
    var body: some View {
        ZStack {
            StyleIATheme.surfaceGreen
            Image(systemName: "photo")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(StyleIATheme.moss)
        }
    }
}

private struct StyleIABeforeAfterTile: View {
    let title: String
    let subtitle: String
    let remoteURL: URL?
    let image: UIImage?
    let persona: StyleIAPersona
    let glasses: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(4)
                .foregroundStyle(StyleIATheme.moss.opacity(0.32))

            ZStack {
                Circle()
                    .fill(StyleIATheme.surfaceGreen)

                if let remoteURL {
                    AsyncImage(url: remoteURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            StyleIAPersonAvatar(persona: persona, expression: .smile, glassesOverride: glasses)
                                .padding(8)
                        default:
                            ProgressView()
                                .tint(StyleIATheme.moss)
                        }
                    }
                    .clipShape(Circle())
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    StyleIAPersonAvatar(persona: persona, expression: .smile, glassesOverride: glasses)
                        .padding(8)
                }
            }
            .frame(width: 72, height: 72)
            .overlay {
                Circle()
                    .stroke(glasses ? StyleIATheme.moss : .clear, lineWidth: 2)
            }

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(glasses ? StyleIATheme.moss : StyleIATheme.moss.opacity(0.34))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct StyleIAPrimaryButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(StyleIATheme.moss)
            .clipShape(Capsule())
            .opacity(isDisabled ? 0.62 : 1)
        }
        .disabled(isDisabled)
        .buttonStyle(StyleIAPressButtonStyle())
    }
}

private struct StyleIASecondaryAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(StyleIATheme.moss)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(StyleIATheme.panel.opacity(0.85))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(StyleIATheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(StyleIAPressButtonStyle())
    }
}

private struct StyleIATag: View {
    let text: String
    let isFilled: Bool

    init(_ text: String, isFilled: Bool = false) {
        self.text = text
        self.isFilled = isFilled
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(2.4)
            .foregroundStyle(isFilled ? Color.black.opacity(0.72) : StyleIATheme.moss.opacity(0.75))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isFilled ? StyleIATheme.moss : .clear)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isFilled ? .clear : StyleIATheme.hairline, lineWidth: 1)
            }
    }
}

private struct StyleIATinyTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(2.2)
            .foregroundStyle(StyleIATheme.moss.opacity(0.58))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(StyleIATheme.surfaceGreen)
            .clipShape(Capsule())
    }
}

private struct StyleIAPersonAvatar: View {
    enum Expression {
        case neutral
        case smile
    }

    let persona: StyleIAPersona
    let expression: Expression
    var glassesOverride: Bool?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let unit = min(width, height)
            let glasses = glassesOverride ?? persona.hasGlasses

            ZStack {
                Capsule()
                    .fill(persona.shirt)
                    .frame(width: unit * 0.68, height: unit * 0.42)
                    .offset(y: unit * 0.31)

                Circle()
                    .fill(persona.skin)
                    .frame(width: unit * 0.5, height: unit * 0.5)
                    .offset(y: -unit * 0.05)

                Circle()
                    .trim(from: 0.48, to: 1)
                    .stroke(persona.hair, style: StrokeStyle(lineWidth: unit * 0.055, lineCap: .round))
                    .frame(width: unit * 0.55, height: unit * 0.55)
                    .offset(y: -unit * 0.07)

                HStack(spacing: unit * 0.14) {
                    Circle()
                        .fill(StyleIATheme.deepBlack)
                    Circle()
                        .fill(StyleIATheme.deepBlack)
                }
                .frame(width: unit * 0.25, height: unit * 0.035)
                .offset(y: -unit * 0.05)

                if glasses {
                    HStack(spacing: unit * 0.05) {
                        RoundedRectangle(cornerRadius: unit * 0.03, style: .continuous)
                            .stroke(StyleIATheme.moss, lineWidth: unit * 0.026)
                            .frame(width: unit * 0.16, height: unit * 0.11)
                        RoundedRectangle(cornerRadius: unit * 0.03, style: .continuous)
                            .stroke(StyleIATheme.moss, lineWidth: unit * 0.026)
                            .frame(width: unit * 0.16, height: unit * 0.11)
                    }
                    .offset(y: -unit * 0.055)
                }

                Path { path in
                    let y = height * (expression == .smile ? 0.48 : 0.5)
                    path.move(to: CGPoint(x: width * 0.43, y: y))
                    path.addQuadCurve(to: CGPoint(x: width * 0.57, y: y), control: CGPoint(x: width * 0.5, y: y + unit * 0.06))
                }
                .stroke(StyleIATheme.deepBlack, lineWidth: max(1.4, unit * 0.018))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StyleIABackground: View {
    var body: some View {
        ZStack {
            StyleIATheme.deepBlack.ignoresSafeArea()

            RadialGradient(
                colors: [StyleIATheme.moss.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 440
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [StyleIATheme.moss.opacity(0.11), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.1), .black.opacity(0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(StyleIATheme.moss)
                Text("Processing…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StyleIATheme.text)
            }
            .padding(18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(StyleIATheme.hairline, lineWidth: 1) }
        }
    }
}

private enum StyleIALookPhotoSaveError: Error, LocalizedError {
    case denied
    case invalidResponse
    case emptyImage

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Photo access is required to save this look."
        case .invalidResponse:
            return "Could not download the generated look."
        case .emptyImage:
            return "The generated look image was empty."
        }
    }
}

private enum StyleIALookPhotoSaver {
    static func saveImage(from url: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard
            let http = response as? HTTPURLResponse,
            200..<300 ~= http.statusCode
        else {
            throw StyleIALookPhotoSaveError.invalidResponse
        }

        guard !data.isEmpty else {
            throw StyleIALookPhotoSaveError.emptyImage
        }

        try await requestPhotoAccess()
        try await save(data: data)
    }

    private static func requestPhotoAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if requested == .authorized || requested == .limited {
                return
            }
            throw StyleIALookPhotoSaveError.denied
        default:
            throw StyleIALookPhotoSaveError.denied
        }
    }

    private static func save(data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: StyleIALookPhotoSaveError.invalidResponse)
                }
            }
        }
    }
}

struct StyleIAPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
