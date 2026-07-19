-- Migration 005: 드라마별 방영시간 오버라이드.
-- crawler/airTimes.ts 는 채널별 하드코딩 슬롯 (KBS=22:00 등) 을 쓰지만
-- 실제 방영은 드라마마다 다르다 (예: "사랑을 처방해 드립니다" 20:00).
-- 이 두 컬럼이 세팅되어 있으면 크롤러가 채널 기본값을 무시하고 이 값을 쓴다.

alter table public.dramas
  add column if not exists air_hour_kst smallint,
  add column if not exists air_minute_kst smallint;

comment on column public.dramas.air_hour_kst is
  'KST 방영 시간 (0-23). null 이면 crawler airTimes.ts 채널 기본값 사용.';
comment on column public.dramas.air_minute_kst is
  'KST 방영 분 (0-59). null 이면 채널 기본값의 분 사용.';

-- 이미 잘못 저장된 episodes.air_time 을 편하게 재계산하는 함수.
-- 사용 예:
--   update public.dramas set air_hour_kst = 20, air_minute_kst = 0
--     where title = '사랑을 처방해 드립니다';
--   select public.recompute_episode_air_times(
--     (select id from public.dramas where title = '사랑을 처방해 드립니다')
--   );
create or replace function public.recompute_episode_air_times(target_drama_id uuid)
returns integer
language plpgsql
as $$
declare
  h smallint;
  m smallint;
  updated integer;
begin
  select air_hour_kst, air_minute_kst into h, m
    from public.dramas where id = target_drama_id;
  if h is null then
    raise notice '드라마 %: air_hour_kst 미설정 — no-op', target_drama_id;
    return 0;
  end if;
  update public.episodes
    set air_time =
      ((air_time at time zone 'Asia/Seoul')::date
        + make_time(h, coalesce(m, 0), 0)
      ) at time zone 'Asia/Seoul'
    where drama_id = target_drama_id;
  get diagnostics updated = row_count;
  return updated;
end;
$$;
