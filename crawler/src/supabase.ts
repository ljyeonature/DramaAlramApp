// Supabase 클라이언트 — service_role 키로 RLS 우회. 서버 사이드 전용.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import WebSocket from 'ws';
import type {
  DramaRow,
  EpisodeRow,
  PersonRow,
  DramaCastRow,
  AvailabilityRow,
} from './mapping.js';

export function makeClient(url: string, serviceRoleKey: string): SupabaseClient {
  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    // 크롤러는 realtime을 쓰지 않지만 supabase-js가 클라이언트 초기화 시점에
    // WebSocket 생성자를 요구한다. Node에는 표준 전역 WebSocket 이 버전마다 다르므로
    // ws 패키지를 명시적으로 주입해 어느 Node 에서도 초기화가 성공하게 한다.
    realtime: {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      transport: WebSocket as any,
    },
  });
}

/** 채널 코드 → UUID 맵을 DB에서 한 번에 로드. */
export async function loadChannelMap(
  client: SupabaseClient
): Promise<Map<string, string>> {
  const { data, error } = await client
    .from('channels')
    .select('id, code');
  if (error) throw new Error(`channels load failed: ${error.message}`);
  if (!data || data.length === 0) {
    throw new Error('channels 테이블이 비어 있음. supabase/seed.sql 먼저 실행하세요.');
  }
  return new Map(data.map((c) => [c.code as string, c.id as string]));
}

/** 드라마 upsert. tmdb_id 기준 충돌 시 갱신. 반환: 우리 DB의 drama.id */
export async function upsertDrama(
  client: SupabaseClient,
  row: DramaRow
): Promise<string> {
  const { data, error } = await client
    .from('dramas')
    .upsert(row, { onConflict: 'tmdb_id' })
    .select('id')
    .single();
  if (error) throw new Error(`drama upsert failed (tmdb_id=${row.tmdb_id}): ${error.message}`);
  return data.id as string;
}

/** 회차 일괄 upsert. (drama_id, number) 기준 충돌 시 갱신. */
export async function upsertEpisodes(
  client: SupabaseClient,
  rows: EpisodeRow[]
): Promise<number> {
  if (rows.length === 0) return 0;
  const { error, count } = await client
    .from('episodes')
    .upsert(rows, { onConflict: 'drama_id,number', count: 'exact' });
  if (error) throw new Error(`episodes upsert failed: ${error.message}`);
  return count ?? rows.length;
}

/** 인물 upsert + tmdb_id → person.id 맵 반환. */
export async function upsertPersonsAndGetIDs(
  client: SupabaseClient,
  rows: PersonRow[]
): Promise<Map<number, string>> {
  if (rows.length === 0) return new Map();
  const { error: upErr } = await client
    .from('persons')
    .upsert(rows, { onConflict: 'tmdb_id' });
  if (upErr) throw new Error(`persons upsert failed: ${upErr.message}`);

  // ID 회수를 위해 별도 SELECT (upsert .select()는 conflict row 미반환 케이스 있음)
  const tmdbIds = rows.map((r) => r.tmdb_id);
  const { data, error: selErr } = await client
    .from('persons')
    .select('id, tmdb_id')
    .in('tmdb_id', tmdbIds);
  if (selErr) throw new Error(`persons select failed: ${selErr.message}`);
  return new Map(
    (data ?? []).map((p) => [p.tmdb_id as number, p.id as string])
  );
}

/** 출연 일괄 upsert. (drama_id, person_id) 기준 충돌 시 갱신. */
export async function upsertDramaCasts(
  client: SupabaseClient,
  rows: DramaCastRow[]
): Promise<number> {
  if (rows.length === 0) return 0;
  const { error } = await client
    .from('drama_casts')
    .upsert(rows, { onConflict: 'drama_id,person_id' });
  if (error) throw new Error(`drama_casts upsert failed: ${error.message}`);
  return rows.length;
}

/** 시청 가능 채널 upsert. (drama_id, channel_id) 기준 충돌 시 link 갱신. */
export async function upsertAvailability(
  client: SupabaseClient,
  rows: AvailabilityRow[]
): Promise<number> {
  if (rows.length === 0) return 0;
  const { error } = await client
    .from('drama_availability')
    .upsert(rows, { onConflict: 'drama_id,channel_id' });
  if (error) throw new Error(`availability upsert failed: ${error.message}`);
  return rows.length;
}
