import SwiftUI

struct ComparisonSlider: View {
    let beforeImage: UIImage
    let afterImage: UIImage
    @State private var dividerX: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let xPosition = max(0, min(width, dividerX * width))

            ZStack(alignment: .leading) {
                Image(uiImage: afterImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()

                Image(uiImage: beforeImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: xPosition)
                    }

                Rectangle()
                    .fill(DesignSystem.Colors.textPrimary)
                    .frame(width: 3, height: height)
                    .position(x: xPosition, y: height / 2)

                Circle()
                    .fill(DesignSystem.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                    .position(x: xPosition, y: height / 2)
                    .designShadow(DesignSystem.Shadows.card)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dividerX = max(0.08, min(0.92, value.location.x / max(width, 1)))
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large, style: .continuous))
    }
}

#Preview {
    ComparisonSlider(beforeImage: PreviewData.sampleImage(color: .systemBlue), afterImage: PreviewData.sampleImage(color: .systemPink))
        .frame(height: 460)
        .padding()
        .background(DesignSystem.Colors.primary)
}
