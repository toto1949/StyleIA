import SwiftUI

/// Scene thumbnail with a moody gradient fallback while loading or offline.
struct SceneThumbnail: View {
    let scene: SceneTemplate

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                fallbackGradient

                if let url = scene.thumbnailURL {
                    Color.clear
                        .overlay {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                }
                            }
                        }
                        .clipped()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .allowsHitTesting(false)
        }
    }

    private var fallbackGradient: LinearGradient {
        let palette: [Color]
        switch scene.category {
        case .urban:
            palette = [Color(hex: 0x1B2335), Color(hex: 0x0A0D16)]
        case .nature:
            palette = [Color(hex: 0x16302B), Color(hex: 0x0A1411)]
        case .luxury:
            palette = [Color(hex: 0x2E2415), Color(hex: 0x140F08)]
        case .events:
            palette = [Color(hex: 0x2C1626), Color(hex: 0x120A10)]
        case .professional:
            palette = [Color(hex: 0x20262E), Color(hex: 0x0C0F13)]
        case .custom:
            palette = [Color(hex: 0x24202E), Color(hex: 0x0E0C13)]
        }

        return LinearGradient(colors: palette, startPoint: .top, endPoint: .bottom)
    }
}

struct SceneBadgePill: View {
    let badge: SceneBadge

    var body: some View {
        Text(badge.title)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(badge == .premium ? SceneMeTheme.gold : SceneMeTheme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(
                    badge == .premium ? SceneMeTheme.gold.opacity(0.6) : SceneMeTheme.hairline,
                    lineWidth: 1
                )
            }
    }
}

/// Card used in the scene picker grid and the featured rail.
struct SceneCardView: View {
    let scene: SceneTemplate
    var isSelected: Bool = false
    var height: CGFloat = 210
    var overrideBadgeTitle: String?
    let onTap: () -> Void

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                SceneThumbnail(scene: scene)
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                if let badgeTitle {
                    Text(badgeTitle)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(scene.badge == .premium ? SceneMeTheme.gold : SceneMeTheme.text)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                        .padding(10)
                        .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Spacer()

                    Text(locationEyebrow)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.8)
                        .foregroundStyle(SceneMeTheme.gold)

                    Text(scene.name)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(SceneMeTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(Color.black)
                                .frame(width: 26, height: 26)
                                .background(SceneMeTheme.gold)
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(cardShape)
            .contentShape(cardShape)
            .overlay {
                cardShape.stroke(
                    isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline,
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private var badgeTitle: String? {
        overrideBadgeTitle ?? scene.badge?.title
    }

    private var locationEyebrow: String {
        scene.location.uppercased()
    }
}
