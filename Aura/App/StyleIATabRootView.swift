import Combine
import SwiftUI
import UIKit

@MainActor
struct StyleIATabRootView: View {
    @StateObject private var flow: StyleIAFlowViewModel
    @StateObject private var favorites = StyleIAFavoritesStore()

    init() {
        _flow = StateObject(wrappedValue: StyleIAFlowViewModel())
    }

    init(flow: StyleIAFlowViewModel) {
        _flow = StateObject(wrappedValue: flow)
    }

    var body: some View {
        TabView {
            NavigationStack {
                StyleIAExperienceView(viewModel: flow)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                MyLooksView(flow: flow)
                    .navigationTitle("My Looks")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("My Looks", systemImage: "rectangle.stack.person.crop.fill")
            }

            NavigationStack {
                SavedLooksView(flow: flow)
                    .navigationTitle("Saved")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Saved", systemImage: "heart.fill")
            }

            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }

            NavigationStack {
                ProfileView(flow: flow)
                    .navigationTitle("Profile")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
        }
        .tint(StyleIATheme.moss)
        .preferredColorScheme(.dark)
        .environmentObject(favorites)
    }
}

private struct MyLooksView: View {
    @ObservedObject var flow: StyleIAFlowViewModel

    var body: some View {
        ZStack {
            StyleIATabBackground()

            if flow.generatedLooks.isEmpty {
                StyleIAEmptyTabState(
                    systemImage: "sparkles.rectangle.stack",
                    title: "No looks yet",
                    message: "Generate a style card from Home and your finished looks will appear here in a responsive grid."
                )
            } else {
                GeometryReader { proxy in
                    let layout = StyleIALayout(size: proxy.size)

                    VStack(spacing: 0) {
                        StyleIALooksTabHeader(
                            eyebrow: "Your wardrobe",
                            title: "My Looks",
                            subtitle: "Every outfit generated in your latest session.",
                            count: flow.generatedLooks.count
                        )
                        .padding(.horizontal, layout.sidePadding)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        StyleIALooksResponsiveGrid(looks: flow.generatedLooks, layout: layout)
                    }
                }
            }
        }
    }
}

private struct SavedLooksView: View {
    @ObservedObject var flow: StyleIAFlowViewModel
    @EnvironmentObject private var favorites: StyleIAFavoritesStore

    private var savedLooks: [StyleIALook] {
        favorites.favoriteLooks(from: flow.generatedLooks)
    }

    var body: some View {
        ZStack {
            StyleIATabBackground()

            if savedLooks.isEmpty {
                StyleIAEmptyTabState(
                    systemImage: "heart",
                    title: "Nothing saved",
                    message: "Tap the heart on any generated look to keep it here for quick access."
                )
            } else {
                GeometryReader { proxy in
                    let layout = StyleIALayout(size: proxy.size)

                    VStack(spacing: 0) {
                        StyleIALooksTabHeader(
                            eyebrow: "Curated",
                            title: "Saved Looks",
                            subtitle: "Your favorite outfits, ready to revisit or share.",
                            count: savedLooks.count
                        )
                        .padding(.horizontal, layout.sidePadding)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        StyleIALooksResponsiveGrid(looks: savedLooks, layout: layout)
                    }
                }
            }
        }
    }
}

