-- Migration 002: 인물(persons) + 출연(drama_casts) 테이블 추가.
-- 멱등 (if not exists / drop policy if exists). 여러 번 실행 안전.

-- ============================================================
-- 인물
-- ============================================================
create table if not exists persons (
  id          uuid primary key default gen_random_uuid(),
  tmdb_id     int unique,
  name        text not null,
  profile_url text,
  created_at  timestamptz default now()
);

-- 한글 부분 검색 (배우 검색 v3에서 사용 예정)
create index if not exists idx_persons_name_trgm
  on persons using gin (name gin_trgm_ops);

-- ============================================================
-- 출연 (M:N)
-- ============================================================
create table if not exists drama_casts (
  drama_id      uuid not null references dramas(id) on delete cascade,
  person_id     uuid not null references persons(id) on delete cascade,
  character     text,
  display_order int default 0,
  primary key (drama_id, person_id)
);

create index if not exists idx_drama_casts_drama
  on drama_casts(drama_id, display_order);

-- ============================================================
-- RLS: 공개 읽기
-- ============================================================
alter table persons enable row level security;
drop policy if exists "persons_select_all" on persons;
create policy "persons_select_all" on persons for select using (true);

alter table drama_casts enable row level security;
drop policy if exists "drama_casts_select_all" on drama_casts;
create policy "drama_casts_select_all" on drama_casts for select using (true);
