import SwiftUI

struct CommunityView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "커뮤니티 준비중",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("v2.0에서 오픈 예정 (Month 3)")
            )
            .navigationTitle("커뮤니티")
        }
    }
}

#Preview {
    CommunityView()
}
