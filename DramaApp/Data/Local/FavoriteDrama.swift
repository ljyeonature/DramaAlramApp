import Foundation
import SwiftData

/// 로컬 즐겨찾기 — 로그인 없이도 동작.
/// 드라마 필드를 denormalize 해서 FavoritesView가 네트워크 없이 렌더 가능.
/// Week 5 Apple Sign In 들어오면 이 로컬 데이터를 Supabase `favorites` 테이블로 sync.
@Model
final class FavoriteDrama {
    @Attribute(.unique) var dramaId: UUID
    var title: String
    var titleEn: String?
    var synopsis: String?
    var posterURLString: String?     // SwiftData가 URL? 직접 저장은 가능하나 String 이 더 안정적
    var channelId: UUID?
    var statusRaw: String            // Drama.Status.rawValue
    var totalEpisodes: Int?
    var startDate: Date?
    var endDate: Date?
    var tmdbId: Int?
    var addedAt: Date
    var notifyAir: Bool
    var notifyNewEpisode: Bool

    init(drama: Drama) {
        self.dramaId = drama.id
        self.title = drama.title
        self.titleEn = drama.titleEn
        self.synopsis = drama.synopsis
        self.posterURLString = drama.posterURL?.absoluteString
        self.channelId = drama.channelId
        self.statusRaw = drama.status.rawValue
        self.totalEpisodes = drama.totalEpisodes
        self.startDate = drama.startDate
        self.endDate = drama.endDate
        self.tmdbId = drama.tmdbId
        self.addedAt = Date()
        self.notifyAir = true
        self.notifyNewEpisode = true
    }

    var posterURL: URL? {
        posterURLString.flatMap(URL.init(string:))
    }

    var status: Drama.Status {
        Drama.Status(rawValue: statusRaw) ?? .ended
    }

    /// 네비게이션이 Drama 기반이므로 역변환 헬퍼.
    func toDrama() -> Drama {
        Drama(
            id: dramaId,
            title: title,
            titleEn: titleEn,
            synopsis: synopsis,
            posterURL: posterURL,
            channelId: channelId,
            status: status,
            totalEpisodes: totalEpisodes,
            startDate: startDate,
            endDate: endDate,
            tmdbId: tmdbId
        )
    }
}
