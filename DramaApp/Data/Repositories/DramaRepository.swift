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

    /// 지정 기간 내 이 드라마의 예정된 에피소드. 알림 스케줄링용.
    /// - Parameter until: exclusive upper bound.
    func upcomingEpisodes(dramaId: UUID, from: Date, until: Date) async throws -> [Episode]
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

/// (드라마, KST 하루) 단위로 묶은 편성표 아이템.
/// Netflix/티빙 등 전편 공개 OTT 는 같은 날짜에 여러 회차 → 한 행으로 표시.
/// 일반 드라마는 하루 1회 → episodeNumbers 1개.
struct DailyScheduleItem: Identifiable, Hashable, Sendable {
    let drama: Drama
    let channel: Channel
    /// 대표 방영 시각 (그룹 내 가장 이른 회).
    let airTime: Date
    /// 오름차순 회차 번호. 1개 = 일반 방영, 2개 이상 = 배치 공개.
    let episodeNumbers: [Int]
    let durationMin: Int

    var id: String {
        "\(drama.id.uuidString)-\(Int(airTime.timeIntervalSince1970))"
    }

    var isBatch: Bool { episodeNumbers.count > 1 }

    /// UI 에 표시할 회차 라벨.
    /// - 단일 회차: "8회"
    /// - 배치 + 총 회차 수와 동일: "전편 공개 (1-8회)"
    /// - 배치 + 연속: "1-8회 공개"
    /// - 배치 + 비연속: "1, 3, 5회"
    var episodeLabel: String {
        guard let first = episodeNumbers.first, let last = episodeNumbers.last else {
            return ""
        }
        if episodeNumbers.count == 1 {
            return "\(first)회"
        }
        let contiguous = last - first + 1 == episodeNumbers.count
        if let total = drama.totalEpisodes, episodeNumbers.count == total {
            return "전편 공개 (\(first)-\(last)회)"
        }
        if contiguous {
            return "\(first)-\(last)회 공개"
        }
        return episodeNumbers.map { "\($0)회" }.joined(separator: ", ")
    }
}

private struct DramaDayKey: Hashable {
    let dramaId: UUID
    let dayBucket: Int // KST day since epoch
}

extension Array where Element == ScheduledEpisode {
    /// (드라마 id, KST 하루) 기준으로 묶어 DailyScheduleItem 배열로 반환.
    /// 원본 순서(가장 이른 airTime 순) 보존.
    func groupedByDramaDay() -> [DailyScheduleItem] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? cal.timeZone

        var order: [DramaDayKey] = []
        var buckets: [DramaDayKey: (
            drama: Drama, channel: Channel, episodes: [Episode], airTime: Date
        )] = [:]

        for item in self {
            let day = cal.startOfDay(for: item.episode.airTime)
            let key = DramaDayKey(
                dramaId: item.drama.id,
                dayBucket: Int(day.timeIntervalSince1970 / 86400)
            )
            if var existing = buckets[key] {
                existing.episodes.append(item.episode)
                if item.episode.airTime < existing.airTime {
                    existing.airTime = item.episode.airTime
                }
                buckets[key] = existing
            } else {
                buckets[key] = (item.drama, item.channel, [item.episode], item.episode.airTime)
                order.append(key)
            }
        }

        return order.compactMap { key -> DailyScheduleItem? in
            guard let b = buckets[key] else { return nil }
            let sorted = b.episodes.sorted { $0.number < $1.number }
            return DailyScheduleItem(
                drama: b.drama,
                channel: b.channel,
                airTime: b.airTime,
                episodeNumbers: sorted.map(\.number),
                durationMin: sorted.first?.durationMin ?? 0
            )
        }
    }
}

extension Array where Element == Episode {
    /// (KST 하루) 기준 그룹. NotificationScheduler 가 전편 공개 알림 1개로 묶기 위해 사용.
    func groupedByDay() -> [(airTime: Date, episodes: [Episode])] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? cal.timeZone
        var order: [Int] = []
        var buckets: [Int: (airTime: Date, episodes: [Episode])] = [:]
        for ep in self {
            let day = cal.startOfDay(for: ep.airTime)
            let bucket = Int(day.timeIntervalSince1970 / 86400)
            if var existing = buckets[bucket] {
                existing.episodes.append(ep)
                if ep.airTime < existing.airTime { existing.airTime = ep.airTime }
                buckets[bucket] = existing
            } else {
                buckets[bucket] = (ep.airTime, [ep])
                order.append(bucket)
            }
        }
        return order.compactMap { buckets[$0] }
    }
}

enum DramaRepositoryError: Error {
    case notFound
    case configMissing(String)
}
