-- ============================================================
-- DramaApp · Row Level Security (RLS) Policies
-- 적용: schema.sql + seed.sql 적용 후 실행
-- ============================================================

-- ------------------------------------------------------------
-- 공개 읽기 (드라마/채널/회차) — 인증 없이 누구나 SELECT 가능
-- ------------------------------------------------------------
alter table channels enable row level security;
drop policy if exists "channels_select_all" on channels;
create policy "channels_select_all" on channels for select using (true);

alter table dramas enable row level security;
drop policy if exists "dramas_select_all" on dramas;
create policy "dramas_select_all" on dramas for select using (true);

alter table episodes enable row level security;
drop policy if exists "episodes_select_all" on episodes;
create policy "episodes_select_all" on episodes for select using (true);

-- ------------------------------------------------------------
-- 사용자: 본인 정보만 조회/수정
-- ------------------------------------------------------------
alter table users enable row level security;

drop policy if exists "users_select_own" on users;
create policy "users_select_own" on users
  for select using (auth.uid() = id);

drop policy if exists "users_update_own" on users;
create policy "users_update_own" on users
  for update using (auth.uid() = id);

-- ------------------------------------------------------------
-- 즐겨찾기: 본인 것만
-- ------------------------------------------------------------
alter table favorites enable row level security;

drop policy if exists "favorites_all_own" on favorites;
create policy "favorites_all_own" on favorites
  for all using (auth.uid() = user_id)
          with check (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 디바이스(푸시 토큰): 본인 것만
-- ------------------------------------------------------------
alter table devices enable row level security;

drop policy if exists "devices_all_own" on devices;
create policy "devices_all_own" on devices
  for all using (auth.uid() = user_id)
          with check (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 게시글: 가려지지 않은 것은 누구나, 본인만 작성/수정/삭제
-- 차단한 사용자의 글은 안 보임
-- ------------------------------------------------------------
alter table posts enable row level security;

drop policy if exists "posts_select_visible" on posts;
create policy "posts_select_visible" on posts
  for select using (
    is_hidden = false
    and not exists (
      select 1 from blocks
      where blocker_id = auth.uid() and blocked_id = posts.user_id
    )
  );

drop policy if exists "posts_insert_own" on posts;
create policy "posts_insert_own" on posts
  for insert with check (auth.uid() = user_id);

drop policy if exists "posts_update_own" on posts;
create policy "posts_update_own" on posts
  for update using (auth.uid() = user_id);

drop policy if exists "posts_delete_own" on posts;
create policy "posts_delete_own" on posts
  for delete using (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 댓글: 위와 동일 패턴
-- ------------------------------------------------------------
alter table comments enable row level security;

drop policy if exists "comments_select_visible" on comments;
create policy "comments_select_visible" on comments
  for select using (
    is_hidden = false
    and not exists (
      select 1 from blocks
      where blocker_id = auth.uid() and blocked_id = comments.user_id
    )
  );

drop policy if exists "comments_insert_own" on comments;
create policy "comments_insert_own" on comments
  for insert with check (auth.uid() = user_id);

drop policy if exists "comments_delete_own" on comments;
create policy "comments_delete_own" on comments
  for delete using (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 좋아요: 본인 것만 (조회는 누구나)
-- ------------------------------------------------------------
alter table post_likes enable row level security;

drop policy if exists "likes_select_all" on post_likes;
create policy "likes_select_all" on post_likes for select using (true);

drop policy if exists "likes_insert_own" on post_likes;
create policy "likes_insert_own" on post_likes
  for insert with check (auth.uid() = user_id);

drop policy if exists "likes_delete_own" on post_likes;
create policy "likes_delete_own" on post_likes
  for delete using (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 신고: 본인이 작성한 신고만 조회, 누구나 작성 가능
-- ------------------------------------------------------------
alter table reports enable row level security;

drop policy if exists "reports_select_own" on reports;
create policy "reports_select_own" on reports
  for select using (auth.uid() = reporter_id);

drop policy if exists "reports_insert_own" on reports;
create policy "reports_insert_own" on reports
  for insert with check (auth.uid() = reporter_id);

-- ------------------------------------------------------------
-- 차단: 본인 차단 목록만
-- ------------------------------------------------------------
alter table blocks enable row level security;

drop policy if exists "blocks_all_own" on blocks;
create policy "blocks_all_own" on blocks
  for all using (auth.uid() = blocker_id)
          with check (auth.uid() = blocker_id);
