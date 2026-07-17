import Foundation
import SwiftUI

/// Canonical legal URLs for App Store, paywall, Profile, and auth.
enum SceneMeLegal {
    static let privacyURL = URL(string: "https://styleia.onrender.com/privacy")!
    static let termsURL = URL(string: "https://styleia.onrender.com/terms")!

    /// Compact "Privacy Policy  ·  Terms of Use" footer used on auth / paywall.
    struct InlineLinks: View {
        var body: some View {
            HStack(spacing: 0) {
                Link("Privacy Policy", destination: privacyURL)
                Text("  ·  ")
                    .foregroundStyle(SceneMeTheme.faintText)
                Link("Terms of Use", destination: termsURL)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SceneMeTheme.subtleText)
        }
    }

    /// Settings-style rows for Profile — where users expect legal links.
    struct SettingsSection: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("LEGAL")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(SceneMeTheme.subtleText)

                VStack(spacing: 0) {
                    linkRow(
                        icon: "hand.raised.fill",
                        title: "Privacy Policy",
                        url: privacyURL
                    )

                    Divider()
                        .background(SceneMeTheme.hairline)
                        .padding(.leading, 54)

                    linkRow(
                        icon: "doc.text.fill",
                        title: "Terms of Use",
                        url: termsURL
                    )
                }
                .background(SceneMeTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                        .stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
            }
        }

        private func linkRow(icon: String, title: String, url: URL) -> some View {
            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SceneMeTheme.gold)
                        .frame(width: 30, height: 30)
                        .background(SceneMeTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SceneMeTheme.text)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SceneMeTheme.faintText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(SceneMePressButtonStyle())
        }
    }
}
