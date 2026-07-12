# Google OAuth 로그인 세팅

Apple 대안으로 붙인 Google 로그인. **유료 개발자 멤버십 불필요**, 시뮬레이터에서 바로 테스트 가능.

구현 방식: **ASWebAuthenticationSession + Supabase PKCE OAuth** — 외부 SDK 의존성 없이 Apple 표준 API 만 사용.

---

## 1. Google Cloud Console — OAuth 2.0 Client 발급

### 1-1. 프로젝트 생성 / 선택
[Google Cloud Console](https://console.cloud.google.com/) → 프로젝트 새로 만들기 (예: DramaApp).

### 1-2. OAuth 동의 화면 (Consent Screen) 설정
APIs & Services → OAuth consent screen
- User Type: **External**
- App name: `DramaApp` (사용자에게 표시됨)
- User support email: 본인 이메일
- Developer contact information: 본인 이메일
- Scopes: `openid`, `email`, `profile` 만 있으면 됨 (기본값)
- Test users: 본인 Google 계정 추가 (Publishing status 가 "Testing" 인 동안은 등록된 사용자만 로그인 가능)

### 1-3. OAuth Client ID 생성
APIs & Services → Credentials → Create Credentials → **OAuth client ID**
- Application type: **Web application** (모바일 아님. Supabase 가 서버 측에서 토큰 교환하므로)
- Name: `DramaApp Supabase Auth`
- **Authorized redirect URIs** 에 Supabase 콜백 URL 추가:
  ```
  https://cmlfyqynogltoigbebtb.supabase.co/auth/v1/callback
  ```
  (본인 Supabase URL 로 교체. Supabase 대시보드 Authentication → Providers → Google 에서도 이 URL 확인 가능)

**Client ID** 와 **Client Secret** 을 복사 — 다음 단계에서 사용.

---

## 2. Supabase 대시보드 설정

### 2-1. Google Provider 활성화
Authentication → Providers → **Google** → Enable

| 필드 | 값 |
|---|---|
| Client ID | 위 1-3 에서 받은 Web Client ID |
| Client Secret | 위 1-3 에서 받은 Client Secret |
| Authorized Client IDs | 비워둠 (iOS SDK 안 씀) |

Save. 여기서 표시되는 Callback URL 이 1-3 에 넣은 URL 과 일치해야 함.

### 2-2. Redirect URLs 등록
Authentication → **URL Configuration** → Redirect URLs 에 앱 커스텀 스킴 추가:
```
dramaapp://auth-callback
```
Save.

이걸 안 하면 Supabase 가 로그인 성공 후 앱으로 리다이렉트를 거부합니다. (400 "redirect not allowed")

---

## 3. iOS 앱 — 이미 준비됨 (커밋 파일에 포함)

이 커밋에 이미 반영된 것들 (수동 확인용):
- `DramaApp/Info.plist` — `CFBundleURLSchemes: [dramaapp]` 등록
- `DramaApp/Data/Auth/OAuthFlow.swift` — PKCE + ASWebAuthenticationSession
- `DramaApp/Data/Auth/SupabaseAuthClient.swift` — `exchangePKCE(code:, verifier:)` 메서드
- `DramaApp/Data/Auth/AuthStore.swift` — `signInWithGoogle(presentationAnchor:)`
- `DramaApp/Features/Profile/ProfileView.swift` — "Google 로 계속하기" 버튼
- `DramaApp/Data/Network/SupabaseConfig.swift` — `oauthRedirectURL`, `oauthCallbackScheme` 상수

### Supabase 마이그레이션 004 (아직 안 돌렸다면)
```sh
# Supabase 대시보드 → SQL Editor 에서 실행
supabase/migrations/004_auth_bridge.sql
```
Google 도 auth.users insert 를 발생시키므로 `handle_new_auth_user` 트리거로 자동 `public.users` 생성 됨. Apple 과 동일한 브릿지 사용.

---

## 4. 동작 확인

```sh
xcodebuild -project DramaApp.xcodeproj -scheme DramaApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

시뮬레이터에서:
1. **마이 탭** → "Google 로 계속하기" 버튼
2. 탭 → Safari 스타일 시트 → 등록한 Google 계정으로 로그인
3. `dramaapp://auth-callback?code=...` 로 리다이렉트 → 시트 자동 닫힘
4. Supabase 세션 발급 → 마이 탭에 유저 ID 표시
5. 편성표/상세에서 즐겨찾기 토글 → `favorites` 테이블에 mirror 확인

Supabase 대시보드 → Table Editor → `auth.users` 에 새 row 가 생기고, `public.users` 에도 자동 브릿지된 row 가 있어야 정상.

---

## 5. 트러블슈팅

**"redirect not allowed"** — 2-2 를 안 함. `dramaapp://auth-callback` 을 Supabase Redirect URLs 에 추가.

**"invalid_request: nonce mismatch"** — 발생할 일 없음 (PKCE 는 nonce 대신 code_verifier 사용). 이런 에러가 뜨면 grant_type 이 잘못 갔을 가능성 → 앱 재설치.

**Consent screen "This app isn't verified"** — Google 이 미검증 앱에 표시하는 경고. 개발 중엔 "Advanced → Go to DramaApp (unsafe)" 로 진행 가능. 프로덕션 배포 시 검증 신청.

**시트가 안 뜨고 즉시 실패** — Info.plist 의 `CFBundleURLSchemes` 에 `dramaapp` 이 없거나 오타. Xcode 에서 앱 삭제 후 재빌드.

**로그인 성공했는데 세션이 없음** — `exchangePKCE` 응답 파싱 실패. Xcode 콘솔의 `[FATAL]` 이나 에러 알림 메시지 확인.
