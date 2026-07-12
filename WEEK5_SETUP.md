# Week 5 · Apple Sign In + 즐겨찾기 서버 동기화 세팅

Week 5 코드 변경은 모두 커밋 가능한 형태로 완료됐지만 아래 **수동 설정** 세 곳(Xcode / Apple Developer / Supabase)이 있어야 실기기에서 로그인이 성공합니다.

---

## 1. Supabase — 마이그레이션 + Apple provider

### 1-1. SQL 마이그레이션 실행
Supabase 대시보드 → SQL Editor 에서 `supabase/migrations/004_auth_bridge.sql` 전체 붙여넣기 → Run.

이 마이그레이션이 하는 일:
- `public.users.apple_sub` / `nickname` NOT NULL 제약 완화 (로그인 직후엔 값 없음)
- `nickname_set_by_user` 컬럼 추가 (커뮤니티 오픈 시점에 사용자 지정)
- `auth.users` INSERT → `public.users` 자동 브릿지 트리거 (`handle_new_auth_user`)
- 기존 auth.users 사용자에 대한 backfill

### 1-2. Apple provider 활성화
대시보드 → **Authentication → Providers → Apple** → Enable.

입력 필드:
| 필드 | 값 |
|---|---|
| Services ID | `com.code.review.public.DramaApp.signin` (아래 3-1 에서 만든 값) |
| Team ID | Apple Developer 계정의 Team ID (10자) |
| Key ID | Sign in with Apple Key ID |
| Private Key | Sign in with Apple Key 의 `.p8` 파일 내용 |

Redirect URL 은 Supabase 가 자동 표시 — Apple Developer 쪽 Return URL 에 그대로 넣어야 합니다.

---

## 2. Xcode — Sign in with Apple capability

프로젝트 파일 열고 **DramaApp target → Signing & Capabilities → + Capability → Sign in with Apple** 추가.

- 이 액션이 자동으로:
  - `DramaApp/DramaApp.entitlements` 파일을 프로젝트에 등록 (파일 자체는 이미 커밋됨)
  - `CODE_SIGN_ENTITLEMENTS = DramaApp/DramaApp.entitlements` 를 build settings 에 추가
- Team 이 설정돼 있어야 함 (Automatic signing). 실기기 테스트라면 유료 개발자 계정 필요.

---

## 3. Apple Developer — App ID + Service ID + Key

Apple Developer Portal (developer.apple.com/account) 접속.

### 3-1. App ID 에 Sign In with Apple 활성화
Identifiers → App IDs → `com.code.review.public.DramaApp` → Capabilities 에서 **Sign In with Apple** 체크 → Save.

### 3-2. Services ID 생성 (OAuth 콜백용)
Identifiers → **Services IDs** → `+` → Identifier: `com.code.review.public.DramaApp.signin` → Description 자유. Continue → Configure → Sign In with Apple 활성화, Return URL 에 Supabase 가 준 콜백 URL 붙여넣기 → Save.

### 3-3. Sign In with Apple Key
Keys → `+` → Key Name 자유 → Sign In with Apple 체크 → Configure → App ID 선택 (com.code.review.public.DramaApp) → Continue → Register → **`.p8` 다운로드 (한 번만 가능!)**. Key ID 도 기록.

이 3개 (Services ID / Team ID / Key ID / .p8) 를 Supabase Apple provider 설정 (1-2) 에 넣습니다.

---

## 4. 동작 확인

```sh
xcodebuild -project DramaApp.xcodeproj -scheme DramaApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

성공하면 시뮬레이터 실행:
1. **마이 탭** → "Sign in with Apple" 버튼 노출
2. 탭 → Apple ID 시트 → Continue → 세션 발급 → 유저 ID 표시
3. **편성표/상세 탭** → 즐겨찾기 토글 시 서버 favorites 테이블에도 mirror
4. 앱 재실행 → 세션 자동 복원 (Keychain)
5. 로그아웃 → 로컬 즐겨찾기는 유지, 서버 mirror 만 중단

Supabase 대시보드 → Table Editor → `favorites` 에서 row 가 생성되는지 확인.

---

## 5. 트러블슈팅

**로그인 시 "invalid_grant" 또는 "id_token verification failed"**
- Supabase Apple provider 의 Services ID / Key 가 잘못 등록됨. 특히 Private Key `.p8` 은 파일 내용 전체(BEGIN/END 라인 포함) 를 그대로 붙여넣어야 합니다.

**시뮬레이터에서 "Sign in with Apple 을 사용할 수 없음"**
- 시뮬레이터에 Apple ID 로그인이 안 돼 있음. 설정 → Sign in to your iPhone → 개발자 계정 로그인.

**서버에는 favorites 가 안 보이는데 UI 는 정상**
- 미로그인 상태에서만 로컬에 저장됨. 로그인 후 편성표에서 다시 하트 토글하거나, 앱 재실행 시 `syncFromServer` 가 로컬을 서버로 업로드합니다 (RootView `.task` 훅).

**users 테이블에 자동 row 가 안 생김**
- 마이그레이션 004 미실행. 트리거 `on_auth_user_created` 가 auth.users insert 시점에 발동합니다.
