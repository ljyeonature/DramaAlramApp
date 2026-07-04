import Foundation

struct Drama: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    let titleEn: String?
    let synopsis: String?
    let posterURL: URL?
    let channelId: UUID?
    let status: Status
    let totalEpisodes: Int?
    let startDate: Date?
    let endDate: Date?
    let tmdbId: Int?

    enum Status: String, Codable, Sendable {
        case upcoming = "UPCOMING"
        case onAir = "ON_AIR"
        case ended = "ENDED"
    }

    // Supabase는 snake_case 컬럼명 → CodingKeys로 매핑.
    enum CodingKeys: String, CodingKey {
        case id, title, synopsis, status
        case titleEn = "title_en"
        case posterURL = "poster_url"
        case channelId = "channel_id"
        case totalEpisodes = "total_episodes"
        case startDate = "start_date"
        case endDate = "end_date"
        case tmdbId = "tmdb_id"
    }
}
