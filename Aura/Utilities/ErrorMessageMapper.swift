import Foundation

struct ErrorMessageMapper {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return L10n.string("error.sessionExpired")
            case .notFound:
                return L10n.string("error.notFound")
            case .serverError:
                return L10n.string("error.server")
            case .networkError:
                return L10n.string("error.network")
            case .decodingFailed:
                return L10n.string("error.server")
            case .invalidRequest:
                return L10n.string("error.invalidRequest")
            }
        }

        if let safetyError = error as? SafetyError {
            switch safetyError {
            case .noFaceDetected:
                return L10n.string("error.noFace")
            case .potentiallyUnsafe:
                return L10n.string("error.potentiallyUnsafe")
            }
        }

        if error is CancellationError {
            return L10n.string("error.cancelled")
        }

        return L10n.string("error.server")
    }

    static var generationFailed: String {
        L10n.string("error.generationFailed")
    }
}
