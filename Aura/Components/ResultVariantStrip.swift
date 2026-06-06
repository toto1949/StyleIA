import SwiftUI

struct ResultVariantStrip: View {
    let urls: [URL]
    @Binding var selectedIndex: Int
    let imageCache: ImageCacheService

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    Button {
                        withAnimation(DesignSystem.Animations.spring) {
                            selectedIndex = index
                        }
                    } label: {
                        AsyncImageView(url: url, imageCache: imageCache)
                            .frame(width: 82, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous)
                                    .stroke(index == selectedIndex ? DesignSystem.Colors.accent : .clear, lineWidth: 3)
                            }
                            .scaleEffect(index == selectedIndex ? 1.05 : 1)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }
}

#Preview {
    @Previewable @State var selected = 0
    ResultVariantStrip(urls: PreviewData.sampleURLs, selectedIndex: $selected, imageCache: PreviewData.container.imageCacheService)
        .background(DesignSystem.Colors.primary)
}
