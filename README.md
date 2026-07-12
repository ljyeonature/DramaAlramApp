# DramaApp

한국 드라마 편성표 · 알림 · 즐겨찾기 iOS 앱. 1인 개발 MVP.

방영 시작 시간을 놓치지 않게 알려주고, 즐겨찾기한 드라마의 새 회차를 추적하고,
현재 어떤 OTT 에서 다시 볼 수 있는지 확인하는 걸 목표로 합니다.

---

## 아키텍처 개요

```
┌────────────────────────┐       ┌──────────────────────────┐
│      iOS App           │       │   Supabase (BaaS)        │
│  SwiftUI + MVVM        │ HTTPS │  Postgres · Auth · RLS   │
│  Swift Concurrency     │◀─────▶│  Storage · Edge Functions│
│  SwiftData (즐겨찾기)  │       │  Seoul ap-northeast-2    │
└────────────────────────┘       └────────────┬─────────────┘
                                              ▲
                                              │ service_role
                                              │ (RLS 우회)
                                 ┌────────────┴─────────────┐
                                 │  Crawler (Node/TS)       │
                                 │  · TMDB → 스키마 매핑    │
                                 │  · dramas / episodes /   │
                                 │    persons / drama_casts │
                                 │    / drama_availability  │
                                 └────────────┬─────────────┘
                                              ▲
                                              │
                                 ┌────────────┴─────────────┐
                                 │  GitHub Actions cron     │
                                 │  · 매일 KST 03:00 delta  │
                                 │  · 매주 일요일 04:00 full│
                                 └──────────────────────────┘
```

**핵심 원칙**

- **MVP는 갈아엎을 수 있게, 코어 도메인은 깨지지 않게** —
  백엔드/크롤러는 추상화(Repository 프로토콜)로 끊어두지만
  `Drama`/`Episode`/`Channel` 도메인 모델은 처음부터 제대로 잡음.
- **혼자 운영 가능한 만큼만 기능을 연다** —
  커뮤니티/실시간 채팅은 신고·어뷰징 대응 인력 필요. 단계적으로 오픈.

전체 설계 문서는 [`DramaApp_Architecture.pdf`](./DramaApp_Architecture.pdf) 참조.

---

## 기술 스택

