import UIKit

/// Renders a small "Made with SceneMe" pill onto exported images.
/// Applied to saves and shares for free-tier users; subscribers export clean.
enum SceneMeWatermark {
    static func apply(to image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { _ in
            image.draw(at: .zero)

            let fontSize = max(image.size.width * 0.028, 16)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let text = "✨ Made with SceneMe" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.92)
            ]

            let textSize = text.size(withAttributes: attributes)
            let horizontalPadding = fontSize * 0.65
            let verticalPadding = fontSize * 0.38
            let margin = image.size.width * 0.035

            let pillRect = CGRect(
                x: image.size.width - textSize.width - horizontalPadding * 2 - margin,
                y: image.size.height - textSize.height - verticalPadding * 2 - margin,
                width: textSize.width + horizontalPadding * 2,
                height: textSize.height + verticalPadding * 2
            )

            let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
            UIColor.black.withAlphaComponent(0.42).setFill()
            pill.fill()

            text.draw(
                at: CGPoint(
                    x: pillRect.minX + horizontalPadding,
                    y: pillRect.midY - textSize.height / 2
                ),
                withAttributes: attributes
            )
        }
    }
}
