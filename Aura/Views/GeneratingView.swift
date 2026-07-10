import Combine
import SwiftUI

/// Loading sequence driven by real backend progress. The backend reports
/// milestones (20 = photo uploaded to the generator, 60 = rendering,
/// 95 = finishing); a slow creep between milestones keeps the bar alive.
struct GeneratingView: View {
    @ObservedObject var viewModel: SceneMeViewModel

    @State private var creep = 0
    @State private var ringRotation: Double = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Progress milestones marking the end of each phase.
    private static let milestones = [20, 60, 95, 100]

    private var phases: [(message: String, systemImage: String)] {
        [
            ("Uploading and analyzing your photo…", "person.crop.rectangle.badge.plus"),
            ("Placing you in \(viewModel.generatingSceneName), styling your outfit…", "tshirt"),
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

    /// Current phase derived from the real backend progress.
    private var phaseIndex: Int {
        let progress = viewModel.generationProgress
        if progress >= 95 { return 3 }
        if progress >= 60 { return 2 }
        if progress >= 20 { return 1 }
        return 0
    }

    /// Real progress plus a slow creep, capped just below the next milestone
    /// so the bar keeps moving without ever lying about being further ahead.
    private var displayedProgress: Int {
        let real = viewModel.generationProgress
        let ceiling = Self.milestones[phaseIndex] - 1
        return min(max(real, min(real + creep, ceiling)), 99)
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
            creep = 0
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                creep += 2
            }
        }
        .onChange(of: viewModel.generationProgress) { _, _ in
            // A real milestone arrived — restart the creep from the new baseline.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                creep = 0
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: phaseIndex)
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
