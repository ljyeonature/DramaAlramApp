import Foundation

/// Supabase(PostgREST) 기반 DramaRepository 실구현.
final class SupabaseDramaRepository: DramaRepository {
    private let http: SupabaseHTTPClient

    init(http: SupabaseHTTPClient) {
        self.http = http
    }

    // MARK: - Channels

    func channels() async throws -> [Channel] {
        try await http.get(
            "channels",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "code.asc"),
            ],
            as: [Channel].self
        )
    }

    // MARK: - Schedule

    func schedule(date: Date, channelIDs: [UUID]?) async throws -> [ScheduledEpisode] {
        // KST 기준 하루 범위.
        let (startISO, endISO) = Self.kstDayBounds(for: date)

        // 채널 필터가 있으면 drama_availability 를 inner join 해서
        // "본방이든 OTT 다시보기든 이 채널에서 볼 수 있는" 드라마를 모두 포함.
        // 필터 없으면 단순 episodes+dramas+channels 조인.
        let selectValue: String
        var items: [URLQueryItem] = [
            URLQueryItem(name: "air_time", value: "gte.\(startISO)"),
            URLQueryItem(name: "air_time", value: "lt.\(endISO)"),
            URLQueryItem(name: "order", value: "air_time.asc"),
        ]

        // dramas → channels 경로가 둘(직접 FK + drama_availability M:N)이라
        // 모호성 회피 위해 임베드 힌트에 FK 컬럼명(`!channel_id`) 명시.
        if let channelIDs, !channelIDs.isEmpty {
            selectValue = "*,drama:dramas!inner(*,channel:channels!channel_id(*),availability:drama_availability!inner(channel_id))"
            let inList = channelIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
            items.append(URLQueryItem(name: "drama.availability.channel_id",
                                       value: "in.(\(inList))"))
        } else {
            selectValue = "*,drama:dramas(*,channel:channels!channel_id(*))"
        }
        items.append(URLQueryItem(name: "select", value: selectValue))

        let rows = try await http.get(
            "episodes",
            queryItems: items,
            as: [ScheduleRow].self
        )

        return rows.compactMap { row -> ScheduledEpisode? in
            guard let drama = row.drama else { return nil }
            let episode = Episode(
                id: row.id,
                dramaId: row.dramaId,
                number: row.number,
                airTime: row.airTime,
                durationMin: row.durationMin,
                isSpecial: row.isSpecial
            )
            return ScheduledEpisode(
                episode: episode,
                drama: drama.toDrama(),
                channel: drama.channel
            )
        }
    }

    // MARK: - Drama detail

    func drama(id: UUID) async throws -> Drama {
        let rows: [Drama] = try await http.get(
            "dramas",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let drama = rows.first else { throw DramaRepositoryError.notFound }
        return drama
    }

    // MARK: - Cast

    func cast(for dramaId: UUID) async throws -> [CastMember] {
        let rows: [CastAPIRow] = try await http.get(
            "drama_casts",
            queryItems: [
                URLQueryItem(name: "drama_id",
                             value: "eq.\(dramaId.uuidString.lowercased())"),
                URLQueryItem(name: "select", value: "*,person:persons(*)"),
                URLQueryItem(name: "order", value: "display_order.asc"),
            ]
        )
        return rows.compactMap { row -> CastMember? in
            guard let person = row.person else { return nil }
            return CastMember(
                person: person,
                character: row.character,
                displayOrder: row.displayOrder
            )
        }
    }

    // MARK: - Availability

    func availability(for dramaId: UUID) async throws -> [Channel] {
        let rows: [AvailabilityAPIRow] = try await http.get(
            "drama_availability",
            queryItems: [
                URLQueryItem(name: "drama_id",
                             value: "eq.\(dramaId.uuidString.lowercased())"),
                URLQueryItem(name: "select", value: "channel:channels(*)"),
            ]
        )
        return rows.compactMap { $0.channel }
    }

    // MARK: - Search

    func search(query: String) async throws -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // 제목 + 출연진 두 쿼리 병렬 발사.
        async let titles = searchByTitle(query: trimmed)
        async let casts = searchByCast(query: trimmed)
        return SearchResults(
            dramas: (try? await titles) ?? [],
            personMatches: (try? await casts) ?? []
        )
    }

    private func searchByTitle(query: String) async throws -> [Drama] {
        let pattern = "*\(query)*"
        return try await http.get(
            "dramas",
            queryItems: [
                URLQueryItem(name: "title", value: "ilike.\(pattern)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "start_date.desc.nullslast"),
                URLQueryItem(name: "limit", value: "50"),
            ],
            as: [Drama].self
        )
    }

    private func searchByCast(query: String) async throws -> [PersonMatch] {
        let pattern = "*\(query)*"
        let rows: [PersonSearchRow] = try await http.get(
            "persons",
            queryItems: [
                URLQueryItem(name: "name", value: "ilike.\(pattern)"),
                URLQueryItem(
                    name: "select",
                    value: "id,tmdb_id,name,profile_url,drama_casts(drama:dramas(*))"
                ),
                URLQueryItem(name: "limit", value: "10"),
            ]
        )
        return rows.compactMap { $0.toMatch() }
    }

    // MARK: - Helpers

    /// 주어진 Date를 포함하는 KST 하루 [00:00, 다음날 00:00) 의 UTC ISO 8601 문자열을 반환.
    /// UTC(`Z`)로 보내는 이유: PostgREST는 URL 쿼리의 `+`를 공백으로 form-디코드하므로
    /// `+09:00` 표기를 그대로 보내면 400 에러가 난다. timestamptz는 어느 TZ 표기든 동일 비교.
    /// 예: 2026-05-25 KST → ("2026-05-24T15:00:00Z", "2026-05-25T15:00:00Z")
    private static func kstDayBounds(for date: Date) -> (String, String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (Self.utcISO.string(from: start), Self.utcISO.string(from: end))
    }

    private static let utcISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        // timeZone 미지정 = UTC. 출력: "2026-05-24T15:00:00Z"
        return f
    }()
}

