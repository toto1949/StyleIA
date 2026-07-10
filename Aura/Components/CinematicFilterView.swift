import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Client-side cinematic looks applied with CoreImage — no backend call needed.
enum CinematicFilter: String, CaseIterable, Identifiable {
    case original
    case filmNoir
    case kodakVintage
    case cyberpunk
    case cinemaVerite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "Original"
        case .filmNoir:
            return "Film Noir"
        case .kodakVintage:
            return "Kodak"
        case .cyberpunk:
            return "Cyberpunk"
        case .cinemaVerite:
            return "Cinéma Vérité"
        }
    }

    static let nonOriginal: [CinematicFilter] = [.filmNoir, .kodakVintage, .cyberpunk, .cinemaVerite]
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
        case .filmNoir:
            output = filmNoir(input)
        case .kodakVintage:
            output = kodakVintage(input)
        case .cyberpunk:
            output = cyberpunk(input)
        case .cinemaVerite:
            output = cinemaVerite(input)
        }

        guard let cgImage = context.createCGImage(output, from: input.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// CIPhotoEffectNoir + contrast boost.
    private static func filmNoir(_ input: CIImage) -> CIImage {
        let noir = CIFilter.photoEffectNoir()
        noir.inputImage = input

        let contrast = CIFilter.colorControls()
        contrast.inputImage = noir.outputImage ?? input
        contrast.contrast = 1.18
        contrast.saturation = 1
        contrast.brightness = 0

        return contrast.outputImage ?? input
    }

    /// Warm tone + CIPhotoEffectFade + film grain.
    private static func kodakVintage(_ input: CIImage) -> CIImage {
        let fade = CIFilter.photoEffectFade()
        fade.inputImage = input
        let faded = fade.outputImage ?? input

        let warm = CIFilter.temperatureAndTint()
        warm.inputImage = faded
        warm.neutral = CIVector(x: 6_500, y: 0)
        warm.targetNeutral = CIVector(x: 5_200, y: 6)
        let warmed = warm.outputImage ?? faded

        return addGrain(to: warmed, intensity: 0.07)
    }

    /// Hue shift to blue/purple + sharpen + neon bloom.
    private static func cyberpunk(_ input: CIImage) -> CIImage {
        let hue = CIFilter.hueAdjust()
        hue.inputImage = input
        hue.angle = -0.55
        let shifted = hue.outputImage ?? input

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = shifted
        sharpen.sharpness = 0.55
        let sharpened = sharpen.outputImage ?? shifted

        let bloom = CIFilter.bloom()
        bloom.inputImage = sharpened
        bloom.intensity = 0.65
        bloom.radius = 8

        return (bloom.outputImage ?? sharpened).cropped(to: input.extent)
    }

    /// Slight desaturation + CIPhotoEffectTonal + subtle vignette.
    private static func cinemaVerite(_ input: CIImage) -> CIImage {
        let desaturate = CIFilter.colorControls()
        desaturate.inputImage = input
        desaturate.saturation = 0.82
        desaturate.contrast = 1.02
        desaturate.brightness = 0
        let muted = desaturate.outputImage ?? input

        let tonal = CIFilter.photoEffectTonal()
        tonal.inputImage = muted
        let toned = tonal.outputImage ?? muted

        let vignette = CIFilter.vignette()
        vignette.inputImage = toned
        vignette.intensity = 0.7
        vignette.radius = 1.6

        return vignette.outputImage ?? toned
    }

    private static func addGrain(to image: CIImage, intensity: CGFloat) -> CIImage {
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

/// Horizontal strip of filter previews shown on the result screen.
struct CinematicFilterView: View {
    let baseImage: UIImage?
    @Binding var selection: CinematicFilter
    @State private var previews: [CinematicFilter: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CINEMATIC FILTERS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(SceneMeTheme.subtleText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CinematicFilter.allCases) { filter in
                        filterTile(filter)
                    }
                }
            }
        }
        .task(id: baseImage) {
            await buildPreviews()
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
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: isSelected ? 1.5 : 1)
                }

                Text(filter.title.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private func buildPreviews() async {
        guard let baseImage else {
            previews = [:]
            return
        }

        let thumbnail = await Task.detached(priority: .userInitiated) { () -> UIImage in
            let targetSize = CGSize(width: 132, height: 132)
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
