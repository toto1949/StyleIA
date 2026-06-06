import SwiftUI

struct AsyncImageView: View {
    let url: URL
    let imageCache: ImageCacheService
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                StyleAIIllustrationView()
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surface)
            } else {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous)
                    .fill(DesignSystem.Colors.surfaceRaised)
                    .shimmer()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        if let cached = imageCache.image(for: url) {
            image = cached
            didFail = false
            return
        }

        do {
            image = try await imageCache.load(url: url)
            didFail = false
        } catch {
            didFail = true
        }
    }
}

#Preview {
    AsyncImageView(url: PreviewData.sampleURLs[0], imageCache: PreviewData.container.imageCacheService)
        .frame(width: 180, height: 240)
        .padding()
        .background(DesignSystem.Colors.primary)
}
