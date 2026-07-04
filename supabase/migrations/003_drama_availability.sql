-- Migration 003: 드라마 시청 가능 채널(M:N).
-- 본방(BROADCAST 채널)도 OTT(다시보기)도 모두 이 테이블에 기록.
-- 결과: "어떤 채널에 가면 이 드라마를 볼 수 있는가?" 가 single source of truth.

-- ============================================================
-- 테이블
-- ============================================================
create table if not exists drama_availability (
  drama_id   uuid not null references dramas(id) on delete cascade,
  channel_id uuid not null references channels(id),
  link       text,
  created_at timestamptz default now(),
  primary key (drama_id, channel_id)
);

-- 채널 → 가용 드라마 역검색용
create index if not exists idx_availability_channel
  on drama_availability(channel_id);

-- ============================================================
-- RLS
-- ============================================================
alter table drama_availability enable row level security;
drop policy if exists "availability_select_all" on drama_availability;
create policy "availability_select_all"
  on drama_availability for select using (true);

-- ============================================================
-- 백필: 기존 드라마의 본방 채널을 availability 에 1회 주입.
-- 멱등 (on conflict do nothing).
-- ============================================================
insert into drama_availability (drama_id, channel_id)
select id, channel_id
from dramas
where channel_id is not null
on conflict do nothing;
