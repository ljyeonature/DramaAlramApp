import SwiftUI

struct RootView: View {
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
    }
}

#Preview {
    RootView()
        .environment(AppDependencies())
}
