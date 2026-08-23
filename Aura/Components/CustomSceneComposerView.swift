import SwiftUI

/// Sheet where the user describes their own scene template:
/// a name, the place/mood, and optionally what to wear.
struct CustomSceneComposerView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: SceneMeViewModel

    @State private var name = ""
    @State private var sceneDescription = ""
    @State private var outfit = ""
    @State private var isImproving = false
    @State private var improvementError: String?

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

                    aiImproveCard
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

    private var aiImproveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(SceneMeTheme.gold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("IMPROVE WITH OPENAI")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(SceneMeTheme.gold)
                    Text("Adds cinematic lighting, camera, atmosphere, and a coordinated outfit.")
                        .font(.system(size: 11))
                        .foregroundStyle(SceneMeTheme.subtleText)
                }
            }

            Button {
                Task { await improveWithAI() }
            } label: {
                HStack(spacing: 8) {
                    if isImproving {
                        ProgressView().tint(Color.black)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isImproving ? "IMPROVING…" : "ENHANCE TEMPLATE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                }
                .foregroundStyle(Color.black.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(SceneMeTheme.gold)
                .clipShape(Capsule())
            }
            .buttonStyle(SceneMePressButtonStyle())
            .disabled(!isValid || isImproving)
            .opacity(isValid ? 1 : 0.45)

            if let improvementError {
                Text(improvementError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(SceneMeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous)
                .stroke(SceneMeTheme.gold.opacity(0.35), lineWidth: 1)
        }
    }

    @MainActor
    private func improveWithAI() async {
        guard !isImproving else { return }
        isImproving = true
        improvementError = nil
        defer { isImproving = false }

        do {
            let improved = try await viewModel.improveCustomScene(
                name: name,
                description: sceneDescription,
                outfit: outfit
            )
            withAnimation(.easeInOut(duration: 0.25)) {
                name = improved.name
                sceneDescription = improved.description
                outfit = improved.outfit
            }
        } catch {
            improvementError = (error as? LocalizedError)?.errorDescription
                ?? "Could not improve this template. Please try again."
        }
    }

    private var createBar: some View {
        VStack(spacing: 8) {
            SceneMeCTAButton(
                title: "Save & Use Scene",
                systemImage: "wand.and.stars",
                isEnabled: isValid
            ) {
                onCreate(name, sceneDescription, outfit)
                dismiss()
            }

            if !isValid {
                Text("Add a short place description (at least 12 characters)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(SceneMeTheme.faintText)
            } else {
                Text("Saved to Yours so you can reuse it later")
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
