import SwiftUI

/// Weather selector — square icon tiles (Clear / Rainy / Snow / Foggy).
struct WeatherToggleView: View {
    let availableWeather: [WeatherOption]
    @Binding var selection: WeatherOption

    var body: some View {
        HStack(spacing: 10) {
            ForEach(WeatherOption.allCases) { weather in
                let isAvailable = availableWeather.contains(weather)
                let isSelected = selection == weather

                Button {
                    guard isAvailable else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = weather
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: weather.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
                            .frame(height: 24)

                        Text(weather.title.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.subtleText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(SceneMeTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                            .stroke(isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: isSelected ? 1.5 : 1)
                    }
                    .opacity(isAvailable ? 1 : 0.3)
                }
                .buttonStyle(SceneMePressButtonStyle())
                .disabled(!isAvailable)
            }
        }
    }
}