private struct ProfileView: View {
    @ObservedObject var flow: StyleIAFlowViewModel
    @EnvironmentObject private var favorites: StyleIAFavoritesStore

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 14) {
                        StyleIAProfileAvatar(image: flow.selectedPhoto)

                        VStack(spacing: 4) {
                            Text("StyleIA Profile")
                                .font(.system(size: 28, weight: .regular, design: .serif))
                                .italic()
                                .foregroundStyle(StyleIATheme.text)

                            Text(flow.selectedPersona.displayName)
                                .font(.system(size: 13, weight: .bold))
                                .tracking(2.6)
                                .foregroundStyle(StyleIATheme.moss)
                        }
                    }
                    .padding(.top, 24)

                    HStack(spacing: 10) {
                        StyleIAProfileMetric(value: "\(flow.generatedLooks.count)", label: "Looks")
                        StyleIAProfileMetric(value: "\(favorites.count)", label: "Saved")
                        StyleIAProfileMetric(value: "\(flow.selectedPersona.match)%", label: "Match")
                    }

                    StyleIAInfoPanel(title: "Current Style DNA") {
                        StyleIAInfoRow(label: "Persona", value: flow.selectedPersona.displayName)
                        StyleIAInfoRow(label: "Photo", value: flow.selectedPhoto == nil ? "Not uploaded" : "Uploaded")
                        StyleIAInfoRow(label: "Backend", value: Secrets.backendAPIBaseURL?.host ?? "Placeholder")
                        StyleIAInfoRow(label: "Generation", value: flow.isPreparingJob ? "Processing" : "Ready")
                    }

                    if !flow.generatedLooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LATEST LOOKS")
                                .font(.system(size: 12, weight: .heavy))
                                .tracking(2.6)
                                .foregroundStyle(StyleIATheme.moss.opacity(0.78))

                            LazyVGrid(columns: layout.lookGridColumns(), spacing: layout.lookGridSpacing) {
                                ForEach(Array(flow.generatedLooks.prefix(4))) { look in
                                    StyleIALookGalleryCard(look: look) {}
                                        .frame(minWidth: 0, maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, layout.sidePadding)
                .padding(.bottom, max(layout.safeBottom, 28))
                .frame(maxWidth: layout.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(StyleIATabBackground())
    }
}

private struct SettingsView: View {
    @State private var localNetworkRequested = false

    private var backendURL: String {
        Secrets.backendAPIBaseURL?.absoluteString ?? "Not configured"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            ScrollView {
                VStack(spacing: 18) {
                    StyleIAPremiumPreviewCard()

                    StyleIAInfoPanel(title: "Backend") {
                        StyleIAInfoRow(label: "API Base URL", value: backendURL)
                        StyleIAInfoRow(label: "Mode", value: Secrets.backendAPIBaseURL == nil ? "Placeholder" : "Live backend")

                        Button {
                            localNetworkRequested = true
                            StyleIALocalNetworkPermission.warmUpIfNeeded()
                        } label: {
                            Label("Retry Local Network Permission", systemImage: "network")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.82))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(StyleIATheme.moss)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(StyleIAPressButtonStyle())

                        Text(localNetworkRequested ? "If iOS already denied access, enable StyleAI in Settings > Privacy & Security > Local Network, then relaunch the app." : "Use this after installing a fresh build if the backend shows as offline on the same Wi-Fi.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(StyleIATheme.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    StyleIAInfoPanel(title: "Testing") {
                        StyleIAInfoRow(label: "Subscription Gates", value: "Disabled for QA")
                        StyleIAInfoRow(label: "Generated Data", value: "Live backend results")
                        StyleIAInfoRow(label: "UI Thread", value: "MainActor view model")
                    }

                    StyleIAInfoPanel(title: "About") {
                        StyleIAInfoRow(label: "Version", value: versionText)
                        StyleIAInfoRow(label: "App", value: "StyleIA")
                    }
                }
                .padding(.horizontal, layout.sidePadding)
                .padding(.top, 14)
                .padding(.bottom, max(layout.safeBottom, 28))
                .frame(maxWidth: layout.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(StyleIATabBackground())
    }
}

private struct StyleIAPremiumPreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("STYLEIA PRO")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(StyleIATheme.moss)

                    Text("Premium testing mode")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(StyleIATheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "star.circle.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(StyleIATheme.moss)
            }

            Text("All premium gates are disabled for QA. The UI still exposes the paid experience: unlimited looks, style twins, product modules, and lock-screen exports.")
                .font(.system(size: 13, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(StyleIATheme.text.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StyleIAPremiumPill("Unlimited")
                StyleIAPremiumPill("Twins")
                StyleIAPremiumPill("Products")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [StyleIATheme.surfaceGreen, StyleIATheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StyleIATheme.moss.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct StyleIAPremiumPill: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.3)
            .foregroundStyle(StyleIATheme.text.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(StyleIATheme.hairline, lineWidth: 1)
            }
    }
}

private struct StyleIAProfileAvatar: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(StyleIATheme.surfaceGreen)
                .frame(width: 104, height: 104)
                .overlay {
                    Circle().stroke(StyleIATheme.moss.opacity(0.56), lineWidth: 2)
                }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 94, height: 94)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(StyleIATheme.moss.opacity(0.8))
            }
        }
    }
}

private struct StyleIAProfileMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(StyleIATheme.text)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(StyleIATheme.moss.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(StyleIATheme.panel.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

private struct StyleIAInfoPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(2.6)
                .foregroundStyle(StyleIATheme.moss.opacity(0.78))

            VStack(spacing: 0) {
                content()
            }
            .padding(14)
            .background(StyleIATheme.panel.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(StyleIATheme.hairline, lineWidth: 1)
            }
        }
    }
}

private struct StyleIAInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(StyleIATheme.subtleText)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StyleIATheme.text.opacity(0.84))
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.74)
        }
        .padding(.vertical, 8)
    }
}
