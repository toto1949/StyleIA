import Foundation

protocol StyleIAJobPreparing {
    func prepare(
        _ draft: StyleIAJobDraft,
        photo: StyleIAPhotoPayload?,
        onPartialLooks: @MainActor @escaping ([StyleIALook]) -> Void
    ) async throws -> StyleIAJobReceipt
}
