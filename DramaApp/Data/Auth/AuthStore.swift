import Foundation
import CryptoKit
import Security
import AuthenticationServices

/// 로그인 세션의 앱 전역 상태.
/// - 앱 시작 시 Keychain 에서 복원, 만료면 refresh 시도.
/// - SwiftUI `SignInWithAppleButton` 에서 얻은 identityToken + raw nonce 를 넘겨 세션 완성.
/// - SupabaseHTTPClient 가 매 요청 직전 `currentAuthorizationToken()` 을 조회.
@Observable
@MainActor
final class AuthStore {
    private(set) var session: AuthSession?
    private(set) var isProcessing: Bool = false
    private(set) var lastError: String?

    private let client: SupabaseAuthClient
    private let anonKey: String
    private let baseURL: URL
    private let redirectURL: String
    private let callbackScheme: String

    init(
        client: SupabaseAuthClient,
        anonKey: String,
        baseURL: URL,
        redirectURL: String,
        callbackScheme: String
    ) {
        self.client = client
        self.anonKey = anonKey
        self.baseURL = baseURL
        self.redirectURL = redirectURL
        self.callbackScheme = callbackScheme
        restore()
    }

    var isSignedIn: Bool { session != nil }

    /// SupabaseHTTPClient 가 매 요청마다 호출.
    /// 로그인 상태면 유저 access_token, 아니면 anon key. 어느 쪽이든 apikey 헤더와 별개로 Authorization Bearer.
    func currentAuthorizationToken() -> String {
        session?.accessToken ?? anonKey
    }

    // MARK: - Google 로그인 (PKCE + ASWebAuthenticationSession)

    /// Google 로그인 시작 → 브라우저 시트 → 콜백 code → 세션 교환까지 한 번에.
    /// presentationAnchor: SwiftUI 에서는 UIApplication.shared.connectedScenes 로부터 얻은 UIWindow.
    @discardableResult
    func signInWithGoogle(presentationAnchor: ASPresentationAnchor?) async throws -> AuthSession {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let flow = try OAuthFlow.prepare(
                provider: "google",
                baseURL: baseURL,
                redirectURL: redirectURL
            )
            let orchestrator = OAuthFlow()
            let callback = try await orchestrator.run(
                flow: flow,
                callbackScheme: callbackScheme,
                presentationAnchor: presentationAnchor
            )
            let session = try await client.exchangePKCE(
                code: callback.code,
                codeVerifier: callback.codeVerifier
            )
            persist(session)
            self.lastError = nil
            return session
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            throw error
        }
    }

    // MARK: - Apple 로그인 완결 (미사용 · 유료 개발자 멤버십 확보 시 재활성화)

    /// SignInWithAppleButton 콜백에서 얻은 identity token + raw nonce 로 Supabase 세션 발급.
    /// - nonce: SignInWithAppleButton onRequest 에 넘긴 SHA256 이전 원본 문자열
    @discardableResult
    func finishAppleSignIn(idToken: String, rawNonce: String) async throws -> AuthSession {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let new = try await client.signInWithApple(identityToken: idToken, nonce: rawNonce)
            persist(new)
            self.lastError = nil
            return new
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            throw error
        }
    }

    // MARK: - 복원 / 재발급

    private func restore() {
        guard let access = KeychainStore.get(KeychainStore.Key.accessToken),
              let refresh = KeychainStore.get(KeychainStore.Key.refreshToken),
              let userId = KeychainStore.get(KeychainStore.Key.userId),
              let expStr = KeychainStore.get(KeychainStore.Key.expiresAt),
              let expInterval = TimeInterval(expStr) else {
            return
        }
        let restored = AuthSession(
            accessToken: access,
            refreshToken: refresh,
            userId: userId,
            expiresAt: Date(timeIntervalSince1970: expInterval)
        )
        self.session = restored
        if restored.isExpired {
            Task { await self.refreshIfNeeded() }
        }
    }

    func refreshIfNeeded() async {
        guard let current = session, current.isExpired else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let new = try await client.refresh(refreshToken: current.refreshToken)
            persist(new)
        } catch {
            clearLocal()
            self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: - 로그아웃

    func signOut() async {
        if let s = session { await client.logout(accessToken: s.accessToken) }
        clearLocal()
    }

    // MARK: - Nonce 생성 (View 에서 SignInWithAppleButton 에 넣기 위해)

    /// 로그인 요청 시 `request.nonce = sha256(rawNonce)` 로 넣고, 콜백 시 rawNonce 를 finishAppleSignIn 에 전달.
    static func makeNonce() -> (raw: String, hashed: String) {
        let raw = randomNonce(length: 32)
        return (raw, sha256(raw))
    }

    // MARK: - Private

    private func persist(_ new: AuthSession) {
        self.session = new
        KeychainStore.set(new.accessToken, for: KeychainStore.Key.accessToken)
        KeychainStore.set(new.refreshToken, for: KeychainStore.Key.refreshToken)
        KeychainStore.set(new.userId, for: KeychainStore.Key.userId)
        KeychainStore.set(String(new.expiresAt.timeIntervalSince1970), for: KeychainStore.Key.expiresAt)
    }

    private func clearLocal() {
        self.session = nil
        KeychainStore.remove(KeychainStore.Key.accessToken)
        KeychainStore.remove(KeychainStore.Key.refreshToken)
        KeychainStore.remove(KeychainStore.Key.userId)
        KeychainStore.remove(KeychainStore.Key.expiresAt)
    }

    // Apple nonce 규격: 알파벳/숫자/-._ , 최소 32자.
    private nonisolated static func randomNonce(length: Int) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        for byte in bytes {
            result.append(charset[Int(byte) % charset.count])
        }
        return result
    }

    private nonisolated static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
