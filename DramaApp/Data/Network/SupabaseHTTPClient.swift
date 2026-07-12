import Foundation

/// Supabase PostgREST 호출용 얇은 HTTP 클라이언트.
/// - apikey 헤더는 항상 anon 키(공개용) 사용.
/// - Authorization 헤더는 tokenProvider 가 주는 토큰. 로그인 상태면 유저 access_token, 아니면 anon.
///   → RLS 정책이 auth.uid() 기반이라 유저 토큰이 없으면 favorites 등 개인 데이터는 접근 불가.
final class SupabaseHTTPClient: Sendable {
    typealias TokenProvider = @Sendable () async -> String

    private let baseURL: URL
    private let apiKey: String
    private let tokenProvider: TokenProvider
    private let session: URLSession

    init(
        baseURL: URL,
        apiKey: String,
        tokenProvider: @escaping TokenProvider,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - GET

    func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        as type: T.Type = T.self
    ) async throws -> T {
        let request = try await makeRequest(method: "GET", path: path, queryItems: queryItems, body: nil, prefer: nil)
        let (data, http) = try await execute(request)
        try validate(http: http, data: data)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: - POST (upsert / insert)

    /// on_conflict 파라미터가 있으면 UPSERT 로 동작. Prefer 헤더로 resolution 지정.
    func post<Body: Encodable>(
        _ path: String,
        body: Body,
        queryItems: [URLQueryItem] = [],
        prefer: String = "return=minimal"
    ) async throws {
        let request = try await makeRequest(
            method: "POST", path: path, queryItems: queryItems,
            body: try Self.encoder.encode(body), prefer: prefer
        )
        let (data, http) = try await execute(request)
        try validate(http: http, data: data)
    }

    // MARK: - DELETE

    func delete(_ path: String, queryItems: [URLQueryItem]) async throws {
        let request = try await makeRequest(
            method: "DELETE", path: path, queryItems: queryItems, body: nil, prefer: "return=minimal"
        )
        let (data, http) = try await execute(request)
        try validate(http: http, data: data)
    }

    // MARK: - 공통

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Data?,
        prefer: String?
    ) async throws -> URLRequest {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        let token = await tokenProvider()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = body }
        // 캐시 우회 — 크롤러 반영 즉시 확인 가능하도록.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpStatus(code: -1, body: "no response")
        }
        return (data, http)
    }

    private func validate(http: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(code: http.statusCode, body: body)
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var comps = URLComponents()
        let rest = baseURL.appendingPathComponent("rest/v1").appendingPathComponent(path)
        comps.scheme = rest.scheme
        comps.host = rest.host
        comps.port = rest.port
        comps.path = rest.path
        if !queryItems.isEmpty {
            comps.queryItems = queryItems
        }
        guard let url = comps.url else { throw APIError.invalidURL }
        return url
    }

    // MARK: - 코덱

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if str.count == 10, let date = SupabaseHTTPClient.dateOnlyFormatter.date(from: str) {
                return date
            }
            if let date = SupabaseHTTPClient.isoFractional.date(from: str) {
                return date
            }
            if let date = SupabaseHTTPClient.isoBasic.date(from: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(str)"
            )
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Supabase 컬럼은 snake_case — 각 요청 페이로드가 CodingKeys 로 매핑되므로 강제 변환은 안 함.
        // ISO8601 (fractional 포함) 로 통일.
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SupabaseHTTPClient.isoFractional.string(from: date))
        }
        return e
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
