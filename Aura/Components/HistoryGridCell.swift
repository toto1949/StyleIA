import SwiftUI

struct HistoryGridCell: View {
    let record: GenerationRecord

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = UIImage(data: record.thumbnailData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    StyleAIIllustrationView()
                        .padding(DesignSystem.Spacing.lg)
                        .background(DesignSystem.Colors.surface)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.78, contentMode: .fill)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(record.styleGoal.label)
                    .font(Typography.titleMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.sm)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
        .designShadow(DesignSystem.Shadows.subtle)
    }
}

#Preview {
    HistoryGridCell(record: PreviewData.sampleRecord)
        .frame(width: 170)
        .padding()
        .background(DesignSystem.Colors.primary)
}
