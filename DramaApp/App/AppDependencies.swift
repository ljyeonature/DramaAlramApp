import Foundation

/// 앱 전역 의존성 컨테이너.
/// - Supabase 가 설정돼 있으면 실서버, 아니면 Mock 폴백.
/// - AuthStore / FavoritesService 는 로그인 유무와 무관하게 항상 준비 (로그인 UI 를 노출해야 하므로).
@Observable
@MainActor
final class AppDependencies {
    let dramaRepository: any DramaRepository
    let authStore: AuthStore
    let favoritesService: FavoritesService
    let notificationScheduler: NotificationScheduler

    init() {
        if SupabaseConfig.isConfigured, let url = SupabaseConfig.baseURL {
            let anonKey = SupabaseConfig.anonKey
            let authClient = SupabaseAuthClient(baseURL: url, anonKey: anonKey)
            let store = AuthStore(
                client: authClient,
                anonKey: anonKey,
                baseURL: url,
                redirectURL: SupabaseConfig.oauthRedirectURL,
                callbackScheme: SupabaseConfig.oauthCallbackScheme
            )
            self.authStore = store

            // tokenProvider 는 매 요청 직전에 최신 토큰을 조회 → 로그인/로그아웃 시 즉시 반영.
            let http = SupabaseHTTPClient(
                baseURL: url,
                apiKey: anonKey,
                tokenProvider: { [weak store] in
                    guard let store else { return anonKey }
                    return await store.currentAuthorizationToken()
                }
            )
            let repo = SupabaseDramaRepository(http: http)
            self.dramaRepository = repo
            let scheduler = NotificationScheduler(repository: repo)
            self.notificationScheduler = scheduler
            self.favoritesService = FavoritesService(
                http: http, authStore: store, notificationScheduler: scheduler
            )
            print("[AppDependencies] Supabase 활성 — \(url.host ?? "?")")
        } else {
            // Mock 모드: 로그인/서버 mirror 는 no-op 이지만 인터페이스는 그대로 노출.
            let dummyURL = URL(string: "https://example.invalid")!
            let authClient = SupabaseAuthClient(baseURL: dummyURL, anonKey: "")
            let store = AuthStore(
                client: authClient, anonKey: "",
                baseURL: dummyURL, redirectURL: "", callbackScheme: ""
            )
            let http = SupabaseHTTPClient(baseURL: dummyURL, apiKey: "", tokenProvider: { "" })
            self.authStore = store
            let repo = MockDramaRepository()
            self.dramaRepository = repo
            let scheduler = NotificationScheduler(repository: repo)
            self.notificationScheduler = scheduler
            self.favoritesService = FavoritesService(
                http: http, authStore: store, notificationScheduler: scheduler
            )
            print("[AppDependencies] ⚠ SupabaseConfig 미설정 — Mock 모드")
        }
    }

    /// 테스트/프리뷰용 명시적 주입.
    init(
        dramaRepository: any DramaRepository,
        authStore: AuthStore,
        favoritesService: FavoritesService,
        notificationScheduler: NotificationScheduler
    ) {
        self.dramaRepository = dramaRepository
        self.authStore = authStore
        self.favoritesService = favoritesService
        self.notificationScheduler = notificationScheduler
    }

    /// SwiftUI Preview 전용. 실서버 접근 없이 즉시 렌더 가능.
    /// nil 이면 MockDramaRepository — 기본 파라미터로 두면 caller isolation 이슈가 있어 nil 판정으로 처리.
    @MainActor
    static func preview(repository: (any DramaRepository)? = nil) -> AppDependencies {
        let repo = repository ?? MockDramaRepository()
        let dummyURL = URL(string: "https://example.invalid")!
        let authClient = SupabaseAuthClient(baseURL: dummyURL, anonKey: "")
        let store = AuthStore(
            client: authClient, anonKey: "",
            baseURL: dummyURL, redirectURL: "", callbackScheme: ""
        )
        let http = SupabaseHTTPClient(baseURL: dummyURL, apiKey: "", tokenProvider: { "" })
        let scheduler = NotificationScheduler(repository: repo)
        let service = FavoritesService(
            http: http, authStore: store, notificationScheduler: scheduler
        )
        return AppDependencies(
            dramaRepository: repo,
            authStore: store,
            favoritesService: service,
            notificationScheduler: scheduler
        )
    }
}
