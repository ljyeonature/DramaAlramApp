# DramaApp Crawler

TMDB 기반 한국 드라마 메타데이터 → Supabase 적재 스크립트.

## 셋업 (1회만)

```sh
cd crawler
npm install
cp .env.example .env
# .env 파일 열어서 세 값 채우기
```

`.env`에 채울 값:

| 키 | 어디서 | 비고 |
|---|---|---|
| `SUPABASE_URL` | Supabase 대시보드 → Settings → API | Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | 같은 화면 → service_role | **⚠ 절대 클라이언트/git 공개 금지** |
| `TMDB_BEARER_TOKEN` | themoviedb.org → Settings → API → API Read Access Token (v4) | `eyJ...`로 시작 |

## 사전 준비 (Supabase)

크롤러는 `dramas.tmdb_id`에 UNIQUE 제약이 필요합니다. SQL Editor에서:

```sh
pbcopy < ../supabase/migrations/001_unique_tmdb_id.sql
```

→ Supabase SQL Editor에 붙여넣고 Run. 1회만.

## 실행

```sh
npm start
```

기본 3페이지(60개 드라마)를 가져와 `dramas` + `episodes` 테이블에 upsert.

페이지 수 조절은 `.env`에서 `CRAWL_PAGES=5` 같이 변경.

## 멱등성

- `dramas`: `tmdb_id` 충돌 시 update
- `episodes`: `(drama_id, number)` 충돌 시 update

→ **여러 번 실행해도 안전.** 같은 드라마/회차는 갱신만 됨.

## 로그 예시

```
[init] Supabase URL: https://abcd.supabase.co
[init] TMDB pages: 3 (max 60 dramas)

[init] 채널 로드 완료: KBS2, MBC, SBS, tvN, JTBC

[discover] page 1/3
  ✓ 폭군의 셰프 [tvN] · 회차 12건 · Ended
  ✓ 약한영웅 Class 2 [Netflix] — 알 수 없는 네트워크 [Netflix]
  ⊘ skip ...
  ...

═══════════════════════════════════════
완료. 드라마 upsert: 42건, 회차 upsert: 671건
스킵: 18건, 실패: 0건
═══════════════════════════════════════
```

## 검증

Supabase SQL Editor에서:

```sql
select
  (select count(*) from dramas)  as drama_count,
  (select count(*) from episodes) as episode_count;
```

100건 이상이면 Week 2A 완료.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `channels 테이블이 비어 있음` | seed.sql 미적용 | Supabase SQL Editor에 `supabase/seed.sql` 실행 |
| `drama upsert failed: there is no unique or exclusion constraint` | migration 001 미적용 | `supabase/migrations/001_unique_tmdb_id.sql` 실행 |
| `TMDB 401` | 토큰 잘못 / 만료 | v4 Bearer Token인지 확인 (v3 API key 아님) |
| `429 rate limited` | TMDB rate limit | 코드의 throttle 간격(`MIN_INTERVAL_MS`) 늘리기 |
| 모든 드라마가 "알 수 없는 네트워크"로 스킵 | `mapping.ts`의 NETWORK_NAME_TO_CODE 매핑 누락 | 로그에 찍힌 네트워크명을 매핑에 추가 |

## 다음 단계 (Week 2B)

지금은 수동 실행. 매일 새벽 3시 자동화는 Fly.io + cron, 또는 GitHub Actions로 Week 2B에서.
