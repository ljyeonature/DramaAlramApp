import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("계정") {
                    LabeledContent("로그인", value: "게스트")
                    LabeledContent("닉네임", value: "—")
                }
                Section("알림") {
                    LabeledContent("방영 알림", value: "Week 6")
                }
                Section("정보") {
                    LabeledContent("버전", value: appVersion)
                }
            }
            .navigationTitle("마이")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

#Preview {
    ProfileView()
}
