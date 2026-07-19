import Foundation
import UserNotifications
import SwiftData

/// 로컬 알림 (`UNUserNotificationCenter`) 스케줄러.
/// - 즐겨찾기한 드라마의 예정 에피소드에 대해 방영 `airTime - lead` 시점 알림 예약.
/// - APNs 원격 푸시 없음 — 유료 Apple Developer 없이 동작.
/// - iOS pending notification cap (64) 대응: 다가올 `scheduleWindow` 내 에피소드만 예약.
@MainActor
final class NotificationScheduler {
    private let center: UNUserNotificationCenter
    private let repository: any DramaRepository

    /// 방영 몇 분 전 알림 발송할지.
    static let leadMinutes: Int = 10
    /// 앞으로 며칠치 에피소드까지 예약해 둘지.
    static let scheduleWindowDays: Int = 7

    init(repository: any DramaRepository, center: UNUserNotificationCenter = .current()) {
        self.repository = repository
        self.center = center
    }

    // MARK: - Authorization

    /// 현재 알림 권한 상태.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 권한 요청. 이미 결정된 상태면 그대로 반환.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[NotificationScheduler] 권한 요청 실패 — \(error)")
            return false
        }
    }

    // MARK: - Scheduling

    /// 단일 드라마의 예정 에피소드에 대해 알림 예약.
    /// 기존에 예약된 이 드라마의 알림은 먼저 제거하고 재예약 (idempotent).
    func schedule(for favorite: FavoriteDrama) async {
        guard favorite.notifyAir else {
            cancelAll(for: favorite.dramaId)
            return
        }
        guard await isAuthorized() else { return }

        let from = Date()
        let until = Calendar.current.date(
            byAdding: .day, value: Self.scheduleWindowDays, to: from
        ) ?? from.addingTimeInterval(TimeInterval(Self.scheduleWindowDays * 86400))

        let episodes: [Episode]
        do {
            episodes = try await repository.upcomingEpisodes(
                dramaId: favorite.dramaId, from: from, until: until
            )
        } catch {
            print("[NotificationScheduler] upcoming fetch 실패 (\(favorite.title)) — \(error)")
            return
        }

        cancelAll(for: favorite.dramaId)
        for episode in episodes {
            scheduleOne(favorite: favorite, episode: episode)
        }
    }

    /// 여러 즐겨찾기 일괄 재정합. 앱 시작 / 로그인 시 호출.
    func reconcile(favorites: [FavoriteDrama]) async {
        guard await isAuthorized() else { return }
        for fav in favorites {
            await schedule(for: fav)
        }
    }

    /// 특정 드라마의 모든 예약 취소 — 즐겨찾기 해제 / 토글 off 시.
    func cancelAll(for dramaId: UUID) {
        Task {
            let requests = await center.pendingNotificationRequests()
            let ids = requests
                .filter { $0.identifier.hasPrefix(Self.identifierPrefix(dramaId: dramaId)) }
                .map(\.identifier)
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Private

    private func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional
    }

    private func scheduleOne(favorite: FavoriteDrama, episode: Episode) {
        let triggerDate = episode.airTime.addingTimeInterval(TimeInterval(-Self.leadMinutes * 60))
        // 이미 지난 시간이면 스킵.
        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = favorite.title
        content.body = "\(episode.number)회 방영 \(Self.leadMinutes)분 전입니다."
        content.sound = .default
        content.userInfo = [
            "drama_id": favorite.dramaId.uuidString,
            "episode_id": episode.id.uuidString,
        ]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier(dramaId: favorite.dramaId, episodeId: episode.id),
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error {
                print("[NotificationScheduler] add 실패 — \(error)")
            }
        }
    }

    // MARK: - Debug helpers

    /// 예약된 알림 요약 로그 — Xcode 콘솔에서 확인.
    func dumpPending() async {
        let requests = await center.pendingNotificationRequests()
        print("[NotificationScheduler] pending=\(requests.count)")
        for r in requests {
            let trig = (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            print("  · \(r.identifier) → \(trig?.description ?? "?")  \"\(r.content.body)\"")
        }
    }

    /// 방출 확인용 — 지금 시각 + `after` 초 뒤 즉시 로컬 알림 하나 발송.
    func fireTest(after seconds: TimeInterval = 5) async {
        guard await isAuthorized() else {
            print("[NotificationScheduler] 테스트 실패 — 권한 없음")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "테스트 알림"
        content.body = "\(Int(seconds))초 뒤 도착한 로컬 알림입니다."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "debug-test-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - Identifier helpers

    /// `"drama-{uuid}-ep-{uuid}"` — 드라마 단위 취소 시 prefix 매칭.
    private static func identifier(dramaId: UUID, episodeId: UUID) -> String {
        "\(identifierPrefix(dramaId: dramaId))\(episodeId.uuidString)"
    }

    private static func identifierPrefix(dramaId: UUID) -> String {
        "drama-\(dramaId.uuidString)-ep-"
    }
}
