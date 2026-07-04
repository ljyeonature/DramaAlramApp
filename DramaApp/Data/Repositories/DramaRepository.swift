import Foundation

protocol DramaRepository: Sendable {
    /// 채널 목록 (편성표 필터용).
    func channels() async throws -> [Channel]

    /// 특정 날짜의 편성표를 조회한다. KST 기준 하루.
    /// - Parameter channelIDs: nil이면 모든 채널.
    func schedule(date: Date, channelIDs: [UUID]?) async throws -> [ScheduledEpisode]

    func drama(id: UUID) async throws -> Drama

    /// 통합 검색 — 제목 + 출연진. 두 쿼리를 병렬로 날리고 묶어 반환.
    func search(query: String) async throws -> SearchResults

    /// 드라마 출연진 (주연부터 정렬).
    func cast(for dramaId: UUID) async throws -> [CastMember]

    /// 이 드라마를 볼 수 있는 채널 목록 (본방 + OTT 다시보기).
    func availability(for dramaId: UUID) async throws -> [Channel]
}

// MARK: - Search

/// 통합 검색 결과 — 제목 매칭 드라마 + 배우별 매칭(배우 한 명당 출연작 묶음).
struct SearchResults: Sendable {
    let dramas: [Drama]
    let personMatches: [PersonMatch]

    static let empty = SearchResults(dramas: [], personMatches: [])
    var isEmpty: Bool { dramas.isEmpty && personMatches.isEmpty }
}

struct PersonMatch: Sendable, Identifiable {
    var id: UUID { person.id }
    let person: Person
    let dramas: [Drama]
}

/// 편성표 한 행의 표시용 합성 모델 — Episode + Drama + Channel.
struct ScheduledEpisode: Identifiable, Hashable, Sendable {
    var id: UUID { episode.id }
    let episode: Episode
    let drama: Drama
    let channel: Channel
}

enum DramaRepositoryError: Error {
    case notFound
    case configMissing(String)
}
