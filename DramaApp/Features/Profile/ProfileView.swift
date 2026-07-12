import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @Environment(AppDependencies.self) private var deps

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                accountSection

                Section("알림") {
                    LabeledContent("방영 알림", value: "Week 6")
                }
                Section("정보") {
                    LabeledContent("버전", value: appVersion)
                }
            }
            .navigationTitle("마이")
            .alert("로그인 실패", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Account section

    @ViewBuilder
    private var accountSection: some View {
        Section("계정") {
            if let session = deps.authStore.session {
                LabeledContent("로그인", value: "Google")
                LabeledContent("유저 ID", value: shortId(session.userId))
                Button(role: .destructive) {
                    Task { await deps.authStore.signOut() }
                } label: {
                    Text("로그아웃")
                }
            } else {
                LabeledContent("로그인", value: "게스트")
                googleSignInButton
                Text("로그인 없이도 즐겨찾기는 기기에 저장됩니다.")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var googleSignInButton: some View {
        Button {
            Task { await triggerGoogleSignIn() }
        } label: {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.white)
                Text("Google 로 계속하기")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                if deps.authStore.isProcessing {
                    Spacer()
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, AppSpacing.md)
            .background(Color(red: 66/255, green: 133/255, blue: 244/255))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))
        }
        .disabled(deps.authStore.isProcessing)
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
    }

    private func triggerGoogleSignIn() async {
        do {
            _ = try await deps.authStore.signInWithGoogle(
                presentationAnchor: currentPresentationAnchor()
            )
        } catch OAuthFlow.OAuthError.userCancelled {
            // 취소는 조용히 무시.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// ASWebAuthenticationSession 을 띄우는 UIWindow. SwiftUI 에선 UIApplication scene 을 훑어서 찾음.
    private func currentPresentationAnchor() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
    }

    private func shortId(_ full: String) -> String {
        String(full.prefix(8)) + "…"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

#Preview {
    ProfileView()
        .environment(AppDependencies.preview())
}
