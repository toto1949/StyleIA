import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Client-side cinematic color grades applied with CoreImage — no backend call.
/// Each look is built from grading primitives (tone curves, split-toning,
/// temperature, grain, bloom, vignette) instead of canned photo effects,
/// so skin tones stay natural while the mood changes.
enum CinematicFilter: String, CaseIterable, Identifiable {
    case original
    case portra
    case blockbuster
    case goldenHour
    case noir
    case neon
    case moody
    case editorial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "Original"
        case .portra:
            return "Portra"
        case .blockbuster:
            return "Blockbuster"
        case .goldenHour:
            return "Golden Hour"
        case .noir:
            return "Noir"
        case .neon:
            return "Neon"
        case .moody:
            return "Moody"
        case .editorial:
            return "Editorial"
        }
    }

    /// One-line description shown under the strip for the selected look.
    var caption: String {
        switch self {
        case .original:
            return "Untouched, straight from the scene"
        case .portra:
            return "Warm film stock, creamy skin tones"
        case .blockbuster:
            return "Teal shadows, orange light — movie poster grade"
        case .goldenHour:
            return "Sun-kissed glow with a soft bloom"
        case .noir:
            return "Rich black & white with film grain"
        case .neon:
            return "Cool night grade with neon bloom"
        case .moody:
            return "Matte, muted and atmospheric"
        case .editorial:
            return "Crisp high-fashion magazine contrast"
        }
    }

    static let nonOriginal: [CinematicFilter] = allCases.filter { $0 != .original }
}

