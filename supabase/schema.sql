-- ============================================================
-- DramaApp · Database Schema (PostgreSQL / Supabase)
-- 적용 위치: Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣기 → Run
-- ============================================================

-- 한글 부분 검색용 trigram 확장
create extension if not exists pg_trgm;

-- ============================================================
-- 1. 사용자
-- ============================================================
create table if not exists users (
  id           uuid primary key default gen_random_uuid(),
  apple_sub    text unique not null,
  nickname     text unique not null,
  avatar_url   text,
  is_blocked   boolean default false,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- ============================================================
-- 2. 채널 (방송사 / OTT)
-- ============================================================
create table if not exists channels (
  id       uuid primary key default gen_random_uuid(),
  code     text unique not null,             -- 'KBS2','MBC','SBS','tvN','JTBC','NETFLIX'
  name     text not null,
  type     text not null check (type in ('BROADCAST','OTT')),
  logo_url text
);

-- ============================================================
-- 3. 드라마
-- ============================================================
create table if not exists dramas (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  title_en       text,
  synopsis       text,
  poster_url     text,
  channel_id     uuid references channels(id),
  status         text not null check (status in ('UPCOMING','ON_AIR','ENDED')),
  total_episodes int,
  start_date     date,
  end_date       date,
  tmdb_id        int,
  external_id    text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);
create index if not exists idx_dramas_status on dramas(status);
create index if not exists idx_dramas_channel on dramas(channel_id);
create index if not exists idx_dramas_title_trgm on dramas using gin (title gin_trgm_ops);

-- ============================================================
-- 4. 회차 (편성표의 실제 단위)
-- ============================================================
create table if not exists episodes (
  id           uuid primary key default gen_random_uuid(),
  drama_id     uuid not null references dramas(id) on delete cascade,
  number       int not null,
  air_time     timestamptz not null,
  duration_min int default 70,
  is_special   boolean default false,
  created_at   timestamptz default now(),
  unique (drama_id, number)
);
create index if not exists idx_episodes_air_time on episodes(air_time);
create index if not exists idx_episodes_air_date on episodes((air_time::date));

-- ============================================================
-- 5. 즐겨찾기
-- ============================================================
create table if not exists favorites (
  user_id             uuid not null references users(id) on delete cascade,
  drama_id            uuid not null references dramas(id) on delete cascade,
  notify_air          boolean default true,
  notify_new_episode  boolean default true,
  created_at          timestamptz default now(),
  primary key (user_id, drama_id)
);

-- ============================================================
-- 6. 디바이스 (APNs 토큰)
-- ============================================================
create table if not exists devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references users(id) on delete cascade,
  apns_token   text unique not null,
  app_version  text,
  os_version   text,
  locale       text default 'ko-KR',
  last_seen_at timestamptz default now(),
  created_at   timestamptz default now()
);

-- ============================================================
-- 7. 커뮤니티: 게시글
-- ============================================================
create table if not exists posts (
  id            uuid primary key default gen_random_uuid(),
  drama_id      uuid not null references dramas(id) on delete cascade,
  user_id       uuid not null references users(id),
  title         text not null,
  body          text not null,
  is_spoiler    boolean default false,
  episode_no    int,
  like_count    int default 0,
  comment_count int default 0,
  hot_score     real default 0,
  is_hidden     boolean default false,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);
create index if not exists idx_posts_drama_created on posts(drama_id, created_at desc);
create index if not exists idx_posts_hot on posts(hot_score desc) where is_hidden = false;

-- ============================================================
-- 8. 댓글
-- ============================================================
create table if not exists comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references posts(id) on delete cascade,
  user_id    uuid not null references users(id),
  parent_id  uuid references comments(id),
  body       text not null,
  is_spoiler boolean default false,
  like_count int default 0,
  is_hidden  boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_comments_post on comments(post_id, created_at);

-- ============================================================
-- 9. 좋아요
-- ============================================================
create table if not exists post_likes (
  post_id    uuid not null references posts(id) on delete cascade,
  user_id    uuid not null references users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

-- ============================================================
-- 10. 신고
-- ============================================================
create table if not exists reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references users(id),
  target_type text not null check (target_type in ('POST','COMMENT','USER')),
  target_id   uuid not null,
  reason      text not null,
  detail      text,
  status      text default 'PENDING' check (status in ('PENDING','RESOLVED','REJECTED')),
  created_at  timestamptz default now()
);

-- ============================================================
-- 11. 차단
-- ============================================================
create table if not exists blocks (
  blocker_id uuid not null references users(id) on delete cascade,
  blocked_id uuid not null references users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (blocker_id, blocked_id)
);

-- ============================================================
-- 12. 푸시 알림 큐
-- ============================================================
create table if not exists push_jobs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references users(id) on delete cascade,
  episode_id   uuid references episodes(id) on delete cascade,
  scheduled_at timestamptz not null,
  status       text default 'PENDING' check (status in ('PENDING','SENT','FAILED')),
  payload      jsonb not null,
  created_at   timestamptz default now(),
  sent_at      timestamptz
);
create index if not exists idx_push_jobs_due on push_jobs(scheduled_at) where status = 'PENDING';

-- ============================================================
-- 좋아요/댓글 카운트 비정규화 트리거
-- ============================================================
create or replace function bump_post_like_count() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update posts set like_count = like_count + 1 where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$$ language plpgsql;

drop trigger if exists trg_post_likes_count on post_likes;
create trigger trg_post_likes_count
after insert or delete on post_likes
for each row execute function bump_post_like_count();

create or replace function bump_post_comment_count() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update posts set comment_count = comment_count + 1 where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update posts set comment_count = greatest(comment_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$$ language plpgsql;

drop trigger if exists trg_post_comment_count on comments;
create trigger trg_post_comment_count
after insert or delete on comments
for each row execute function bump_post_comment_count();