| 레이어 | 선택 | 이유 |
|---|---|---|
| iOS UI | SwiftUI (iOS 26.2+) | 모던, `@Observable`/`@Query` 반응형 |
| 상태 관리 | MVVM + Repository | 1인 개발엔 TCA 오버헤드 큼 |
| 로컬 저장 | SwiftData | 즐겨찾기, 오프라인 캐시 |
| HTTP | URLSession (얇게 감쌈) | 의존성 최소화, supabase-swift 미사용 |
| 백엔드 | Supabase (Postgres) | RLS 로 백엔드 코드 거의 0, Postgres 표준 → 벤더 락인 낮음 |
| 크롤러 | Node 22 + TypeScript + `@supabase/supabase-js` | TMDB API 처리에 적합, 재사용 라이브러리 풍부 |
| 데이터 소스 | [TMDB](https://www.themoviedb.org) | 무료, 안정적, 한국어 로케일 지원, 포스터 CDN 제공 |
| 자동화 | GitHub Actions cron | 별도 서버 불필요, 월 $0 |

---

## 저장소 구조

```
DramaApp/
├── DramaApp/                          # iOS 앱 소스
│   ├── App/                           # 진입점, DI 컨테이너
│   ├── Features/                      # 화면별 (Feature-first)
│   │   ├── Schedule/                  # 편성표 (탭 홈)
│   │   ├── Favorites/                 # 즐겨찾기 (SwiftData)
│   │   ├── Search/                    # 제목 · 배우 통합 검색
│   │   ├── DramaDetail/               # 상세 (시놉시스/출연/OTT)
│   │   ├── Community/                 # placeholder (Week 6+)
│   │   └── Profile/                   # placeholder
│   ├── Domain/Models/                 # Drama, Episode, Channel, Person, CastMember
│   ├── Data/
│   │   ├── Repositories/              # DramaRepository + FavoritesService (로컬↔서버)
│   │   ├── Auth/                      # AuthStore, SupabaseAuthClient, OAuthFlow, Keychain
│   │   ├── Network/                   # SupabaseHTTPClient, SupabaseConfig
│   │   └── Local/                     # FavoriteDrama (SwiftData 모델)
│   ├── DramaApp.entitlements          # (빈 dict — Xcode 재추가 방지용)
│   └── DesignSystem/                  # AppColors/Typography/Spacing 토큰
├── DramaApp.xcodeproj/
├── crawler/                           # TMDB → Supabase 배치
│   ├── src/
│   │   ├── index.ts                   # 오케스트레이션
│   │   ├── tmdb.ts                    # TMDB API 클라이언트
│   │   ├── supabase.ts                # Supabase upsert 헬퍼
│   │   ├── mapping.ts                 # TMDB → 우리 스키마 매핑
│   │   └── airTimes.ts                # 채널별 표준 방영 시간 추정
│   ├── package.json
│   └── .env.example
├── supabase/
│   ├── schema.sql                     # 12개 테이블 + 인덱스 + 트리거
│   ├── seed.sql                       # 채널 13종 (지상파/종편/OTT)
│   ├── policies.sql                   # RLS 정책 전체
│   └── migrations/
│       ├── 001_unique_tmdb_id.sql
│       ├── 002_persons_and_casts.sql
│       ├── 003_drama_availability.sql
│       └── 004_auth_bridge.sql        # auth.users → public.users 자동 브릿지 트리거
├── .github/workflows/
│   ├── crawler-daily.yml              # 매일 KST 03:00
│   └── crawler-weekly.yml             # 매주 일요일 04:00
├── DramaApp_Architecture.pdf          # 전체 설계 문서
├── WEEK1_SETUP.md                     # 초기 세팅 상세 가이드
├── WEEK5_SETUP.md                     # 로그인 + 즐겨찾기 동기화 세팅
├── WEEK5_GOOGLE_SETUP.md              # Google OAuth 상세 (Cloud Console + Supabase)
├── WORKLOG_YYYY-MM-DD.md              # 날짜별 작업 로그
└── CLAUDE.md                          # Claude Code용 프로젝트 노트
```

---

## 데이터 모델 요약

```
auth.users ─┐ (Supabase Auth · Google OAuth)
            │  1:1 (trigger handle_new_auth_user)
public.users ──< favorites >── dramas ──< episodes
                                 │
                                 ├──< drama_casts >── persons
                                 └──< drama_availability >── channels
                                                               (본방 + OTT 다시보기)
```

- **`dramas.status`**: `UPCOMING` · `ON_AIR` · `ENDED` — TMDB status에서 매핑
- **`episodes.air_time`**: `timestamptz` (UTC). 클라이언트는 KST로 표시
- **`drama_availability`**: M:N. "이 드라마를 볼 수 있는 채널" 의 single source of truth
- **`push_jobs`**: 방영 10분 전 알림 큐 (Week 6+ 구현 예정)
- 모든 테이블 RLS 활성화. 공개 읽기(`select`)는 허용, 쓰기는 로그인 사용자만
- **`auth.users` → `public.users` 브릿지**: OAuth 로그인 시 `handle_new_auth_user` 트리거가
  `public.users` 에 동일 `id` 로 자동 삽입. RLS 정책 `auth.uid() = user_id` 가 favorites 에서 그대로 동작

---

## 최초 셋업 (fresh clone)

### 1) Supabase 프로젝트

1. https://supabase.com 로그인 → **New project** (Seoul 리전 필수)
2. Project Settings → API 에서 두 값 확보:
   - Project URL
   - anon public key
   - service_role key (비공개, 크롤러 전용)
3. SQL Editor 에서 순서대로 실행:
   ```
   supabase/schema.sql
   supabase/seed.sql
   supabase/policies.sql
   supabase/migrations/001_unique_tmdb_id.sql
   supabase/migrations/002_persons_and_casts.sql
   supabase/migrations/003_drama_availability.sql
   supabase/migrations/004_auth_bridge.sql
   ```
4. Authentication → **Providers → Google** 활성화 + Client ID/Secret 등록
   → 자세한 절차는 [`WEEK5_GOOGLE_SETUP.md`](./WEEK5_GOOGLE_SETUP.md)
5. Authentication → **URL Configuration → Redirect URLs** 에 `dramaapp://auth-callback` 추가

### 2) TMDB API 토큰

https://www.themoviedb.org/settings/api → **API Read Access Token (v4)** 발급.
`eyJ...` 로 시작하는 JWT 형태.

### 3) iOS 앱 설정

```sh
cd DramaApp/Data/Network
cp SupabaseConfig.swift.example SupabaseConfig.swift
# SupabaseConfig.swift 편집 → url, anonKey 채움
# → .gitignore 에 포함돼 있어 git 에 안 올라감
```

Xcode 로 `DramaApp.xcodeproj` 열고 iPhone 시뮬레이터 선택 → ⌘R.

### 4) 크롤러 설정

```sh
cd crawler
cp .env.example .env
# .env 편집:
#   SUPABASE_URL=...
#   SUPABASE_SERVICE_ROLE_KEY=...   (anon 아님 주의)
#   TMDB_BEARER_TOKEN=...
#   CRAWL_START_DATE=2021-01-01
#   CRAWL_MAX_PAGES=100
npm install
npm start                              # 로컬 수동 실행 (~30분 for 5년치)
```

첫 실행 완료 후 Supabase 에서 확인:

```sql
select
  (select count(*) from dramas)              as dramas,
  (select count(*) from episodes)            as episodes,
  (select count(*) from persons)             as persons,
  (select count(*) from drama_casts)         as casts,
  (select count(*) from drama_availability)  as availability;
```

---

## 자동화 (GitHub Actions cron)

### Secrets 등록

Repository → **Settings → Secrets and variables → Actions** → New repository secret

| Name | 값 |
|---|---|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | service_role |
| `TMDB_BEARER_TOKEN` | TMDB v4 토큰 |

### 스케줄

| 워크플로우 | 스케줄 | 범위 | 소요 |
|---|---|---|---|
| `crawler-daily.yml` | 매일 KST 03:00 | 최근 90일 첫방작, 15페이지 | ~5분 |
| `crawler-weekly.yml` | 일요일 KST 04:00 | 2021-01-01 이후 전체, 100페이지 | ~30분 |

`workflow_dispatch` 로 언제든 Actions UI 에서 수동 실행 가능.

- 두 워크플로우는 `concurrency: crawler` 그룹으로 묶여 있어 겹치기 방지
- 실패 3회 연속 시 GitHub 이 이메일 자동 발송

---

## 개발 워크플로우

### iOS 빌드

```sh
# 사용 가능한 시뮬레이터 목록
xcrun simctl list devices available | grep iPhone

# 빌드
xcodebuild -project DramaApp.xcodeproj -scheme DramaApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# 테스트
xcodebuild -project DramaApp.xcodeproj -scheme DramaApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Xcode 26.2 의 **PBXFileSystemSynchronizedRootGroup** 사용. `.swift` 파일을
폴더에 추가하면 자동 포함 — `project.pbxproj` 수동 편집 금지.

### 크롤러 수동 실행

```sh
cd crawler
npm start
```

멱등(upsert)이라 몇 번을 돌려도 안전. 기존 데이터를 갱신할 뿐 삭제하지 않음.

### 스키마 변경 (마이그레이션 추가)

```sh
# 1. supabase/migrations/00X_description.sql 파일 작성
# 2. Supabase SQL Editor 에 붙여넣어 Run
# 3. 필요 시 crawler / iOS 코드 업데이트
# 4. 커밋
```

---

## Repository 프로토콜 — 확장 지점

`DramaRepository` 를 프로토콜로 끊어두어 백엔드 교체가 쉬움:

```swift
protocol DramaRepository: Sendable {
    func channels() async throws -> [Channel]
    func schedule(date: Date, channelIDs: [UUID]?) async throws -> [ScheduledEpisode]
    func drama(id: UUID) async throws -> Drama
    func search(query: String) async throws -> SearchResults
    func cast(for dramaId: UUID) async throws -> [CastMember]
    func availability(for dramaId: UUID) async throws -> [Channel]
}
```

- **`MockDramaRepository`** — 오프라인/프리뷰 개발
- **`SupabaseDramaRepository`** — 프로덕션
- 미래에 자체 백엔드(NestJS 등)로 바꿔도 뷰모델은 안 건드림

---

## 시크릿 관리

`.gitignore` 로 다음 파일들이 절대 커밋되지 않음:

- `DramaApp/Data/Network/SupabaseConfig.swift` — iOS anon key
- `crawler/.env` — service_role, TMDB 토큰
- Xcode `xcuserdata/`, `DerivedData/`
- `node_modules/`, `.DS_Store`

새로 클론한 사람은 `SupabaseConfig.swift.example`, `crawler/.env.example` 을
복사해 직접 값을 채움. GitHub Actions 는 Repository Secrets 로 주입.

---

## 로드맵 진행 현황

| Week | 스코프 | 상태 |
|---|---|---|
| 1 | Supabase 스키마, iOS SwiftUI 골격, 5 탭, DesignSystem | ✅ |
| 2 | TMDB 크롤러 (드라마/회차/출연/OTT availability) | ✅ |
| 3 | SupabaseDramaRepository, 편성표 실데이터, 상세 화면 | ✅ |
| 4 | 즐겨찾기 (SwiftData), 리스트 내 하트 토글 | ✅ |
| 5 | Google OAuth (ASWebAuth + Supabase PKCE), 로컬↔서버 즐겨찾기 sync | ✅ 코드 · ⏳ 대시보드 설정 대기 |
| 6 | 푸시 알림 (APNs, `push_jobs` 워커) | 예정 |
| 7 | 정밀 방영 시간 크롤 (방송사 직접), 홈피드 | 예정 |
| 8 | 마이 페이지, 회원탈퇴, 약관, TestFlight | 예정 |
| 9~10 | 베타 피드백, 크래시 모니터링 | 예정 |
| 11 | App Store v1.0 (커뮤니티 미포함) | 예정 |
| 12+ | 커뮤니티(게시판/댓글/신고/블라인드) — v2.0 | 예정 |

---

## 참고 문서

- [`DramaApp_Architecture.pdf`](./DramaApp_Architecture.pdf) — 전체 설계, DB, API, 비용, 리스크, 수익화
- [`WEEK1_SETUP.md`](./WEEK1_SETUP.md) — 초기 셋업 상세 (Supabase/TMDB 계정 발급 스크린 단위)
- [`WEEK5_SETUP.md`](./WEEK5_SETUP.md) — 로그인 + 즐겨찾기 동기화 인프라 세팅
- [`WEEK5_GOOGLE_SETUP.md`](./WEEK5_GOOGLE_SETUP.md) — Google OAuth 대시보드 설정 (Cloud Console + Supabase)
- [`CLAUDE.md`](./CLAUDE.md) — Claude Code 작업 시 알아야 할 프로젝트 관례
- [`crawler/README.md`](./crawler/README.md) — 크롤러 상세 (스크립트 옵션, 트러블슈팅)

작업 로그: `WORKLOG_YYYY-MM-DD.md` 형식으로 날짜별 누적 (최신부터 확인).
