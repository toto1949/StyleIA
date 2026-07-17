import SwiftUI
import UIKit

/// SceneMe brand signature — editorial wordmark used on results, clips, and exports.
enum SceneMeSignature {
    static let markText = "SceneMe"
    static let diamond = "✦"

    /// Soft gold used when drawing into UIKit bitmaps.
    static var goldUIColor: UIColor {
        UIColor(red: 0.788, green: 0.659, blue: 0.361, alpha: 1) // #C9A85C
    }
}

/// Live overlay for result & video screens — subtle, always on for brand presence.
struct SceneMeSignatureOverlay: View {
    enum Corner {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    var corner: Corner = .topLeading
    var compact: Bool = false

    var body: some View {
        VStack {
            if isBottom { Spacer(minLength: 0) }

            HStack {
                if isTrailing { Spacer(minLength: 0) }
                mark
                    .padding(.horizontal, compact ? 12 : 16)
                    .padding(.vertical, compact ? 8 : 12)
                if isLeading { Spacer(minLength: 0) }
            }

            if isTop { Spacer(minLength: 0) }
        }
        .allowsHitTesting(false)
    }

    private var isTop: Bool {
        corner == .topLeading || corner == .topTrailing
    }

    private var isBottom: Bool {
        corner == .bottomLeading || corner == .bottomTrailing
    }

    private var isLeading: Bool {
        corner == .topLeading || corner == .bottomLeading
    }

    private var isTrailing: Bool {
        corner == .topTrailing || corner == .bottomTrailing
    }

    private var mark: some View {
        HStack(spacing: compact ? 5 : 7) {
            Text(SceneMeSignature.diamond)
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(SceneMeTheme.gold)

            Text(SceneMeSignature.markText)
                .font(.system(size: compact ? 12 : 14, weight: .medium, design: .serif))
                .foregroundStyle(Color.white.opacity(0.9))
                .tracking(0.4)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(SceneMeTheme.gold.opacity(0.28), lineWidth: 0.5)
                }
        )
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
    }
}

/// Burns a professional "✦ SceneMe" signature onto exported stills (free tier).
enum SceneMeWatermark {
    static func apply(to image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { _ in
            image.draw(at: .zero)
            drawSignature(in: CGRect(origin: .zero, size: image.size), style: .export)
        }
    }

    /// Draws the signature into an existing graphics context (images / video frames).
    static func drawSignature(in bounds: CGRect, style: Style) {
        let scale = max(bounds.width / 390, 0.55)
        let diamondSize = (style == .export ? 11 : 9) * scale
        let wordSize = (style == .export ? 15 : 12) * scale
        let margin = bounds.width * (style == .export ? 0.038 : 0.03)

        let diamondFont = UIFont.systemFont(ofSize: diamondSize, weight: .semibold)
        let wordFont: UIFont = {
            let base = UIFont.systemFont(ofSize: wordSize, weight: .medium)
            guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
            return UIFont(descriptor: descriptor, size: wordSize)
        }()

        let diamond = SceneMeSignature.diamond as NSString
        let word = SceneMeSignature.markText as NSString

        let diamondAttrs: [NSAttributedString.Key: Any] = [
            .font: diamondFont,
            .foregroundColor: SceneMeSignature.goldUIColor.withAlphaComponent(style == .export ? 0.95 : 0.85)
        ]
        let wordAttrs: [NSAttributedString.Key: Any] = [
            .font: wordFont,
            .foregroundColor: UIColor.white.withAlphaComponent(style == .export ? 0.94 : 0.88),
            .kern: 0.6
        ]

        let diamondSizeValue = diamond.size(withAttributes: diamondAttrs)
        let wordSizeValue = word.size(withAttributes: wordAttrs)
        let gap: CGFloat = 6 * scale
        let padX = 11 * scale
        let padY = 7 * scale

        let contentWidth = diamondSizeValue.width + gap + wordSizeValue.width
        let contentHeight = max(diamondSizeValue.height, wordSizeValue.height)
        let pillSize = CGSize(
            width: contentWidth + padX * 2,
            height: contentHeight + padY * 2
        )

        let pillOrigin = CGPoint(
            x: bounds.maxX - pillSize.width - margin,
            y: bounds.maxY - pillSize.height - margin
        )
        let pillRect = CGRect(origin: pillOrigin, size: pillSize)

        // Soft plate — editorial, not a heavy sticker.
        let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
        UIColor.black.withAlphaComponent(style == .export ? 0.38 : 0.28).setFill()
        pill.fill()

        SceneMeSignature.goldUIColor.withAlphaComponent(0.32).setStroke()
        pill.lineWidth = max(0.6 * scale, 0.5)
        pill.stroke()

        let textY = pillRect.midY - contentHeight / 2
        diamond.draw(
            at: CGPoint(x: pillRect.minX + padX, y: textY + (contentHeight - diamondSizeValue.height) / 2),
            withAttributes: diamondAttrs
        )
        word.draw(
            at: CGPoint(
                x: pillRect.minX + padX + diamondSizeValue.width + gap,
                y: textY + (contentHeight - wordSizeValue.height) / 2
            ),
            withAttributes: wordAttrs
        )
    }

    enum Style {
        case export
        case subtle
    }
}
