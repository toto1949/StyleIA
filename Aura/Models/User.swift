import Foundation

struct User: Codable, Hashable {
    let userId: String
    let email: String
    let accessToken: String

    init(userId: String, email: String, accessToken: String) {
        self.userId = userId
        self.email = email
        self.accessToken = accessToken
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case email
        case accessToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        accessToken = try container.decode(String.self, forKey: .accessToken)
    }
}
