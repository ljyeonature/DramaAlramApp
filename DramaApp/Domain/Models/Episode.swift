import Foundation

struct Episode: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let dramaId: UUID
    let number: Int
    let airTime: Date
    let durationMin: Int
    let isSpecial: Bool

    enum CodingKeys: String, CodingKey {
        case id, number
        case dramaId = "drama_id"
        case airTime = "air_time"
        case durationMin = "duration_min"
        case isSpecial = "is_special"
    }
}
