import SwiftUI

/// App Review-facing disclosure shown before any personal content is sent to
/// third-party AI services. Consent is scoped to the signed-in SceneMe account.
struct AIProcessingConsentView: View {
    @ObservedObject var viewModel: SceneMeViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(SceneMeTheme.gold)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Processing Permission")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(SceneMeTheme.text)

                        Text("Before SceneMe can generate or animate your scene, choose whether to share the content needed for that request with our AI providers.")
                            .font(.system(size: 14))
                            .foregroundStyle(SceneMeTheme.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    disclosure(
                        icon: "person.crop.rectangle.stack",
                        title: "What is shared",
                        detail: "Your selected photo, an optional companion photo, and the scene, outfit, motion, or spoken-text instructions you submit."
                    )
                    disclosure(
                        icon: "network",
                        title: "Who processes it",
                        detail: "OpenAI screens selected photos and user-written text for safety, and processes custom-scene text when you tap Improve with OpenAI. fal.ai processes image, video, and optional speech requests."
                    )
                    disclosure(
                        icon: "lock.shield",
                        title: "Your control",
                        detail: "Sharing is used to fulfill your request. You can decline now or withdraw permission anytime in Profile. Only upload photos you have permission to use."
                    )

                    Link(destination: SceneMeLegal.privacyURL) {
                        Label("Read the Privacy Policy", systemImage: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SceneMeTheme.gold)
                    }

                    if viewModel.hasAIProcessingConsent {
                        Button(role: .destructive) {
                            viewModel.revokeAIProcessingConsent()
                        } label: {
                            Text("WITHDRAW PERMISSION")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1.5)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.95, green: 0.45, blue: 0.42))
                    } else {
                        SceneMeCTAButton(
                            title: "Allow & Continue",
                            systemImage: "checkmark.shield"
                        ) {
                            viewModel.allowAIProcessing()
                        }

                        Button("NOT NOW") {
                            viewModel.isAIProcessingConsentPresented = false
                            viewModel.cancelAIProcessingConsentRequest()
                        }
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(SceneMeTheme.subtleText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                }
                .padding(24)
            }
            .background(SceneMeTheme.ink)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.isAIProcessingConsentPresented = false
                        viewModel.cancelAIProcessingConsentRequest()
                    }
                    .foregroundStyle(SceneMeTheme.gold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func disclosure(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SceneMeTheme.gold)
                .frame(width: 34, height: 34)
                .background(SceneMeTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.text)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(SceneMeTheme.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
