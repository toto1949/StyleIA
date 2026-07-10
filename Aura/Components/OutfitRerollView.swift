import SwiftUI

/// Circular "Re-roll outfit" action — regenerates only the outfit, keeps the scene.
struct OutfitRerollView: View {
    let isRerolling: Bool
    var isLocked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .stroke(isLocked ? SceneMeTheme.hairline : SceneMeTheme.gold, lineWidth: 1.4)
                        .frame(width: 48, height: 48)

                    if isRerolling {
                        ProgressView()
                            .tint(SceneMeTheme.gold)
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: isLocked ? "lock.fill" : "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isLocked ? SceneMeTheme.subtleText : SceneMeTheme.gold)
                            .frame(width: 48, height: 48)
                    }

                    if isLocked {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.88))
                            .padding(3)
                            .background(SceneMeTheme.gold)
                            .clipShape(Circle())
                            .offset(x: 2, y: -2)
                    }
                }

                Text("RE-ROLL")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(SceneMeTheme.subtleText)
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
        .disabled(isRerolling)
    }
}
