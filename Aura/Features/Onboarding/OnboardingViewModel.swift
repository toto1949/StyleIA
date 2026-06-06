import Foundation
import Observation

struct OnboardingSlide: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
}

@MainActor
@Observable
final class OnboardingViewModel {
    var currentIndex = 0
    var isLoading = false
    var errorMessage: String?

    let slides: [OnboardingSlide] = [
        OnboardingSlide(
            id: 0,
            title: L10n.string("onboarding.slide1.title"),
            subtitle: L10n.string("onboarding.slide1.subtitle")
        ),
        OnboardingSlide(
            id: 1,
            title: L10n.string("onboarding.slide2.title"),
            subtitle: L10n.string("onboarding.slide2.subtitle")
        ),
        OnboardingSlide(
            id: 2,
            title: L10n.string("onboarding.slide3.title"),
            subtitle: L10n.string("onboarding.slide3.subtitle")
        )
    ]

    var isLastSlide: Bool {
        currentIndex == slides.count - 1
    }

    func advance(completion: () -> Void) {
        if isLastSlide {
            completion()
        } else {
            currentIndex += 1
        }
    }
}
