import SwiftUI
import UIKit

/// Composes the generated image into a shareable postcard UIImage.
enum PostcardRenderer {
    /// White border frame, image in the center, scene name + date strip, italic caption.
    static func render(
        image: UIImage,
        sceneName: String,
        date: Date,
        caption: String
    ) -> UIImage {
        // Scale all metrics relative to a 390pt design width so exports stay sharp.
        let scale = max(image.size.width / 390, 1)
        let border = 20 * scale
        let stripHeight = 54 * scale
        let captionHeight: CGFloat = caption.isEmpty ? 0 : 34 * scale

        let canvasSize = CGSize(
            width: image.size.width + border * 2,
            height: image.size.height + border * 2 + captionHeight + stripHeight
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            image.draw(in: CGRect(x: border, y: border, width: image.size.width, height: image.size.height))

            let textColor = UIColor(white: 0.12, alpha: 1)
            var cursorY = border + image.size.height

            if !caption.isEmpty {
                let captionFont = italicSerifFont(size: 15 * scale)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byTruncatingTail

                let captionRect = CGRect(
                    x: border,
                    y: cursorY + 8 * scale,
                    width: image.size.width,
                    height: captionHeight - 8 * scale
                )
                (caption as NSString).draw(
                    in: captionRect,
                    withAttributes: [
                        .font: captionFont,
                        .foregroundColor: textColor.withAlphaComponent(0.75),
                        .paragraphStyle: paragraph
                    ]
                )
                cursorY += captionHeight
            }

            let nameFont = serifFont(size: 17 * scale)
            let dateFont = serifFont(size: 13 * scale)
            let stripCenterY = cursorY + stripHeight / 2

            let nameAttributes: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: textColor
            ]
            let nameSize = (sceneName as NSString).size(withAttributes: nameAttributes)
            (sceneName as NSString).draw(
                at: CGPoint(x: border, y: stripCenterY - nameSize.height / 2),
                withAttributes: nameAttributes
            )

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let dateText = formatter.string(from: date)
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: textColor.withAlphaComponent(0.6)
            ]
            let dateSize = (dateText as NSString).size(withAttributes: dateAttributes)
            (dateText as NSString).draw(
                at: CGPoint(
                    x: canvasSize.width - border - dateSize.width,
                    y: stripCenterY - dateSize.height / 2
                ),
                withAttributes: dateAttributes
            )
        }
    }

    private static func serifFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func italicSerifFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        guard
            let descriptor = base.fontDescriptor
                .withDesign(.serif)?
                .withSymbolicTraits(.traitItalic)
        else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// Postcard sheet: live preview, editable caption, share & save.
struct PostcardFrameView: View {
    let image: UIImage
    let sceneName: String
    let date: Date
    var onSave: (UIImage) -> Void

    @State private var caption = ""
    @State private var rendered: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(SceneMeTheme.hairline)
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            SceneMeEyebrow(text: "Postcard", alignment: .center)

            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 380)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
                    .padding(.horizontal, 24)
            }

            TextField("Add a caption…", text: $caption, axis: .vertical)
                .font(.system(size: 15, design: .serif))
                .italic()
                .foregroundStyle(SceneMeTheme.text)
                .padding(14)
                .background(SceneMeTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                        .stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                if let rendered {
                    ShareLink(
                        item: Image(uiImage: rendered),
                        preview: SharePreview(sceneName, image: Image(uiImage: rendered))
                    ) {
                        shareLabel
                    }
                    .buttonStyle(SceneMePressButtonStyle())
                }

                SceneMeSecondaryButton(title: "Save", systemImage: "square.and.arrow.down") {
                    if let rendered {
                        onSave(rendered)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SceneMeTheme.ink)
        .task(id: caption) {
            render()
        }
    }

    private var shareLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
            Text("SHARE")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.8)
        }
        .foregroundStyle(Color.black.opacity(0.88))
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            LinearGradient(
                colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(Capsule())
    }

    private func render() {
        rendered = PostcardRenderer.render(
            image: image,
            sceneName: sceneName,
            date: date,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