// MARK: - Wire format DTOs

/// `/rest/v1/episodes?select=*,drama:dramas(*,channel:channels(*))` 의 응답 행.
private struct ScheduleRow: Decodable {
    let id: UUID
    let dramaId: UUID
    let number: Int
    let airTime: Date
    let durationMin: Int
    let isSpecial: Bool
    let drama: DramaWithChannel?

    enum CodingKeys: String, CodingKey {
        case id, number, drama
        case dramaId = "drama_id"
        case airTime = "air_time"
        case durationMin = "duration_min"
        case isSpecial = "is_special"
    }
}

/// 중첩된 `drama` 객체 — Drama 필드 + nested channel.
private struct DramaWithChannel: Decodable {
    let id: UUID
    let title: String
    let titleEn: String?
    let synopsis: String?
    let posterURL: URL?
    let channelId: UUID?
    let status: Drama.Status
    let totalEpisodes: Int?
    let startDate: Date?
    let endDate: Date?
    let tmdbId: Int?
    let channel: Channel

    enum CodingKeys: String, CodingKey {
        case id, title, synopsis, status, channel
        case titleEn = "title_en"
        case posterURL = "poster_url"
        case channelId = "channel_id"
        case totalEpisodes = "total_episodes"
        case startDate = "start_date"
        case endDate = "end_date"
        case tmdbId = "tmdb_id"
    }

    func toDrama() -> Drama {
        Drama(
            id: id, title: title, titleEn: titleEn, synopsis: synopsis,
            posterURL: posterURL, channelId: channelId, status: status,
            totalEpisodes: totalEpisodes, startDate: startDate, endDate: endDate,
            tmdbId: tmdbId
        )
    }
}

/// `/rest/v1/drama_casts?select=*,person:persons(*)` 의 응답 행.
private struct CastAPIRow: Decodable {
    let character: String?
    let displayOrder: Int
    let person: Person?

    enum CodingKeys: String, CodingKey {
        case character, person
        case displayOrder = "display_order"
    }
}

/// `/rest/v1/drama_availability?select=channel:channels(*)` 의 응답 행.
private struct AvailabilityAPIRow: Decodable {
    let channel: Channel?
}

/// `/rest/v1/persons?select=...,drama_casts(drama:dramas(*))` 의 응답 행.
private struct PersonSearchRow: Decodable {
    let id: UUID
    let tmdbId: Int?
    let name: String
    let profileURL: URL?
    let dramaCasts: [DramaCastJoin]

    enum CodingKeys: String, CodingKey {
        case id, name
        case tmdbId = "tmdb_id"
        case profileURL = "profile_url"
        case dramaCasts = "drama_casts"
    }

    func toMatch() -> PersonMatch? {
        let dramas = dramaCasts.compactMap { $0.drama }
        guard !dramas.isEmpty else { return nil }
        let person = Person(id: id, tmdbId: tmdbId, name: name, profileURL: profileURL)
        return PersonMatch(person: person, dramas: dramas)
    }
}

private struct DramaCastJoin: Decodable {
    let drama: Drama?
}