nonisolated enum CinematicFilterEngine {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func apply(_ filter: CinematicFilter, to image: UIImage) -> UIImage {
        guard filter != .original, let input = CIImage(image: image) else {
            return image
        }

        let output: CIImage
        switch filter {
        case .original:
            return image
        case .portra:
            output = portra(input)
        case .blockbuster:
            output = blockbuster(input)
        case .goldenHour:
            output = goldenHour(input)
        case .noir:
            output = noir(input)
        case .neon:
            output = neon(input)
        case .moody:
            output = moody(input)
        case .editorial:
            output = editorial(input)
        }

        return render(output, extent: input.extent, fallback: image)
    }

    /// Cross-fades the original with the fully graded image so the user can
    /// dial the strength of a look. `intensity` 0 = original, 1 = full grade.
    static func blend(_ original: UIImage, _ filtered: UIImage, intensity: Double) -> UIImage {
        guard
            intensity < 0.995,
            let base = CIImage(image: original),
            let graded = CIImage(image: filtered)
        else {
            return filtered
        }

        guard intensity > 0.005 else {
            return original
        }

        let mix = CIFilter.dissolveTransition()
        mix.inputImage = base
        mix.targetImage = graded
        mix.time = Float(intensity)

        guard let output = mix.outputImage else {
            return filtered
        }

        return render(output, extent: base.extent, fallback: filtered)
    }

    private static func render(_ output: CIImage, extent: CGRect, fallback: UIImage) -> UIImage {
        guard let cgImage = context.createCGImage(output.cropped(to: extent), from: extent) else {
            return fallback
        }
        return UIImage(cgImage: cgImage, scale: fallback.scale, orientation: fallback.imageOrientation)
    }

    // MARK: - Looks

    /// Kodak Portra-style film stock: gentle warmth, lifted blacks,
    /// rolled-off highlights, fine grain. Flattering on skin.
    private static func portra(_ input: CIImage) -> CIImage {
        var image = temperature(input, target: 5_650, tint: 4)
        image = colorControls(image, saturation: 0.92, contrast: 1.02)
        image = toneCurve(
            image,
            p0: CGPoint(x: 0, y: 0.03),
            p1: CGPoint(x: 0.25, y: 0.25),
            p2: CGPoint(x: 0.5, y: 0.51),
            p3: CGPoint(x: 0.75, y: 0.78),
            p4: CGPoint(x: 1, y: 0.97)
        )
        return grain(image, intensity: 0.035)
    }

    /// The Hollywood teal & orange grade: shadows pushed cyan-blue,
    /// highlights pushed warm, midtone skin left mostly intact.
    private static func blockbuster(_ input: CIImage) -> CIImage {
        var image = channelCurves(
            input,
            red: CIVector(x: 0, y: 0.95, z: 0.12, w: 0),
            green: CIVector(x: 0.02, y: 0.98, z: 0, w: 0),
            blue: CIVector(x: 0.07, y: 1.0, z: -0.2, w: 0)
        )
        image = colorControls(image, saturation: 1.08, contrast: 1.06)
        return vignette(image, intensity: 0.3, radius: 1.8)
    }

    /// Warm sun-drenched glow with a soft highlight bloom.
    private static func goldenHour(_ input: CIImage) -> CIImage {
        var image = temperature(input, target: 4_950, tint: 8)
        image = colorControls(image, saturation: 1.06, contrast: 1.02)
        image = toneCurve(
            image,
            p0: CGPoint(x: 0, y: 0.02),
            p1: CGPoint(x: 0.25, y: 0.26),
            p2: CGPoint(x: 0.5, y: 0.52),
            p3: CGPoint(x: 0.75, y: 0.77),
            p4: CGPoint(x: 1, y: 1)
        )
        image = bloom(image, intensity: 0.35, radius: 10)
        return vignette(image, intensity: 0.3, radius: 2)
    }

    /// Fine-art black & white: deep S-curve contrast, grain, vignette.
    private static func noir(_ input: CIImage) -> CIImage {
        let mono = CIFilter.photoEffectMono()
        mono.inputImage = input
        var image = mono.outputImage ?? input

        image = toneCurve(
            image,
            p0: CGPoint(x: 0, y: 0),
            p1: CGPoint(x: 0.25, y: 0.18),
            p2: CGPoint(x: 0.5, y: 0.5),
            p3: CGPoint(x: 0.75, y: 0.82),
            p4: CGPoint(x: 1, y: 1)
        )
        image = grain(image, intensity: 0.05)
        return vignette(image, intensity: 0.65, radius: 1.8)
    }

    /// Night-city grade: cool blue shadows, magenta-leaning highlights and a
    /// neon bloom — without the hue rotation that used to turn faces purple.
    private static func neon(_ input: CIImage) -> CIImage {
        var image = channelCurves(
            input,
            red: CIVector(x: 0.03, y: 0.85, z: 0.18, w: 0),
            green: CIVector(x: 0, y: 0.94, z: 0.03, w: 0),
            blue: CIVector(x: 0.12, y: 0.88, z: 0.06, w: 0)
        )
        image = colorControls(image, saturation: 1.12, contrast: 1.08)
        image = bloom(image, intensity: 0.5, radius: 12)
        return vignette(image, intensity: 0.5, radius: 1.7)
    }

    /// Matte atmospheric grade: muted color, lifted blacks, softened
    /// highlights, faint green cast in the shadows, grain.
    private static func moody(_ input: CIImage) -> CIImage {
        var image = colorControls(input, saturation: 0.8, contrast: 1.03)
        image = toneCurve(
            image,
            p0: CGPoint(x: 0, y: 0.06),
            p1: CGPoint(x: 0.25, y: 0.26),
            p2: CGPoint(x: 0.5, y: 0.48),
            p3: CGPoint(x: 0.75, y: 0.72),
            p4: CGPoint(x: 1, y: 0.93)
        )
        image = channelCurves(
            image,
            red: CIVector(x: 0, y: 1, z: 0, w: 0),
            green: CIVector(x: 0.02, y: 0.99, z: 0, w: 0),
            blue: CIVector(x: 0.01, y: 1, z: 0, w: 0)
        )
        image = grain(image, intensity: 0.04)
        return vignette(image, intensity: 0.5, radius: 1.9)
    }

    /// High-fashion editorial: crisp contrast, slightly cool, deep blacks.
    private static func editorial(_ input: CIImage) -> CIImage {
        var image = temperature(input, target: 7_100, tint: -3)
        image = colorControls(image, saturation: 0.96, contrast: 1.1)
        image = toneCurve(
            image,
            p0: CGPoint(x: 0, y: 0),
            p1: CGPoint(x: 0.22, y: 0.17),
            p2: CGPoint(x: 0.5, y: 0.5),
            p3: CGPoint(x: 0.78, y: 0.82),
            p4: CGPoint(x: 1, y: 1)
        )
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = 0.25
        return sharpen.outputImage ?? image
    }

    // MARK: - Grading primitives

    private static func temperature(_ input: CIImage, target: CGFloat, tint: CGFloat) -> CIImage {
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = input
        filter.neutral = CIVector(x: 6_500, y: 0)
        filter.targetNeutral = CIVector(x: target, y: tint)
        return filter.outputImage ?? input
    }

    private static func colorControls(_ input: CIImage, saturation: Float, contrast: Float) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.saturation = saturation
        filter.contrast = contrast
        filter.brightness = 0
        return filter.outputImage ?? input
    }

    private static func toneCurve(
        _ input: CIImage,
        p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, p4: CGPoint
    ) -> CIImage {
        let filter = CIFilter.toneCurve()
        filter.inputImage = input
        filter.point0 = p0
        filter.point1 = p1
        filter.point2 = p2
        filter.point3 = p3
        filter.point4 = p4
        return filter.outputImage ?? input
    }

    /// Per-channel polynomial curves (y = a0 + a1·x + a2·x² + a3·x³) — the
    /// split-toning workhorse: bias a channel in shadows via a0, in
    /// highlights via a2/a3, without touching overall hue.
    private static func channelCurves(
        _ input: CIImage,
        red: CIVector, green: CIVector, blue: CIVector
    ) -> CIImage {
        let filter = CIFilter.colorPolynomial()
        filter.inputImage = input
        filter.redCoefficients = red
        filter.greenCoefficients = green
        filter.blueCoefficients = blue
        filter.alphaCoefficients = CIVector(x: 0, y: 1, z: 0, w: 0)
        return (filter.outputImage ?? input).cropped(to: input.extent)
    }

    private static func bloom(_ input: CIImage, intensity: Float, radius: Float) -> CIImage {
        let filter = CIFilter.bloom()
        filter.inputImage = input
        filter.intensity = intensity
        filter.radius = radius
        return (filter.outputImage ?? input).cropped(to: input.extent)
    }

    private static func vignette(_ input: CIImage, intensity: Float, radius: Float) -> CIImage {
        let filter = CIFilter.vignette()
        filter.inputImage = input
        filter.intensity = intensity
        filter.radius = radius
        return filter.outputImage ?? input
    }

    private static func grain(_ image: CIImage, intensity: CGFloat) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else {
            return image
        }

        let monochromeNoise = CIFilter.colorMatrix()
        monochromeNoise.inputImage = noise.cropped(to: image.extent)
        monochromeNoise.rVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        monochromeNoise.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        monochromeNoise.bVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        monochromeNoise.aVector = CIVector(x: 0, y: 0, z: 0, w: intensity)
        monochromeNoise.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

        guard let grain = monochromeNoise.outputImage else {
            return image
        }

        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = grain
        composite.backgroundImage = image

        return (composite.outputImage ?? image).cropped(to: image.extent)
    }
}

