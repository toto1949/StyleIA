import SwiftData
import UIKit

@MainActor
enum PreviewData {
    static let container: DependencyContainer = {
        do {
            let schema = Schema([GenerationRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            let container = DependencyContainer(modelContainer: modelContainer)

            for (index, url) in sampleURLs.enumerated() {
                let colors: [UIColor] = [.systemPink, .systemTeal, .systemPurple, .systemOrange]
                container.imageCacheService.store(sampleImage(color: colors[index % colors.count]), for: url)
            }

            container.historyService.saveLocally(sampleRecord)
            return container
        } catch {
            preconditionFailure("Preview container failed: \(error.localizedDescription)")
        }
    }()

    static let coordinator: AppCoordinator = {
        let coordinator = AppCoordinator(container: container)
        coordinator.root = .main
        return coordinator
    }()

    static let sampleURLs: [URL] = [
        URL(string: "https://example.com/styleai-1.jpg"),
        URL(string: "https://example.com/styleai-2.jpg"),
        URL(string: "https://example.com/styleai-3.jpg"),
        URL(string: "https://example.com/styleai-4.jpg")
    ].compactMap { $0 }

    static var sampleRecord: GenerationRecord {
        GenerationRecord(
            jobId: "preview-job",
            styleGoal: .luxury,
            thumbnailData: sampleImage(color: .systemPink).jpegData(compressionQuality: 0.8) ?? Data(),
            resultURLs: sampleURLs.map(\.absoluteString),
            originalPhotoURL: sampleURLs[0].absoluteString,
            createdAt: Date(),
            isSaved: false
        )
    }

    static var resultsInput: ResultsInput {
        ResultsInput(
            jobId: "preview-job",
            styleGoal: .luxury,
            resultURLs: sampleURLs.map(\.absoluteString),
            originalImage: sampleImage(color: .systemBlue),
            originalPhotoURL: sampleURLs[0].absoluteString,
            readOnly: false,
            s3Key: "preview-s3-key"
        )
    }

    static func sampleImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.white.withAlphaComponent(0.92).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 330, y: 180, width: 240, height: 240))

            UIColor.black.withAlphaComponent(0.18).setFill()
            context.cgContext.fill(CGRect(x: 250, y: 470, width: 400, height: 520))

            UIColor.white.withAlphaComponent(0.65).setFill()
            context.cgContext.fill(CGRect(x: 300, y: 540, width: 300, height: 48))
            context.cgContext.fill(CGRect(x: 340, y: 620, width: 220, height: 36))
        }
    }
}
