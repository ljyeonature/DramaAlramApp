import Foundation

@Observable
final class AppDependencies {
    let dramaRepository: any DramaRepository

    /// SupabaseConfig가 채워져 있으면 Supabase, 아니면 Mock으로 폴백.
    /// 개발 초기/플레이스홀더 상태에서도 앱이 죽지 않게 한다.
    init() {
        if SupabaseConfig.isConfigured, let url = SupabaseConfig.baseURL {
            let client = SupabaseHTTPClient(baseURL: url, anonKey: SupabaseConfig.anonKey)
            self.dramaRepository = SupabaseDramaRepository(http: client)
            print("[AppDependencies] Supabase repository active — \(url.host ?? "?")")
        } else {
            self.dramaRepository = MockDramaRepository()
            print("[AppDependencies] ⚠ SupabaseConfig 미설정 — Mock 데이터로 동작 중")
        }
    }

    /// 테스트/프리뷰용 명시적 주입.
    init(repository: any DramaRepository) {
        self.dramaRepository = repository
    }
}
