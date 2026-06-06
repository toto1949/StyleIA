import UIKit

struct HapticManager {
    func primaryTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func styleSelected() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func generationComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func generationFailed() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    func saveSucceeded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func deleteConfirmed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
