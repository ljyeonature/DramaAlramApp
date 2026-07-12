import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// PKCE 기반 OAuth 로그인 오케스트레이션.
/// - Supabase `/auth/v1/authorize?provider=google` URL 을 ASWebAuthenticationSession 으로 열고,
///   콜백으로 돌아온 `code` 를 반환. code 를 verifier 와 함께 `/auth/v1/token?grant_type=pkce` 에
///   넣어 세션으로 교환하는 건 상위 계층(AuthStore) 책임.
/// - SDK 의존성 없이 Apple 표준 API 만 사용.
@MainActor
final class OAuthFlow: NSObject {
    struct StartedFlow {
        let authorizationURL: URL
        /// PKCE code_verifier — 서버 교환 시 반드시 함께 보내야 함.
        let codeVerifier: String
    }

    struct Result {
        let code: String
        let codeVerifier: String
    }

    enum OAuthError: LocalizedError {
        case invalidURL
        case userCancelled
        case sessionFailed(Error)
        case missingCode(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "OAuth URL 생성 실패."
            case .userCancelled: return "로그인이 취소되었습니다."
            case .sessionFailed(let e): return "웹 인증 실패: \(e.localizedDescription)"
            case .missingCode(let raw):
                return "콜백에서 인증 코드를 찾지 못했습니다. (\(raw))"
            }
        }
    }

    /// 프로바이더용 authorize URL + PKCE 재료 생성.
    /// - provider: "google", "kakao" 등 Supabase 프로바이더 코드.
    /// - baseURL / redirectURL: SupabaseConfig 값.
    static func prepare(
        provider: String,
        baseURL: URL,
        redirectURL: String
    ) throws -> StartedFlow {
        let verifier = makeCodeVerifier(length: 64)
        let challenge = codeChallenge(from: verifier)

        var comps = URLComponents()
        let authorize = baseURL
            .appendingPathComponent("auth/v1")
            .appendingPathComponent("authorize")
        comps.scheme = authorize.scheme
        comps.host = authorize.host
        comps.port = authorize.port
        comps.path = authorize.path
        comps.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        guard let url = comps.url else { throw OAuthError.invalidURL }
        return StartedFlow(authorizationURL: url, codeVerifier: verifier)
    }

    /// ASWebAuthenticationSession 을 띄우고 콜백에서 `code` 를 뽑아 반환.
    /// 사용자가 시트를 닫으면 userCancelled throw.
    func run(
        flow: StartedFlow,
        callbackScheme: String,
        presentationAnchor: ASPresentationAnchor?
    ) async throws -> Result {
        self.activeAnchor = presentationAnchor
        let code: String = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: flow.authorizationURL,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        cont.resume(throwing: OAuthError.userCancelled)
                    } else {
                        cont.resume(throwing: OAuthError.sessionFailed(error))
                    }
                    return
                }
                guard let callback,
                      let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                      let value = comps.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    cont.resume(throwing: OAuthError.missingCode(callback?.absoluteString ?? ""))
                    return
                }
                cont.resume(returning: value)
            }
            session.presentationContextProvider = self
            // 시뮬레이터/기기 공용 — 앱 내에서 브라우저 세션을 뜨게 (ephemeral 옵션은 SSO 방지).
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            session.start()
        }
        return Result(code: code, codeVerifier: flow.codeVerifier)
    }

    private var activeSession: ASWebAuthenticationSession?
    private var activeAnchor: ASPresentationAnchor?

    // MARK: - PKCE 유틸

    /// RFC 7636 code_verifier: 43~128자 [A-Z a-z 0-9 - . _ ~]
    private static func makeCodeVerifier(length: Int) -> String {
        precondition(length >= 43 && length <= 128)
        let charset: [Character] =
            Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// code_challenge = BASE64URL( SHA256( code_verifier ) )
    private static func codeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }
}

extension OAuthFlow: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            if let anchor = self.activeAnchor { return anchor }
            // 안전망 — ProfileView 가 항상 key window 를 넘기므로 이 분기는 이론상만 도달.
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            guard let scene else {
                fatalError("OAuth presentation anchor requested with no window scene")
            }
            return scene.windows.first ?? UIWindow(windowScene: scene)
        }
    }
}

private extension Data {
    /// base64url — padding 제거 + `+/` → `-_`. OAuth PKCE 표준.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
