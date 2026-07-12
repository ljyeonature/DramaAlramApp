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
        // 앱 부팅 시 세션이 살아있으면 서버와 즐겨찾기 재정합.
        .task { await deps.favoritesService.syncFromServer(in: modelContext) }
        // 로그인/로그아웃 시 트리거 — 로그인 직후 로컬 → 서버 업로드 + 서버 → 로컬 다운로드.
        .onChange(of: deps.authStore.isSignedIn) { _, _ in
            Task { await deps.favoritesService.syncFromServer(in: modelContext) }
        }
    }
}

#Preview {
    RootView()
        .environment(AppDependencies())
        .modelContainer(for: FavoriteDrama.self, inMemory: true)
}