/// Horizontal strip of graded previews plus a strength slider,
/// shown on the result screen.
struct CinematicFilterView: View {
    let baseImage: UIImage?
    @Binding var selection: CinematicFilter
    /// Committed strength (0…1); only updated when the user releases the slider.
    @Binding var intensity: Double

    @State private var previews: [CinematicFilter: UIImage] = [:]
    @State private var sliderValue: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("CINEMATIC GRADES")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(SceneMeTheme.subtleText)

                Spacer()

                Text(selection.caption)
                    .font(.system(size: 10))
                    .foregroundStyle(SceneMeTheme.faintText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CinematicFilter.allCases) { filter in
                        filterTile(filter)
                    }
                }
            }

            if selection != .original {
                strengthSlider
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .task(id: baseImage) {
            await buildPreviews()
        }
        .onChange(of: selection) { _, _ in
            sliderValue = 1
            intensity = 1
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection != .original)
    }

    private var strengthSlider: some View {
        HStack(spacing: 12) {
            Text("STRENGTH")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(SceneMeTheme.subtleText)

            Slider(value: $sliderValue, in: 0.2...1) { editing in
                // Full-resolution regrade is expensive; commit on release only.
                if !editing {
                    intensity = sliderValue
                }
            }
            .tint(SceneMeTheme.gold)

            Text("\(Int(sliderValue * 100))%")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(SceneMeTheme.gold)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func filterTile(_ filter: CinematicFilter) -> some View {
        let isSelected = selection == filter

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selection = filter
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SceneMeTheme.surface)

                    Color.clear
                        .overlay {
                            if let preview = previews[filter] {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "film")
                                    .font(.system(size: 16))
                                    .foregroundStyle(SceneMeTheme.faintText)
                            }
                        }
                        .clipped()
                }
                .frame(width: 62, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: isSelected ? 1.5 : 1)
                }

                Text(filter.title.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
                    .frame(width: 66)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private func buildPreviews() async {
        guard let baseImage else {
            previews = [:]
            return
        }

        let thumbnail = await Task.detached(priority: .userInitiated) { () -> UIImage in
            let targetSize = CGSize(width: 124, height: 164)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                baseImage.draw(in: aspectFillRect(for: baseImage.size, in: targetSize))
            }
        }.value

        var generated: [CinematicFilter: UIImage] = [:]
        for filter in CinematicFilter.allCases {
            let preview = await Task.detached(priority: .userInitiated) {
                CinematicFilterEngine.apply(filter, to: thumbnail)
            }.value
            generated[filter] = preview
        }
        previews = generated
    }
}

private func aspectFillRect(for imageSize: CGSize, in bounds: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else {
        return CGRect(origin: .zero, size: bounds)
    }

    let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
    return CGRect(origin: origin, size: size)
}
