import Foundation

struct Person: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let tmdbId: Int?
    let name: String
    let profileURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name
        case tmdbId = "tmdb_id"
        case profileURL = "profile_url"
    }
}

/// 드라마 출연진 한 명 (Person + 극중 정보).
struct CastMember: Identifiable, Hashable, Sendable {
    var id: UUID { person.id }
    let person: Person
    let character: String?
    let displayOrder: Int
}
