import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case transport(any Error)
    case httpStatus(code: Int, body: String)
    case decoding(any Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "잘못된 URL"
        case .transport(let err): "통신 오류: \(err.localizedDescription)"
        case .httpStatus(let code, let body):
            "서버 오류 \(code): \(body.prefix(200))"
        case .decoding(let err): "응답 파싱 실패: \(err.localizedDescription)"
        }
    }
}
