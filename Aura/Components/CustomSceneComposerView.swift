import SwiftUI

/// Sheet where the user describes their own scene template:
/// a name, the place/mood, and optionally what to wear.
struct CustomSceneComposerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sceneDescription = ""
    @State private var outfit = ""

    let onCreate: (_ name: String, _ description: String, _ outfit: String) -> Void

    private var isValid: Bool {
        sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    field(title: "Scene name", hint: "e.g. Marrakech Rooftop") {
                        TextField("", text: $name, prompt: prompt("My Scene"))
                            .textFieldStyle(.plain)
                    }

                    field(
                        title: "Describe the scene",
                        hint: "Where are you? What's around you? The more detail, the better the result."
                    ) {
                        TextField(
                            "",
                            text: $sceneDescription,
                            prompt: prompt("standing on a rooftop terrace in Marrakech, mosaic tiles, the Atlas mountains behind…"),
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .lineLimit(4...8)
                    }

                    field(title: "Outfit (optional)", hint: "Leave empty to auto-match an outfit to your scene.") {
                        TextField("", text: $outfit, prompt: prompt("flowing linen outfit in warm desert tones"), axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)

            createBar
        }
        .background(SceneMeTheme.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            SceneMeEyebrow(text: "Custom template")

            Text("Create Your Own Scene")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.text)

            Text("Describe any place in the world — or out of it — and we'll put you there.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(SceneMeTheme.subtleText)
        }
    }

    private func field<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(SceneMeTheme.subtleText)

            content()
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SceneMeTheme.text)
                .padding(14)
                .background(SceneMeTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous)
                        .stroke(SceneMeTheme.hairline, lineWidth: 1)
                }

            Text(hint)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SceneMeTheme.faintText)
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(SceneMeTheme.faintText)
    }

    private var createBar: some View {
        VStack(spacing: 8) {
            SceneMeCTAButton(
                title: "Use This Scene",
                systemImage: "wand.and.stars",
                isEnabled: isValid
            ) {
                onCreate(name, sceneDescription, outfit)
                dismiss()
            }

            if !isValid {
                Text("Describe your scene in a few words to continue")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(SceneMeTheme.faintText)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [SceneMeTheme.ink.opacity(0), SceneMeTheme.ink.opacity(0.92), SceneMeTheme.ink],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}
