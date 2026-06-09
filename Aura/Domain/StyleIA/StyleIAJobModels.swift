import Foundation

struct StyleIAJobDraft: Equatable {
    let localJobId: String
    let personaId: String
    let personaName: String
    let matchScore: Int
    let faceShape: String
    let undertone: String
    let build: String
    let styleGoal: String
    let styleGoals: [String]
    let subjectGender: String
    let styleProfile: StyleIAStyleProfile
    let photoSource: String
    let requestedOutputs: [String]
}

struct StyleIAStyleProfile: Codable, Equatable {
    let subjectGender: String
    let ageRange: String
    let bodyType: String
    let heightRange: String
    let skinTone: String
    let undertone: String
    let hairColor: String
    let faceShape: String
    let fitPreference: String
    let colorPreference: String
    let modestyPreference: String
    let climate: String
    let occasion: String
    let budget: String
    let stylePersona: String
    let favoriteColors: [String]
    let avoid: [String]
}

enum StyleIASubjectGender: String, CaseIterable, Identifiable {
    case male
    case female
    case nonbinary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male:
            return "Male"
        case .female:
            return "Female"
        case .nonbinary:
            return "Nonbinary"
        }
    }
}

struct StyleIALook: Codable, Equatable, Identifiable {
    let id: String
    let styleGoal: String
    let title: String
    let subtitle: String
    let imageURL: URL
    let assetURLs: StyleIALookAssetURLs?
    let products: [StyleIAProductMatch]?
}

struct StyleIALookAssetURLs: Codable, Equatable {
    let outfit: URL?
    let shoes: URL?
    let frames: URL?
    let accessories: URL?
}

struct StyleIAProductMatch: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let brand: String
    let price: String
    let category: String
    let styleGoal: String
    let matchReason: String
    let imageURL: URL?
    let merchantURL: URL
}

extension StyleIALook {
    func assetURL(for module: StyleIALookAssetModule) -> URL? {
        switch module {
        case .outfit:
            return assetURLs?.outfit ?? imageURL
        case .shoes:
            return assetURLs?.shoes
        case .frames:
            return assetURLs?.frames
        case .accessories:
            return assetURLs?.accessories
        }
    }

    func imageURL(for module: StyleIALookAssetModule) -> URL {
        switch module {
        case .outfit:
            return assetURLs?.outfit ?? imageURL
        case .shoes:
            return assetURLs?.shoes ?? imageURL
        case .frames:
            return assetURLs?.frames ?? imageURL
        case .accessories:
            return assetURLs?.accessories ?? imageURL
        }
    }
}

enum StyleIALookAssetModule: Equatable {
    case outfit
    case shoes
    case frames
    case accessories
}

struct StyleIARecommendations: Codable, Equatable {
    let title: String
    let bullets: [String]
    let tags: [String]
}

struct StyleIAJobReceipt: Equatable {
    let localJobId: String
    let message: String
    let recommendations: StyleIARecommendations?
    let resultURLs: [URL]
    let looks: [StyleIALook]
}

struct StyleIAPhotoPayload: Equatable {
    let data: Data
    let contentType: String
}

enum StyleIAFlowStep {
    case splash
    case inspiration
    case upload
    case analysing
    case styleCard
    case twins
}
