import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            ScheduleView()
                .tabItem { Label("편성표", systemImage: "calendar") }

            FavoritesView()
                .tabItem { Label("즐겨찾기", systemImage: "heart.fill") }

            SearchView()
                .tabItem { Label("검색", systemImage: "magnifyingglass") }

            CommunityView()
                .tabItem { Label("커뮤니티", systemImage: "bubble.left.and.bubble.right") }

            ProfileView()
                .tabItem { Label("마이", systemImage: "person.crop.circle") }
        }
        // 앱 부팅 시 세션이 살아있으면 서버와 즐겨찾기 재정합 + 알림 재예약.
        .task {
            await deps.favoritesService.syncFromServer(in: modelContext)
            await reconcileNotifications()
        }
        // 로그인 → 서버와 병합. 로그아웃 → 계정 소유 즐겨찾기 로컬에서 제거 (게스트 origin 은 보존).
        .onChange(of: deps.authStore.isSignedIn) { _, isNowSignedIn in
            if isNowSignedIn {
                Task {
                    await deps.favoritesService.syncFromServer(in: modelContext)
                    await reconcileNotifications()
                }
            } else {
                deps.favoritesService.clearOwnedFavorites(in: modelContext)
                Task { await reconcileNotifications() }
            }
        }
    }

    private func reconcileNotifications() async {
        let favorites = (try? modelContext.fetch(FetchDescriptor<FavoriteDrama>())) ?? []
        await deps.notificationScheduler.reconcile(favorites: favorites)
    }
}

#Preview {
    RootView()
        .environment(AppDependencies())
        .modelContainer(for: FavoriteDrama.self, inMemory: true)
}
