import SwiftUI

/// Pro Video Director — choose how the still comes to life, and optionally
/// what the person is saying (Talking mode renders a caption).
struct AnimateDirectorSheet: View {
    let sceneName: String
    let sceneLocation: String
    let sceneCategory: SceneCategory?
    var hasExistingVideo: Bool
    let onGenerate: (VideoMotionStyle, String) -> Void
    let onPlayExisting: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var style: VideoMotionStyle = .talking
    @State private var spokenLine = ""

    private var suggestions: [String] {
        VideoTalkSuggestions.lines(for: sceneName, location: sceneLocation, category: sceneCategory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    styleGrid

                    if style.showsTalkLine {
                        talkSection
                    }

                    generateButton

                    if hasExistingVideo {
                        Button("Play existing clip") {
                            onPlayExisting()
                            dismiss()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SceneMeTheme.subtleText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
                .padding(22)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(SceneMeTheme.ink.ignoresSafeArea())
            .navigationTitle("Video Director")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(SceneMeTheme.subtleText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DIRECT YOUR CLIP")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundStyle(SceneMeTheme.gold)

            Text("Choose the performance. For Talking, write the line — it becomes the caption.")
                .font(.system(size: 14))
                .foregroundStyle(SceneMeTheme.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var styleGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(VideoMotionStyle.allCases) { item in
                styleCard(item)
            }
        }
    }

    private func styleCard(_ item: VideoMotionStyle) -> some View {
        let selected = style == item

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                style = item
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? SceneMeTheme.gold : SceneMeTheme.subtleText)

                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.text)

                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SceneMeTheme.faintText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(selected ? SceneMeTheme.gold.opacity(0.1) : SceneMeTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                    .stroke(selected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    private var talkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT ARE THEY SAYING?")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(SceneMeTheme.subtleText)

            TextField("Type the line…", text: $spokenLine, axis: .vertical)
                .lineLimit(2...3)
                .padding(14)
                .background(SceneMeTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                        .stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
                .foregroundStyle(SceneMeTheme.text)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { line in
                        Button {
                            spokenLine = line
                        } label: {
                            Text(line)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SceneMeTheme.gold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(SceneMeTheme.surface)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule().stroke(SceneMeTheme.gold.opacity(0.35), lineWidth: 1)
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(SceneMePressButtonStyle())
                    }
                }
            }

            Text("Tip: short lines caption best — under ~80 characters.")
                .font(.system(size: 11))
                .foregroundStyle(SceneMeTheme.faintText)
        }
    }

    private var generateButton: some View {
        SceneMeCTAButton(
            title: style == .talking && spokenLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Animate talking clip"
                : "Generate clip",
            systemImage: "play.circle.fill"
        ) {
            let line = spokenLine.trimmingCharacters(in: .whitespacesAndNewlines)
            onGenerate(style, style.showsTalkLine ? line : "")
            dismiss()
        }
    }
}
