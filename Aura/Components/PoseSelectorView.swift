import SwiftUI

/// Pose selector — horizontally scrolling tiles (Casual / Walking / Candid / Sitting / Action).
struct PoseSelectorView: View {
    @Binding var selection: PoseOption

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PoseOption.allCases) { pose in
                    let isSelected = selection == pose

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selection = pose
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(pose.emoji)
                                .font(.system(size: 24))

                            Text(pose.title.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.4)
                                .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
                        }
                        .frame(width: 82, height: 78)
                        .background(SceneMeTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                                .stroke(isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: isSelected ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(SceneMePressButtonStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }
}
