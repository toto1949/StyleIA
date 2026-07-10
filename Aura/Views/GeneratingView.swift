import Combine
import SwiftUI

/// Smart loading sequence: timed status phases + real backend progress.
struct GeneratingView: View {
    @ObservedObject var viewModel: SceneMeViewModel

    @State private var phaseIndex = 0
    @State private var ringRotation: Double = 0

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var phases: [(message: String, systemImage: String)] {
        [
            ("Placing you in \(viewModel.generatingSceneName)…", "mappin.and.ellipse"),
            ("Matching outfit to the vibe…", "tshirt"),
            ("Rendering lighting and atmosphere…", "sparkles"),
            ("Almost there…", "wand.and.stars")
        ]
    }

    private var steps: [String] {
        [
            "Photo uploaded & analyzed",
            "Scene & outfit matched",
            "Rendering lighting & atmosphere",
            "Final touches…"
        ]
    }

    /// Timed progress hits 90% at the last phase; real backend progress can push past it.
    private var displayedProgress: Int {
        let timedTarget = [25, 55, 75, 90][min(phaseIndex, 3)]
        return min(max(viewModel.generationProgress, timedTarget), 99)
    }

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 24)

            VStack(spacing: 10) {
                SceneMeEyebrow(text: "Generating your scene", alignment: .center)

                Text(viewModel.generatingSceneName)
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(SceneMeTheme.text)
            }

            loadingCard

            checklist

            progressBar

            Button {
                viewModel.cancelGeneration()
            } label: {
                Text("Cancel generation")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SceneMeTheme.subtleText)
                    .underline()
            }
            .buttonStyle(SceneMePressButtonStyle())

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SceneMeTheme.ink)
        .onAppear {
            phaseIndex = 0
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
        .onReceive(timer) { _ in
            guard phaseIndex < phases.count - 1 else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                phaseIndex += 1
            }
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(SceneMeTheme.hairline, lineWidth: 3)
                    .frame(width: 110, height: 110)

                Circle()
                    .trim(from: 0, to: 0.62)
                    .stroke(
                        AngularGradient(
                            colors: [SceneMeTheme.gold.opacity(0), SceneMeTheme.gold],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(ringRotation))

                Image(systemName: phases[phaseIndex].systemImage)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(SceneMeTheme.gold)
                    .contentTransition(.symbolEffect(.replace))
            }

            Text(phases[phaseIndex].message)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SceneMeTheme.subtleText)
                .multilineTextAlignment(.center)
                .frame(height: 42)
                .animation(.easeInOut(duration: 0.3), value: phaseIndex)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .background(
            LinearGradient(
                colors: [SceneMeTheme.panel.opacity(0.95), SceneMeTheme.surface.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [SceneMeTheme.gold.opacity(0.3), SceneMeTheme.hairline],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(
                                index <= phaseIndex ? SceneMeTheme.gold : SceneMeTheme.hairline,
                                lineWidth: 1.4
                            )
                            .frame(width: 22, height: 22)

                        if index < phaseIndex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(SceneMeTheme.gold)
                        } else if index == phaseIndex {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(SceneMeTheme.gold)
                        }
                    }

                    Text(step)
                        .font(.system(size: 14, weight: index == phaseIndex ? .semibold : .regular))
                        .foregroundStyle(
                            index < phaseIndex
                                ? SceneMeTheme.text
                                : index == phaseIndex ? SceneMeTheme.gold : SceneMeTheme.faintText
                        )

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("PROGRESS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(SceneMeTheme.subtleText)

                Spacer()

                Text("\(displayedProgress)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.gold)
                    .contentTransition(.numericText())
                    .animation(.default, value: displayedProgress)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SceneMeTheme.hairline)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [SceneMeTheme.gold.opacity(0.7), SceneMeTheme.goldBright],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(displayedProgress) / 100)
                        .animation(.easeInOut(duration: 0.6), value: displayedProgress)
                }
            }
            .frame(height: 5)
        }
    }
}
