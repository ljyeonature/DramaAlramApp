import Foundation

struct Channel: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let type: ChannelType
    let logoURL: URL?

    enum ChannelType: String, Codable, Sendable {
        case broadcast = "BROADCAST"
        case ott = "OTT"
    }

    enum CodingKeys: String, CodingKey {
        case id, code, name, type
        case logoURL = "logo_url"
    }
}
