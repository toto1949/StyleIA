import UIKit

protocol StyleIAImageAnalyzing: Sendable {
    func validate(_ image: UIImage) async throws -> StyleIAImageValidationResult
}
