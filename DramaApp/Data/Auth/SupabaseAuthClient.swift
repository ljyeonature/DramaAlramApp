import Foundation

/// Supabase GoTrue (Auth) REST 클라이언트 — 최소 기능만.
/// - Apple ID token 교환 (grant_type=id_token, provider=apple)
/// - refresh_token 으로 세션 갱신
/// - logout
/// PostgREST 와 base URL 은 같고 path 만 /auth/v1/ 로 다름.
struct AuthSession: Sendable, Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let expiresAt: Date

    var isExpired: Bool { expiresAt <= Date().addingTimeInterval(30) }
}

enum AuthError: Error, LocalizedError {
    case network(Error)
    case status(Int, String)
    case decoding(Error)
    case missingIdentityToken
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .network(let e): return "네트워크 오류: \(e.localizedDescription)"
        case .status(let code, let body):
            return "인증 서버 오류(\(code)): \(body.prefix(200))"
        case .decoding(let e): return "응답 파싱 실패: \(e.localizedDescription)"
        case .missingIdentityToken: return "Apple 로그인 응답에 identity token 이 없습니다."
        case .notSignedIn: return "로그인이 필요합니다."
        }
    }
}

final class SupabaseAuthClient: Sendable {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Apple 로그인 identity_token + nonce 를 Supabase 에 넘겨 세션 발급.
    /// nonce 는 Apple 인증 요청 시 raw(원본) 값을 보냈어야 하며, 여기선 그 raw 값을 전달.
    func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession {
        var request = try makeRequest(path: "token", query: [URLQueryItem(name: "grant_type", value: "id_token")])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "provider": "apple",
            "id_token": identityToken,
            "nonce": nonce,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    /// PKCE 코드 교환 — OAuth 로그인 (Google 등) 완료 후 콜백으로 받은 `code` 를
    /// `code_verifier` 와 함께 보내 세션 발급. Supabase 는 grant_type=pkce 지원.
    func exchangePKCE(code: String, codeVerifier: String) async throws -> AuthSession {
        var request = try makeRequest(path: "token", query: [URLQueryItem(name: "grant_type", value: "pkce")])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "auth_code": code,
            "code_verifier": codeVerifier,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    /// refresh token 으로 access token 재발급. 만료 임박 시 호출.
    func refresh(refreshToken: String) async throws -> AuthSession {
        var request = try makeRequest(path: "token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    /// 서버 세션 무효화. 실패해도 로컬 세션은 어차피 지울 것이라 조용히.
    func logout(accessToken: String) async {
        guard var request = try? makeRequest(path: "logout", query: []) else { return }
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    // MARK: - Internals

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        var comps = URLComponents()
        let base = baseURL.appendingPathComponent("auth/v1").appendingPathComponent(path)
        comps.scheme = base.scheme
        comps.host = base.host
        comps.port = base.port
        comps.path = base.path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else {
            throw AuthError.status(-1, "invalid URL")
        }
        var req = URLRequest(url: url)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return req
    }

    private func perform(_ request: URLRequest) async throws -> AuthSession {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.status(-1, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.status(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            let raw = try JSONDecoder().decode(TokenResponse.self, from: data)
            return AuthSession(
                accessToken: raw.access_token,
                refreshToken: raw.refresh_token,
                userId: raw.user.id,
                expiresAt: Date().addingTimeInterval(TimeInterval(raw.expires_in))
            )
        } catch {
            throw AuthError.decoding(error)
        }
    }

    // GoTrue 응답 매핑. 필드명은 API 스펙 그대로(snake_case).
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let user: UserPayload
        struct UserPayload: Decodable { let id: String }
    }
}
