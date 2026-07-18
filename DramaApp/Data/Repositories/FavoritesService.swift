import Foundation
import SwiftData

/// 즐겨찾기 로컬(SwiftData) + 서버(Supabase) 이중 저장 파사드.
/// - 로컬은 항상 SOT. UI(@Query FavoriteDrama) 가 즉시 반영.
/// - 로그인 상태면 서버에도 mirror. 서버 실패는 UX 를 막지 않음 (재시도는 다음 sync 에서).
/// - syncFromServer 는 로그인 직후·앱 시작 시 호출: 로컬↔서버 양방향 병합.
@MainActor
final class FavoritesService {
    private let http: SupabaseHTTPClient
    private let authStore: AuthStore

    init(http: SupabaseHTTPClient, authStore: AuthStore) {
        self.http = http
        self.authStore = authStore
    }

    // MARK: - 조회 헬퍼

    func isFavorite(dramaId: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<FavoriteDrama>(
            predicate: #Predicate { $0.dramaId == dramaId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first) != nil
    }

    // MARK: - 토글

    /// 스케줄/상세/즐겨찾기 뷰에서 공용 진입점.
    func setFavorite(_ isFav: Bool, drama: Drama, in context: ModelContext) async {
        if isFav {
            addLocal(drama, in: context)
        } else {
            removeLocal(dramaId: drama.id, in: context)
        }
        try? context.save()

        guard authStore.isSignedIn else { return }
        do {
            try await mirrorRemote(isFav: isFav, dramaId: drama.id)
        } catch {
            // 로컬은 이미 반영. 다음 syncFromServer 호출 때 재정합 될 것.
            print("[FavoritesService] remote mirror 실패 — \(error)")
        }
    }

    // MARK: - 로컬 CRUD

    private func addLocal(_ drama: Drama, in context: ModelContext) {
        // 중복 방지: 이미 있으면 no-op (기존 ownerUserId 유지 — 게스트 origin 보존 목적).
        if isFavorite(dramaId: drama.id, in: context) { return }
        context.insert(FavoriteDrama(drama: drama, ownerUserId: authStore.session?.userId))
    }

    private func removeLocal(dramaId: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<FavoriteDrama>(
            predicate: #Predicate { $0.dramaId == dramaId }
        )
        if let target = try? context.fetch(descriptor).first {
            context.delete(target)
        }
    }

    // MARK: - 원격 mirror

    private func mirrorRemote(isFav: Bool, dramaId: UUID) async throws {
        guard let userIdString = authStore.session?.userId,
              let userId = UUID(uuidString: userIdString) else { return }
        if isFav {
            let payload = FavoriteInsert(user_id: userId, drama_id: dramaId)
            try await http.post(
                "favorites",
                body: [payload],
                prefer: "resolution=merge-duplicates,return=minimal"
            )
        } else {
            try await http.delete(
                "favorites",
                queryItems: [
                    URLQueryItem(name: "user_id",
                                 value: "eq.\(userId.uuidString.lowercased())"),
                    URLQueryItem(name: "drama_id",
                                 value: "eq.\(dramaId.uuidString.lowercased())"),
                ]
            )
        }
    }

    // MARK: - 양방향 동기화

    /// 로그인 직후 / 앱 부팅 시 호출.
    /// 1) 서버에서 favorites 를 embed 된 drama 와 함께 fetch
    /// 2) 로컬 → 서버 : 로컬에만 있는 항목을 batch upsert
    /// 3) 서버 → 로컬 : 서버에만 있는 항목을 SwiftData 에 insert
    func syncFromServer(in context: ModelContext) async {
        guard authStore.isSignedIn,
              let userIdString = authStore.session?.userId,
              let userId = UUID(uuidString: userIdString) else { return }
        do {
            let serverRows: [ServerFavoriteRow] = try await http.get(
                "favorites",
                queryItems: [
                    URLQueryItem(
                        name: "select",
                        value: "drama_id,drama:dramas(*,channel:channels!channel_id(*))"
                    ),
                    URLQueryItem(name: "user_id",
                                 value: "eq.\(userId.uuidString.lowercased())"),
                ]
            )
            let serverIds = Set(serverRows.map(\.dramaId))

            let localFavorites = (try? context.fetch(FetchDescriptor<FavoriteDrama>())) ?? []
            let localIds = Set(localFavorites.map(\.dramaId))

            // 2) 로컬 → 서버
            let uploadTargets = localFavorites.filter { !serverIds.contains($0.dramaId) }
            if !uploadTargets.isEmpty {
                let payloads = uploadTargets.map {
                    FavoriteInsert(user_id: userId, drama_id: $0.dramaId)
                }
                try await http.post(
                    "favorites",
                    body: payloads,
                    prefer: "resolution=merge-duplicates,return=minimal"
                )
            }

            // 3) 서버 → 로컬 (계정 소유로 마킹)
            for row in serverRows where !localIds.contains(row.dramaId) {
                if let d = row.drama?.toDrama() {
                    context.insert(FavoriteDrama(drama: d, ownerUserId: userIdString))
                }
            }
            try? context.save()
        } catch {
            print("[FavoritesService] syncFromServer 실패 — \(error)")
        }
    }

    /// 로그아웃 시 호출 — 계정 소유(ownerUserId != nil) 즐겨찾기만 로컬에서 제거.
    /// 게스트 상태(nil owner)에서 추가한 항목은 보존.
    func clearOwnedFavorites(in context: ModelContext) {
        let descriptor = FetchDescriptor<FavoriteDrama>(
            predicate: #Predicate { $0.ownerUserId != nil }
        )
        guard let owned = try? context.fetch(descriptor) else { return }
        for fav in owned { context.delete(fav) }
        try? context.save()
    }
}

// MARK: - Wire DTOs

private struct FavoriteInsert: Encodable {
    let user_id: UUID
    let drama_id: UUID
}

/// `/rest/v1/favorites?select=drama_id,drama:dramas(*,channel:channels!channel_id(*))`
private struct ServerFavoriteRow: Decodable {
    let dramaId: UUID
    let drama: DramaEmbed?

    enum CodingKeys: String, CodingKey {
        case dramaId = "drama_id"
        case drama
    }
}

private struct DramaEmbed: Decodable {
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

    func toDrama() -> Drama {
        Drama(
            id: id, title: title, titleEn: titleEn, synopsis: synopsis,
            posterURL: posterURL, channelId: channelId, status: status,
            totalEpisodes: totalEpisodes, startDate: startDate, endDate: endDate,
            tmdbId: tmdbId
        )
    }
}
