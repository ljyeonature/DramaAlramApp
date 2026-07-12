-- ============================================================
-- Week 5 · Apple Sign In 브릿지
-- ============================================================
-- public.users 는 앱 도메인 유저 테이블. RLS 정책이 auth.uid() = user_id 를
-- 요구하므로 public.users.id 가 auth.users.id 와 동일해야 한다.
-- 로그인 직후엔 apple_sub / nickname 을 확정할 수 없으므로 제약을 완화하고,
-- auth.users 에 새 row 가 생기면 트리거로 public.users 를 자동 생성한다.
-- ============================================================

-- 1) 제약 완화 — 로그인 직후엔 값 채우기 전이라 not null 유지 불가.
alter table public.users alter column apple_sub drop not null;
alter table public.users alter column nickname  drop not null;

-- 닉네임은 커뮤니티 오픈(Week 12) 시점에 사용자가 직접 설정. 그 전엔 자동 생성값 사용.
alter table public.users
  add column if not exists nickname_set_by_user boolean not null default false;

-- 2) auth.users → public.users 자동 브릿지 트리거.
--    security definer 로 실행해야 auth 스키마에 접근 가능.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, nickname)
  values (
    new.id,
    'user_' || substring(new.id::text from 1 for 8)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_auth_user();

-- 3) 기존 auth.users 에 있는 사용자(개발/테스트로 미리 생긴)에 대한 backfill.
insert into public.users (id, nickname)
select u.id, 'user_' || substring(u.id::text from 1 for 8)
from auth.users u
where not exists (select 1 from public.users p where p.id = u.id)
on conflict (id) do nothing;

-- 4) favorites INSERT 정책은 이미 favorites_all_own (auth.uid() = user_id) 로 잡혀 있음.
--    users.id = auth.users.id 가 성립하므로 그대로 동작.
