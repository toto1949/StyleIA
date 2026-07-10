import SwiftUI

/// Time of day selector — three image-style cards (Morning / Golden Hr / Night).
struct TimeSliderView: View {
    let availableTimes: [TimeOfDay]
    @Binding var selection: TimeOfDay

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TimeOfDay.allCases) { time in
                let isAvailable = availableTimes.contains(time)
                let isSelected = selection == time

                Button {
                    guard isAvailable else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = time
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                                .fill(gradient(for: time))
                                .frame(height: 56)
                                .overlay {
                                    Text(time.emoji)
                                        .font(.system(size: 24))
                                }

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Color.black)
                                    .frame(width: 18, height: 18)
                                    .background(SceneMeTheme.gold)
                                    .clipShape(Circle())
                                    .padding(5)
                            }
                        }

                        Text(time.title.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
                    }
                    .padding(6)
                    .background(SceneMeTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 4, style: .continuous)
                            .stroke(isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: isSelected ? 1.5 : 1)
                    }
                    .opacity(isAvailable ? 1 : 0.3)
                }
                .buttonStyle(SceneMePressButtonStyle())
                .disabled(!isAvailable)
            }
        }
    }

    private func gradient(for time: TimeOfDay) -> LinearGradient {
        let colors: [Color]
        switch time {
        case .morning:
            colors = [Color(hex: 0x355070), Color(hex: 0xE7B86A)]
        case .goldenHour:
            colors = [Color(hex: 0xB35C37), Color(hex: 0x5C2A2B)]
        case .night:
            colors = [Color(hex: 0x141A33), Color(hex: 0x05060D)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}
