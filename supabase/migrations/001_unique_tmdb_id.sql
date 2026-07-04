-- Migration 001: dramas.tmdb_id 에 UNIQUE 제약을 추가한다.
-- 크롤러가 upsert(onConflict: 'tmdb_id') 할 수 있도록 필요.
-- Postgres UNIQUE는 다중 NULL 허용 — 수동 입력 드라마(tmdb_id=null) 공존 가능.

alter table dramas
  add constraint dramas_tmdb_id_unique unique (tmdb_id);
