import Foundation

/// Supabase PostgREST 호출용 얇은 HTTP 클라이언트.
/// Auth 추가될 때(Week 5+) Bearer 토큰 주입 메서드만 늘면 됨.
final class SupabaseHTTPClient: Sendable {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// `/rest/v1/<path>?<queryItems>` 에 GET. JSON 디코드 결과 반환.
    func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        as type: T.Type = T.self
    ) async throws -> T {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // URLSession 기본 캐시 우회 — Supabase가 캐시 헤더를 안 주지만 안전망.
        // 크롤러 재실행 후 즉시 새 데이터가 반영되어야 UX 자연스러움.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpStatus(code: -1, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(code: http.statusCode, body: body)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
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

    /// PostgREST는 ISO 8601 타임스탬프(+TZ 또는 Z) 사용. 일부 date-only 컬럼도 있어 다단 시도.
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
