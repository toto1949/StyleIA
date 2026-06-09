import Foundation

struct StyleIAPlaceholderJobClient: StyleIAJobPreparing {
    func prepare(
        _ draft: StyleIAJobDraft,
        photo: StyleIAPhotoPayload?,
        onPartialLooks: @MainActor @escaping ([StyleIALook]) -> Void
    ) async throws -> StyleIAJobReceipt {
        _ = photo
        _ = onPartialLooks
        try await Task.sleep(for: .milliseconds(250))

        return StyleIAJobReceipt(
            localJobId: draft.localJobId,
            message: "Placeholder job ready for backend handoff",
            recommendations: nil,
            resultURLs: [],
            looks: []
        )
    }
}
