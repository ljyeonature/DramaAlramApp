# Week 1 Setup Checklist

이 주차의 작업은 두 트랙으로 나뉩니다.

- **트랙 A (사용자)**: 외부 계정 가입 (Supabase, TMDB) — 30분
- **트랙 B (코드)**: iOS 프로젝트 SwiftUI 전환 — 이미 완료

---

## 트랙 A — 사용자가 할 일

### A-1. Supabase 프로젝트 생성

1. https://supabase.com 회원가입 (GitHub 로그인 추천)
2. **New Project** 클릭
   - **Name**: `dramaapp` (자유)
   - **Database Password**: 강한 비밀번호 (1Password에 저장)
   - **Region**: **`Northeast Asia (Seoul)`** ← 반드시 Seoul
   - **Plan**: Free (월 0달러로 시작)
3. 프로젝트 생성까지 약 2분 대기
4. 생성 완료 후 **Project Settings → API**에서 다음 두 값을 메모:
   - `Project URL` (예: `https://abcdefgh.supabase.co`)
   - `anon public` key (eyJ로 시작하는 긴 문자열)

> 이 두 값은 Week 2~3에서 iOS 앱에 주입합니다. 지금은 메모만.

### A-2. DB 스키마 적용

1. Supabase 대시보드 → 좌측 **SQL Editor** → **New query**
2. 다음 파일을 순서대로 붙여넣기 → **Run** (⌘+Enter)
   1. `supabase/schema.sql` — 12개 테이블 + 인덱스 + 트리거
   2. `supabase/seed.sql` — 채널 5개 시드
   3. `supabase/policies.sql` — RLS 정책
3. 좌측 **Table Editor**에서 `channels`에 5개 행이 들어왔는지 확인

### A-3. TMDB API 키 발급

1. https://www.themoviedb.org 회원가입
2. 이메일 인증
3. **Settings → API → Create** → "Developer"
4. 신청서 양식:
   - **Application Name**: DramaApp
   - **Application URL**: 일단 `https://github.com/your-id/dramaapp` 같은 placeholder
   - **Summary**: 한국 드라마 편성표 iOS 앱. 드라마 메타데이터(포스터, 시놉시스, 출연진) 조회용.
5. 약관 동의 → 즉시 발급
6. **API Read Access Token** (Bearer 토큰) 메모

> v3 API key가 아니라 **v4 Read Access Token**을 쓰세요. 신형이고 권한 관리가 쉽습니다.

### A-4. 키 보관

`.env.local` 같은 파일을 만들지 마세요. iOS 앱에 직접 박을 거라 환경변수 관리는 Week 3에 시작합니다. 지금은 **1Password 또는 Notion 비공개 페이지**에:

```
SUPABASE_URL=https://abcdefgh.supabase.co
SUPABASE_ANON_KEY=eyJ...
TMDB_BEARER_TOKEN=eyJ...
```

---

## 트랙 B — 이미 완료된 코드 작업

### B-1. UIKit → SwiftUI 라이프사이클 전환

- 삭제: `AppDelegate.swift`, `SceneDelegate.swift`, `ViewController.swift`, `Main.storyboard`
- 신규: `App/DramaAppApp.swift` (`@main`), `App/RootView.swift` (TabView 5개)
- `Info.plist`에서 `UIApplicationSceneManifest` 제거
- `project.pbxproj`에서 `INFOPLIST_KEY_UIMainStoryboardFile` 제거
- `LaunchScreen.storyboard`는 유지 (런치 스크린은 그대로 사용)

### B-2. 폴더 구조

```
DramaApp/
├── App/                  # 진입점, DI
├── Features/             # 5개 탭 (Schedule/Favorites/Search/Community/Profile)
├── Domain/Models/        # Drama, Episode, Channel
├── Data/Repositories/    # DramaRepository (프로토콜) + MockDramaRepository
├── DesignSystem/         # AppColors, AppTypography, AppSpacing
├── Base.lproj/           # LaunchScreen.storyboard
└── Assets.xcassets/
```

### B-3. DesignSystem 토큰

- `AppColors` — accent, liveBadge, cardBackground, separator
- `AppTypography` — title, body, caption, timeMono, badge
- `AppSpacing` / `AppCornerRadius` — xs / sm / md / lg / xl

### B-4. Mock Repository

`MockDramaRepository`가 샘플 드라마 3개와 가짜 편성표를 반환합니다. **Supabase가 없어도 앱이 실행되고 ScheduleView에서 편성표를 볼 수 있습니다.** Week 3에서 `SupabaseDramaRepository`로 갈아끼웁니다.

---

## 검증

```sh
# 빌드 확인
xcodebuild -project DramaApp.xcodeproj -scheme DramaApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# 시뮬레이터에서 실행
open -a Simulator
# 또는 Xcode에서 ⌘R
```

5개 탭이 보이고, **편성표 탭에서 샘플 드라마 3개가 시간순으로 표시**되면 Week 1 완료입니다.

---

## Week 2 진입 조건

- [ ] Supabase 프로젝트 URL + anon key 확보
- [ ] 스키마 + 시드 + RLS 적용 (`channels` 테이블에 5개 행 보임)
- [ ] TMDB Bearer token 확보
- [ ] 시뮬레이터에서 앱 실행 + 5개 탭 동작 확인

위 4개가 모두 완료되면 **Week 2: KBS 크롤러 작성**으로 넘어갑니다.
