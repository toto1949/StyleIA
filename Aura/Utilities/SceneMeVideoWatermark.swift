import AVFoundation
import UIKit

/// Burns the SceneMe signature into a saved video (free-tier exports).
enum SceneMeVideoWatermark {
    /// Returns a temporary branded mp4 when `apply` is true; otherwise returns `sourceURL`.
    static func prepareForExport(sourceURL: URL, apply: Bool) async throws -> URL {
        guard apply else { return sourceURL }

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return sourceURL
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let rendered = naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(rendered.width), height: abs(rendered.height))
        guard renderSize.width > 1, renderSize.height > 1 else {
            return sourceURL
        }

        let composition = AVMutableComposition()
        guard
            let compositionVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            return sourceURL
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudio = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let watermarkImage = makeWatermarkImage(size: renderSize)
        let overlayLayer = CALayer()
        overlayLayer.contents = watermarkImage.cgImage
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        overlayLayer.contentsGravity = .resize
        overlayLayer.opacity = 1

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideo)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sceneme-branded-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            return sourceURL
        }

        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.shouldOptimizeForNetworkUse = true

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<AVAssetExportSession.Status, Never>) in
            export.exportAsynchronously {
                continuation.resume(returning: export.status)
            }
        }

        if status == .completed {
            return outputURL
        }
        return sourceURL
    }

    /// Transparent canvas the size of the video with the signature drawn in the corner.
    private static func makeWatermarkImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            SceneMeWatermark.drawSignature(in: CGRect(origin: .zero, size: size), style: .export)
        }
    }
}
