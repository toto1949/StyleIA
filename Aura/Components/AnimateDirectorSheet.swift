import SwiftUI

/// Pro Video Director — choose how the still comes to life, optionally
/// what they say, and free-text direction for the performance.
struct AnimateDirectorSheet: View {
    let sceneName: String
    let sceneLocation: String
    let sceneCategory: SceneCategory?
    let existingClips: [SceneVideoClip]
    let onGenerate: (VideoMotionStyle, String, String) -> Void
    let onPlayClip: (SceneVideoClip) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var style: VideoMotionStyle = .talking
    @State private var spokenLine = ""
    @State private var directionNote = ""

    private var suggestions: [String] {
        VideoTalkSuggestions.lines(for: sceneName, location: sceneLocation, category: sceneCategory)
    }

    private var matchingExisting: SceneVideoClip? {
        let line = style.showsTalkLine
            ? spokenLine.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let direction = directionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return existingClips.first {
            $0.motionStyle == style.rawValue
                && ($0.spokenLine ?? "") == line
                && ($0.directionNote ?? "") == direction
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if !existingClips.isEmpty {
                        yourClips
                    }

                    styleGrid

                    directionSection

                    if style.showsTalkLine {
                        talkSection
                    }

                    generateButton

                    Text("You can leave this screen — we’ll notify you when the clip is ready.")
                        .font(.system(size: 11))
                        .foregroundStyle(SceneMeTheme.faintText)
                        .frame(maxWidth: .infinity, alignment: .center)
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

            Text("Pick a style, optionally describe the motion, and for Talking add the line — voice matches the subject and lips stay in sync.")
                .font(.system(size: 14))
                .foregroundStyle(SceneMeTheme.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var yourClips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR CLIPS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(SceneMeTheme.subtleText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(existingClips) { clip in
                        Button {
                            onPlayClip(clip)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clip.displayTitle)
                                        .font(.system(size: 13, weight: .semibold))
                                    if let line = clip.captionText {
                                        Text(line)
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .foregroundStyle(SceneMeTheme.faintText)
                                    }
                                }
                            }
                            .foregroundStyle(SceneMeTheme.gold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(SceneMeTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                                    .stroke(SceneMeTheme.gold.opacity(0.4), lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
                        }
                        .buttonStyle(SceneMePressButtonStyle())
                    }
                }
            }
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
        let alreadyMade = existingClips.contains { $0.motionStyle == item.rawValue }

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                style = item
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
                    Spacer()
                    if alreadyMade {
                        Text("SAVED")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(SceneMeTheme.gold)
                    }
                }

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

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW SHOULD IT MOVE?")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(SceneMeTheme.subtleText)

            TextField("Type your direction… e.g. slow walk toward camera", text: $directionNote, axis: .vertical)
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
                    ForEach(VideoDirectionSuggestions.chips, id: \.self) { chip in
                        Button {
                            directionNote = chip
                        } label: {
                            Text(chip)
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
        }
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

            Text("Tip: short lines lip-sync best — under ~80 characters.")
                .font(.system(size: 11))
                .foregroundStyle(SceneMeTheme.faintText)
        }
    }

    private var generateButton: some View {
        let line = spokenLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let direction = directionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = {
            if let matchingExisting {
                return "Play \(matchingExisting.displayTitle)"
            }
            if style == .talking && line.isEmpty {
                return "Animate talking clip"
            }
            return existingClips.isEmpty ? "Generate clip" : "Generate another clip"
        }()

        return SceneMeCTAButton(
            title: title,
            systemImage: matchingExisting == nil ? "play.circle.fill" : "play.fill"
        ) {
            if let matchingExisting {
                onPlayClip(matchingExisting)
            } else {
                onGenerate(style, style.showsTalkLine ? line : "", direction)
            }
            dismiss()
        }
    }
}
