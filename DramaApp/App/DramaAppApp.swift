import SwiftUI
import SwiftData
import UserNotifications

@main
struct DramaAppApp: App {
    @State private var dependencies = AppDependencies()

    init() {
        // 포그라운드에서도 알림 배너 노출 위해 델리게이트 등록.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
        .modelContainer(for: FavoriteDrama.self)
    }
}
