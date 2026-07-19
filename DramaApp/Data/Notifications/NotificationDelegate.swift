import Foundation
import UserNotifications

/// UNUserNotificationCenter 델리게이트.
/// - 포그라운드 도착 시 배너 표시 (기본은 억제됨).
/// - 앱 시작 시 `AppDelegateAdaptor` 에서 시스템에 등록.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 포그라운드에서도 배너/사운드/리스트에 노출. 뱃지는 아직 사용 안 함.
        completionHandler([.banner, .sound, .list])
    }
}
