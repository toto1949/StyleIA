import PhotosUI
import SwiftUI

@MainActor
struct SceneMeRootView: View {
    @StateObject private var viewModel: SceneMeViewModel

    init() {
        _viewModel = StateObject(wrappedValue: SceneMeViewModel())
    }

    init(viewModel: SceneMeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if !viewModel.isAuthenticated {
                AuthView(viewModel: viewModel)
                    .transition(.opacity)
            } else {
                switch viewModel.flow {
                case .home:
                    tabContent
                    SceneMeTabBar(viewModel: viewModel)
                case .scenePicker:
                    ScenePickerView(viewModel: viewModel)
                case .sceneOptions:
                    SceneOptionsView(viewModel: viewModel)
                case .generating:
                    GeneratingView(viewModel: viewModel)
                case .result:
                    ResultView(viewModel: viewModel)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isAuthenticated)
        .task {
            // Start StoreKit listener after the run loop is ready to prevent
            // the OS_dispatch_mach_msg crash that occurs on early init.
            viewModel.subscriptionService.start()
        }
        .sheet(item: $viewModel.paywallTrigger) { trigger in
            PaywallView(trigger: trigger) {
                viewModel.paywallTrigger = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .background(SceneMeTheme.ink.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(SceneMeTheme.gold)
        .overlay(alignment: .top) {
            noticeBanner
        }
        .onChange(of: viewModel.photoItem) { _, _ in
            Task {
                await viewModel.loadSelectedPhoto()
            }
        }
        .task {
            await viewModel.refreshScenes()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.tab {
        case .home:
            HomeView(viewModel: viewModel)
        case .explore:
            ExploreView(viewModel: viewModel)
        case .gallery:
            GalleryView(viewModel: viewModel)
        case .profile:
            ProfileView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = viewModel.notice {
            Text(notice)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SceneMeTheme.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(SceneMeTheme.surface.opacity(0.97))
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(SceneMeTheme.gold.opacity(0.4), lineWidth: 1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(3.2))
                    withAnimation {
                        viewModel.notice = nil
                    }
                }
                .onTapGesture {
                    withAnimation {
                        viewModel.notice = nil
                    }
                }
        }
    }
}

/// Custom bottom tab bar with a center "+" action that starts a new generation.
private struct SceneMeTabBar: View {
    @ObservedObject var viewModel: SceneMeViewModel

    var body: some View {
        HStack {
            tabButton(.home)
            tabButton(.explore)

            centerButton

            tabButton(.gallery)
            tabButton(.profile)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            SceneMeTheme.ink.opacity(0.97)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(SceneMeTheme.hairline)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: SceneMeTab) -> some View {
        let isSelected = viewModel.tab == tab

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                viewModel.tab = tab
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 18, weight: .regular))

                Text(tab.title.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.faintText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    @ViewBuilder
    private var centerButton: some View {
        Group {
            if viewModel.userPhoto != nil {
                Button {
                    viewModel.move(to: .scenePicker)
                } label: {
                    centerLabel
                }
                .buttonStyle(SceneMePressButtonStyle())
            } else {
                PhotosPicker(selection: $viewModel.photoItem, matching: .images) {
                    centerLabel
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var centerLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(Circle())
            .shadow(color: SceneMeTheme.gold.opacity(0.4), radius: 12, y: 4)
            .offset(y: -14)
    }
}

/// Explore tab — browse every scene by category.
private struct ExploreView: View {
    @ObservedObject var viewModel: SceneMeViewModel
    @State private var category: SceneCategory?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Explore Scenes")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(SceneMeTheme.text)
                    .padding(.top, 16)

                chips

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filtered) { scene in
                        SceneCardView(scene: scene, height: 200) {
                            viewModel.selectScene(scene)
                            if viewModel.userPhoto != nil {
                                viewModel.move(to: .sceneOptions)
                            } else {
                                viewModel.notice = "Upload your photo first to enter this scene."
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(SceneMeTheme.ink)
    }

    private var filtered: [SceneTemplate] {
        guard let category else {
            return viewModel.scenes
        }
        return viewModel.scenes.filter { $0.category == category }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: category == nil) { category = nil }

                ForEach(SceneCategory.pickerCases) { item in
                    chip(title: item.title, isSelected: category == item) { category = item }
                }
            }
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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
                .overlay {
                    Capsule().stroke(isSelected ? Color.clear : SceneMeTheme.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }
}

/// Gallery tab — full generation history with a favorites filter.
private struct GalleryView: View {
    @ObservedObject var viewModel: SceneMeViewModel
    @State private var favoritesOnly = false

    private var results: [GenerationResult] {
        favoritesOnly ? viewModel.favoriteResults : viewModel.history
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Gallery")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(SceneMeTheme.text)

                    if !results.isEmpty {
                        Text("Long-press a scene to favorite or delete it.")
                            .font(.system(size: 12))
                            .foregroundStyle(SceneMeTheme.faintText)
                    }
                }
                .padding(.top, 16)

                galleryFilter

                if results.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: favoritesOnly ? "heart" : "sparkles.rectangle.stack")
                            .font(.system(size: 28))
                            .foregroundStyle(SceneMeTheme.faintText)

                        Text(favoritesOnly ? "Tap the heart on a result to keep it here." : "Generate your first scene from Home.")
                            .font(.system(size: 13))
                            .foregroundStyle(SceneMeTheme.subtleText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(results) { result in
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
            .padding(.horizontal, 22)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(SceneMeTheme.ink)
    }

    private var galleryFilter: some View {
        HStack(spacing: 8) {
            filterChip(title: "All", count: viewModel.history.count, isSelected: !favoritesOnly) {
                favoritesOnly = false
            }
            filterChip(title: "Favorites", count: viewModel.favoriteResults.count, isSelected: favoritesOnly) {
                favoritesOnly = true
            }
            Spacer()
        }
    }

    private func filterChip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                action()
            }
        } label: {
            HStack(spacing: 6) {
                if title == "Favorites" {
                    Image(systemName: isSelected ? "heart.fill" : "heart")
                        .font(.system(size: 10, weight: .bold))
                }

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)

                Text("\(count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.6) : SceneMeTheme.faintText)
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.88) : SceneMeTheme.subtleText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? SceneMeTheme.gold : SceneMeTheme.panel)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(isSelected ? Color.clear : SceneMeTheme.hairline, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SceneMePressButtonStyle())
    }
}

/// Profile tab — avatar, stats, account actions and connection details.
private struct ProfileView: View {
    @ObservedObject var viewModel: SceneMeViewModel
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(SceneMeTheme.panel)
                            .frame(width: 100, height: 100)
                            .overlay {
                                Circle().stroke(SceneMeTheme.gold.opacity(0.6), lineWidth: 1.5)
                            }

                        if let photo = viewModel.userPhoto {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 92, height: 92)
                                .clipShape(Circle())
                        } else {
                            Text(viewModel.profile.initial)
                                .font(.system(size: 36, weight: .regular, design: .serif))
                                .foregroundStyle(SceneMeTheme.gold)
                        }
                    }

                    VStack(spacing: 4) {
                        Text(viewModel.profile.displayName)
                            .font(.system(size: 24, weight: .regular, design: .serif))
                            .foregroundStyle(SceneMeTheme.text)

                        if let email = viewModel.session?.email, !email.isEmpty {
                            Text(email)
                                .font(.system(size: 13))
                                .foregroundStyle(SceneMeTheme.subtleText)
                        }
                    }
                }
                .padding(.top, 30)

                HStack(spacing: 10) {
                    metric(value: "\(viewModel.history.count)", label: "Scenes Made")
                    metric(value: "\(viewModel.favoriteIds.count)", label: "Favorites")
                    metric(value: "\(viewModel.scenes.count)", label: "Destinations")
                }

                subscriptionCard

                #if DEBUG
                debugTierCard
                #endif

                passportCard

                VStack(spacing: 4) {
                    row(icon: "photo", title: "Photo", value: viewModel.userPhoto == nil ? "Not uploaded" : "Uploaded")
                    row(icon: "number", title: "Version", value: versionText)
                }
                .padding(16)
                .background(SceneMeTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                        .stroke(SceneMeTheme.hairline, lineWidth: 1)
                }

                accountActions
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(SceneMeTheme.ink)
        .confirmationDialog("Sign out of SceneMe?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $confirmDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await viewModel.deleteAccount()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account, uploaded photos and all generations will be permanently deleted from the server.")
        }
    }

    private var subscriptionCard: some View {
        let tier = viewModel.currentTier
        let remaining = viewModel.generationsRemainingThisMonth

        return VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tier.displayName.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(tier == .free ? SceneMeTheme.subtleText : Color.black.opacity(0.88))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(tier == .free ? SceneMeTheme.surface : SceneMeTheme.gold)
                            .clipShape(Capsule())

                        if tier == .free, let left = remaining {
                            Text("\(left) gen\(left == 1 ? "" : "s") left this month")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(left == 0 ? Color(red: 0.95, green: 0.45, blue: 0.42) : SceneMeTheme.subtleText)
                        }
                    }

                    Text(tier == .free ? "Upgrade to unlock all features" : "Manage your subscription anytime")
                        .font(.system(size: 12))
                        .foregroundStyle(SceneMeTheme.subtleText)
                }

                Spacer()

                Image(systemName: tier == .free ? "crown" : "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(SceneMeTheme.gold)
            }

            if tier == .free {
                SceneMeCTAButton(
                    title: "Upgrade to Creator",
                    systemImage: "crown"
                ) {
                    viewModel.paywallTrigger = .manualUpgrade
                }
                .frame(height: 48)
            } else {
                HStack(spacing: 10) {
                    Button {
                        viewModel.paywallTrigger = .manualUpgrade
                    } label: {
                        Text("VIEW PLANS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(SceneMeTheme.gold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(SceneMeTheme.gold.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(SceneMePressButtonStyle())

                    Button {
                        Task {
                            if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                                await UIApplication.shared.open(url)
                            }
                        }
                    } label: {
                        Text("MANAGE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(SceneMeTheme.subtleText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(SceneMeTheme.panel)
                            .clipShape(Capsule())
                            .overlay { Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1) }
                    }
                    .buttonStyle(SceneMePressButtonStyle())
                }
            }
        }
        .padding(16)
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                .stroke(tier == .free ? SceneMeTheme.hairline : SceneMeTheme.gold.opacity(0.35), lineWidth: 1)
        }
    }

    #if DEBUG
    /// Debug-only tier simulator: force Free / Creator / Pro without StoreKit.
    /// Not compiled into Release builds.
    private var debugTierCard: some View {
        let service = viewModel.subscriptionService

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DEV · SIMULATE TIER")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(SceneMeTheme.subtleText)

                Spacer()

                Image(systemName: "hammer.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SceneMeTheme.subtleText)
            }

            HStack(spacing: 8) {
                debugTierChip(title: "Live", isSelected: service.debugTierOverride == nil) {
                    service.debugTierOverride = nil
                }
                ForEach([SubscriptionTier.free, .creator, .pro], id: \.rawValue) { tier in
                    debugTierChip(title: tier.displayName, isSelected: service.debugTierOverride == tier) {
                        service.debugTierOverride = tier
                    }
                }
            }

            Text("Overrides the subscription for testing. \"Live\" uses the real StoreKit entitlement. Debug builds only — never ships to the App Store.")
                .font(.system(size: 10))
                .foregroundStyle(SceneMeTheme.faintText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                .stroke(SceneMeTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
    }

    private func debugTierChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(isSelected ? Color.black.opacity(0.88) : SceneMeTheme.subtleText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isSelected ? SceneMeTheme.gold : SceneMeTheme.surface)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(SceneMePressButtonStyle())
    }
    #endif

    /// Scene Passport — a collectible record of every destination visited.
    private var passportCard: some View {
        let catalog = viewModel.scenes.filter { !$0.isCustom }
        let visitedIds = Set(viewModel.history.map(\.sceneId))
        let visitedCount = catalog.filter { visitedIds.contains($0.id) }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SCENE PASSPORT")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(SceneMeTheme.gold)

                    Text(visitedCount == catalog.count && !catalog.isEmpty
                        ? "Every destination visited — world traveler!"
                        : "\(visitedCount) of \(catalog.count) destinations visited")
                        .font(.system(size: 13))
                        .foregroundStyle(SceneMeTheme.subtleText)
                }

                Spacer()

                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(SceneMeTheme.gold)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(catalog) { scene in
                    passportStamp(scene: scene, visited: visitedIds.contains(scene.id))
                }
            }
        }
        .padding(16)
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                .stroke(SceneMeTheme.hairline, lineWidth: 1)
        }
    }

    private func passportStamp(scene: SceneTemplate, visited: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: visited ? "checkmark.seal.fill" : "circle.dashed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(visited ? SceneMeTheme.gold : SceneMeTheme.faintText)

            Text(scene.name)
                .font(.system(size: 10, weight: visited ? .semibold : .regular))
                .foregroundStyle(visited ? SceneMeTheme.text : SceneMeTheme.faintText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(visited ? SceneMeTheme.gold.opacity(0.08) : SceneMeTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                .stroke(visited ? SceneMeTheme.gold.opacity(0.35) : SceneMeTheme.hairline, lineWidth: 1)
        }
    }

    private var accountActions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await viewModel.subscriptionService.restorePurchases() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("RESTORE PURCHASES")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(SceneMeTheme.subtleText)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(SceneMeTheme.panel)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(SceneMePressButtonStyle())

            Button {
                confirmSignOut = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text("SIGN OUT")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(SceneMeTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(SceneMeTheme.panel)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(SceneMePressButtonStyle())

            Button {
                confirmDeleteAccount = true
            } label: {
                Text("Delete account and all data")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.42).opacity(0.85))
            }
            .buttonStyle(SceneMePressButtonStyle())
            .padding(.top, 2)
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.text)

            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(SceneMeTheme.subtleText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                .stroke(SceneMeTheme.hairline, lineWidth: 1)
        }
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SceneMeTheme.gold)
                .frame(width: 30, height: 30)
                .background(SceneMeTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(SceneMeTheme.subtleText)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SceneMeTheme.text.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
    }
}
