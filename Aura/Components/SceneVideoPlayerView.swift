import AVFoundation
import AVKit
import SwiftUI

/// Full-screen sheet that plays the animated scene clip on loop,
/// with save and share actions. Optional caption for Talking director clips.
struct SceneVideoPlayerView: View {
    let videoURL: URL
    let sceneName: String
    var caption: String? = nil
    let onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var looper: Any?

    private var trimmedCaption: String? {
        guard let caption else { return nil }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(SceneMeTheme.gold)
            }

            // Always-on signature — top trailing so it never fights the lower-third caption.
            SceneMeSignatureOverlay(corner: .topTrailing, compact: true)
                .padding(.top, 64)
                .padding(.trailing, 8)

            // Broadcast-style lower-third caption for Talking clips.
            if let trimmedCaption {
                VStack {
                    Spacer()
                    Text(trimmedCaption)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.55))
                        .padding(.horizontal, 22)
                        .padding(.bottom, 210)
                }
                .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text(SceneMeSignature.diamond)
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(sceneName) — Live")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(SceneMeTheme.gold)

                HStack(spacing: 12) {
                    Button {
                        onSave(videoURL)
                    } label: {
                        actionLabel(systemImage: "arrow.down.to.line", title: "SAVE VIDEO", prominent: true)
                    }
                    .buttonStyle(SceneMePressButtonStyle())

                    ShareLink(item: videoURL) {
                        actionLabel(systemImage: "square.and.arrow.up", title: "SHARE", prominent: false)
                    }
                    .buttonStyle(SceneMePressButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            closeButton
        }
        .onAppear {
            // Talking clips include TTS audio — play even if the hardware mute switch is on.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)

            let created = AVPlayer(url: videoURL)
            created.isMuted = false
            created.actionAtItemEnd = .none
            looper = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: created.currentItem,
                queue: .main
            ) { _ in
                created.seek(to: .zero)
                created.play()
            }
            created.play()
            player = created
        }
        .onDisappear {
            player?.pause()
            if let looper {
                NotificationCenter.default.removeObserver(looper)
            }
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                SceneMeCircleButton(systemImage: "xmark") {
                    dismiss()
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            Spacer()
        }
    }

    private func actionLabel(systemImage: String, title: String, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .tracking(1.8)
        }
        .foregroundStyle(prominent ? Color.black.opacity(0.88) : SceneMeTheme.text)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            if prominent {
                LinearGradient(
                    colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                SceneMeTheme.panel.opacity(0.9)
            }
        }
        .clipShape(Capsule())
        .overlay {
            if !prominent {
                Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1)
            }
        }
    }
}
