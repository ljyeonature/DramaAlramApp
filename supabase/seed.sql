-- ============================================================
-- DramaApp · Seed Data (채널)
-- 적용: schema.sql 적용 후 SQL Editor에서 실행
-- 멱등 (ON CONFLICT) 처리: 여러 번 실행해도 안전 — 새 채널만 추가됨
-- ============================================================

insert into channels (code, name, type, logo_url) values
  -- 지상파 / 종편 / 케이블 (방송)
  ('KBS2',         'KBS 2TV',     'BROADCAST', null),
  ('MBC',          'MBC',         'BROADCAST', null),
  ('SBS',          'SBS',         'BROADCAST', null),
  ('tvN',          'tvN',         'BROADCAST', null),
  ('JTBC',         'JTBC',        'BROADCAST', null),
  ('ENA',          'ENA',         'BROADCAST', null),
  ('MBN',          'MBN',         'BROADCAST', null),
  ('GENIE_TV',     'Genie TV',    'BROADCAST', null),
  -- OTT
  ('NETFLIX',      'Netflix',     'OTT',       null),
  ('DISNEY_PLUS',  'Disney+',     'OTT',       null),
  ('COUPANG_PLAY', 'Coupang Play','OTT',       null),
  ('WAVVE',        'Wavve',       'OTT',       null),
  ('TVING',        'TVING',       'OTT',       null)
on conflict (code) do nothing;
