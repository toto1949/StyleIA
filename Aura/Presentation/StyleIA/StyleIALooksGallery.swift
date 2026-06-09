import SwiftUI

final class StyleIAFavoritesStore: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(favoriteIDs), forKey: storageKey)
        }
    }

    private let storageKey = "styleia.favorite.look.ids"

    init() {
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    var count: Int {
        favoriteIDs.count
    }

    func isFavorite(_ look: StyleIALook) -> Bool {
        favoriteIDs.contains(look.id)
    }

    func toggle(_ look: StyleIALook) {
        if favoriteIDs.contains(look.id) {
            favoriteIDs.remove(look.id)
        } else {
            favoriteIDs.insert(look.id)
        }
    }

    func favoriteLooks(from looks: [StyleIALook]) -> [StyleIALook] {
        looks.filter { favoriteIDs.contains($0.id) }
    }
}

struct StyleIALooksResponsiveGrid: View {
    let looks: [StyleIALook]
    let layout: StyleIALayout
    var showsStyleBadge = true

    @State private var selectedLook: StyleIALook?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: layout.lookGridColumns(), spacing: layout.lookGridSpacing) {
                ForEach(looks) { look in
                    StyleIALookGalleryCard(look: look, showsStyleBadge: showsStyleBadge) {
                        selectedLook = look
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
            .padding(.horizontal, layout.sidePadding)
            .padding(.top, 6)
            .padding(.bottom, max(layout.safeBottom, 28))
            .frame(maxWidth: layout.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selectedLook) { look in
            StyleIALookPreviewSheet(look: look)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct StyleIAAllLooksGridSection: View {
    let looks: [StyleIALook]
    let layout: StyleIALayout
    let onSelectLook: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ALL LOOKS")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(3.2)
                    .foregroundStyle(StyleIATheme.moss.opacity(0.78))

                Text("Browse every generated outfit")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(StyleIATheme.text.opacity(0.86))
            }

            LazyVGrid(columns: layout.lookGridColumns(), spacing: layout.lookGridSpacing) {
                ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                    StyleIALookGalleryCard(look: look) {
                        onSelectLook(index)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, layout.sidePadding)
    }
}

struct StyleIALookGalleryCard: View {
    let look: StyleIALook
    var showsStyleBadge = true
    let onOpen: () -> Void

    @EnvironmentObject private var favorites: StyleIAFavoritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: look.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ZStack {
                            StyleIATheme.surfaceGreen
                            ProgressView()
                                .tint(StyleIATheme.moss)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.72)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 88)

                    if showsStyleBadge {
                        Text(look.styleGoal.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(StyleIATheme.moss)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    favorites.toggle(look)
                } label: {
                    Image(systemName: favorites.isFavorite(look) ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(favorites.isFavorite(look) ? StyleIATheme.moss : StyleIATheme.text)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(StyleIAPressButtonStyle())
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(look.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StyleIATheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(look.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(StyleIATheme.subtleText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [StyleIATheme.panel.opacity(0.92), StyleIATheme.surfaceGreen.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [StyleIATheme.moss.opacity(0.34), StyleIATheme.hairline],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: StyleIATheme.moss.opacity(0.1), radius: 10, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
}

struct StyleIALooksTabHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(StyleIATheme.moss.opacity(0.82))

                    Text(title)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(StyleIATheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(StyleIATheme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text("\(count)")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(StyleIATheme.text)
                    .frame(width: 52, height: 52)
                    .background(StyleIATheme.surfaceGreen)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(StyleIATheme.moss.opacity(0.45), lineWidth: 1)
                    }
            }
        }
        .padding(16)
        .background(StyleIATheme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(StyleIATheme.hairline, lineWidth: 1)
        }
    }
}

struct StyleIALookPreviewSheet: View {
    let look: StyleIALook
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favorites: StyleIAFavoritesStore

    var body: some View {
        GeometryReader { proxy in
            let layout = StyleIALayout(size: proxy.size)

            ZStack {
                StyleIATabBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ZStack(alignment: .bottomLeading) {
                            AsyncImage(url: look.imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    StyleIALookImagePlaceholder()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: min(proxy.size.height * 0.56, 520))
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                            LinearGradient(colors: [.clear, .black.opacity(0.74)], startPoint: .center, endPoint: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                            VStack(alignment: .leading, spacing: 7) {
                                Text(look.styleGoal.uppercased())
                                    .font(.system(size: 12, weight: .heavy))
                                    .tracking(3)
                                    .foregroundStyle(StyleIATheme.moss)

                                Text(look.title)
                                    .font(.system(size: min(layout.resultTitleSize, 34), weight: .regular, design: .serif))
                                    .foregroundStyle(StyleIATheme.text)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)

                                Text(look.subtitle)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(StyleIATheme.text.opacity(0.7))
                                    .lineLimit(2)
                            }
                            .padding(20)
                        }

                        HStack(spacing: 12) {
                            Button {
                                favorites.toggle(look)
                            } label: {
                                Label(
                                    favorites.isFavorite(look) ? "Saved" : "Save",
                                    systemImage: favorites.isFavorite(look) ? "heart.fill" : "heart"
                                )
                                .frame(maxWidth: .infinity)
                            }

                            ShareLink(item: look.imageURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(height: 46)
                        .buttonStyle(StyleIAPreviewButtonStyle())

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(StyleIATheme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(StyleIATheme.panel)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule().stroke(StyleIATheme.hairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(StyleIAPressButtonStyle())
                    }
                    .padding(.horizontal, layout.sidePadding)
                    .padding(.bottom, max(layout.safeBottom, 18))
                    .frame(maxWidth: layout.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct StyleIAPreviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 46)
            .background(StyleIATheme.moss)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct StyleIALookImagePlaceholder: View {
    var body: some View {
        ZStack {
            StyleIATheme.surfaceGreen
            Image(systemName: "photo")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(StyleIATheme.moss)
        }
    }
}

struct StyleIATabBackground: View {
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

            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.56)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

struct StyleIAEmptyTabState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(StyleIATheme.moss)
                .frame(width: 72, height: 72)
                .background(StyleIATheme.surfaceGreen)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(StyleIATheme.moss.opacity(0.35), lineWidth: 1)
                }

            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(StyleIATheme.text)

            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(StyleIATheme.subtleText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
