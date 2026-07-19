import Foundation

/// Supabase 연결 전 UI 개발용 Mock.
/// 백엔드가 붙으면 `SupabaseDramaRepository`로 교체한다.
final class MockDramaRepository: DramaRepository {
    func channels() async throws -> [Channel] {
        try await Task.sleep(for: .milliseconds(100))
        return [MockData.kbs2, MockData.mbc, MockData.sbs]
    }

    func schedule(date: Date, channelIDs: [UUID]?) async throws -> [ScheduledEpisode] {
        try await Task.sleep(for: .milliseconds(300))
        let all = MockData.todaysSchedule(date: date)
        guard let channelIDs, !channelIDs.isEmpty else { return all }
        let set = Set(channelIDs)
        return all.filter { set.contains($0.channel.id) }
    }

    func drama(id: UUID) async throws -> Drama {
        try await Task.sleep(for: .milliseconds(200))
        guard let drama = MockData.allDramas.first(where: { $0.id == id }) else {
            throw DramaRepositoryError.notFound
        }
        return drama
    }

    func search(query: String) async throws -> SearchResults {
        try await Task.sleep(for: .milliseconds(200))
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        let titleHits = MockData.allDramas.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
        let castHits = MockData.sampleCast
            .filter { $0.person.name.localizedCaseInsensitiveContains(trimmed) }
            .map { PersonMatch(person: $0.person, dramas: Array(MockData.allDramas.prefix(2))) }
        return SearchResults(dramas: titleHits, personMatches: castHits)
    }

    func cast(for dramaId: UUID) async throws -> [CastMember] {
        try await Task.sleep(for: .milliseconds(150))
        return MockData.sampleCast
    }

    func availability(for dramaId: UUID) async throws -> [Channel] {
        try await Task.sleep(for: .milliseconds(100))
        return []
    }

    func upcomingEpisodes(dramaId: UUID, from: Date, until: Date) async throws -> [Episode] {
        try await Task.sleep(for: .milliseconds(50))
        // 오늘부터 3일치 임의 에피소드 — UI 확인용.
        let cal = Calendar(identifier: .gregorian)
        return (0..<3).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: from),
                  let airTime = cal.date(bySettingHour: 21, minute: 0, second: 0, of: day),
                  airTime < until else { return nil }
            return Episode(
                id: UUID(), dramaId: dramaId, number: 10 + offset,
                airTime: airTime, durationMin: 70, isSpecial: false
            )
        }
    }
}

private enum MockData {
    static let kbs2 = Channel(id: UUID(), code: "KBS2", name: "KBS 2TV", type: .broadcast, logoURL: nil)
    static let mbc  = Channel(id: UUID(), code: "MBC",  name: "MBC",     type: .broadcast, logoURL: nil)
    static let sbs  = Channel(id: UUID(), code: "SBS",  name: "SBS",     type: .broadcast, logoURL: nil)

    static let allDramas: [Drama] = [
        Drama(id: UUID(), title: "샘플 드라마 A", titleEn: "Sample Drama A",
              synopsis: "예시 시놉시스입니다.", posterURL: nil,
              channelId: kbs2.id, status: .onAir, totalEpisodes: 16,
              startDate: nil, endDate: nil, tmdbId: nil),
        Drama(id: UUID(), title: "샘플 드라마 B", titleEn: nil,
              synopsis: nil, posterURL: nil,
              channelId: mbc.id, status: .onAir, totalEpisodes: 16,
              startDate: nil, endDate: nil, tmdbId: nil),
        Drama(id: UUID(), title: "샘플 드라마 C (첫방)", titleEn: nil,
              synopsis: nil, posterURL: nil,
              channelId: sbs.id, status: .upcoming, totalEpisodes: nil,
              startDate: nil, endDate: nil, tmdbId: nil),
    ]

    static let sampleCast: [CastMember] = [
        CastMember(
            person: Person(id: UUID(), tmdbId: 1, name: "샘플 배우 A", profileURL: nil),
            character: "주인공", displayOrder: 0
        ),
        CastMember(
            person: Person(id: UUID(), tmdbId: 2, name: "샘플 배우 B", profileURL: nil),
            character: "남자 주인공", displayOrder: 1
        ),
        CastMember(
            person: Person(id: UUID(), tmdbId: 3, name: "샘플 배우 C", profileURL: nil),
            character: "조연", displayOrder: 2
        ),
    ]

    static func todaysSchedule(date: Date) -> [ScheduledEpisode] {
        let calendar = Calendar(identifier: .gregorian)
        let slots: [(hour: Int, minute: Int, channel: Channel)] = [
            (19, 30, kbs2),
            (20, 40, mbc),
            (21, 50, sbs),
        ]
        return zip(allDramas, slots).enumerated().compactMap { idx, pair in
            let (drama, slot) = pair
            guard let airTime = calendar.date(
                bySettingHour: slot.hour, minute: slot.minute, second: 0, of: date
            ) else { return nil }
            let episode = Episode(
                id: UUID(), dramaId: drama.id, number: 12 - idx,
                airTime: airTime, durationMin: 70, isSpecial: false
            )
            return ScheduledEpisode(episode: episode, drama: drama, channel: slot.channel)
        }
    }
}
