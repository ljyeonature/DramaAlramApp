// TMDB 응답 → 우리 Supabase 스키마 매핑.

import type {
  TMDBTVDetail,
  TMDBEpisode,
  TMDBCastMember,
  TMDBWatchProvidersResponse,
} from './tmdb.js';
import { posterURL, profileURL } from './tmdb.js';
import { estimateAirTimeUTC } from './airTimes.js';

export type DramaStatus = 'UPCOMING' | 'ON_AIR' | 'ENDED';

export interface DramaRow {
  title: string;
  title_en: string | null;
  synopsis: string | null;
  poster_url: string | null;
  channel_id: string;
  status: DramaStatus;
  total_episodes: number | null;
  start_date: string | null; // 'YYYY-MM-DD'
  end_date: string | null;
  tmdb_id: number;
}

export interface EpisodeRow {
  drama_id: string;
  number: number;
  air_time: string; // ISO UTC
  duration_min: number;
  is_special: boolean;
}

// TMDB 네트워크 이름 → 우리 channels.code.
// TMDB는 같은 방송사를 여러 이름으로 표기하므로 다중 별칭 매핑.
// 매칭 안 되는 네트워크(Vigloo, Lezhin Snack, ReelShort, DramaBox 등 단편/세로 드라마,
// iQIYI 등 해외) 는 의도적으로 스킵.
const NETWORK_NAME_TO_CODE: Record<string, string> = {
  // 지상파
  'KBS': 'KBS2',
  'KBS 2TV': 'KBS2',
  'KBS2': 'KBS2',
  'KBS1': 'KBS2',
  'MBC': 'MBC',
  'Munhwa Broadcasting Corporation': 'MBC',
  'SBS': 'SBS',
  'Seoul Broadcasting System': 'SBS',
  // 종편 / 케이블
  'tvN': 'tvN',
  'CJ ENM': 'tvN',
  'JTBC': 'JTBC',
  'ENA': 'ENA',
  'MBN': 'MBN',
  'MBN Plus': 'MBN',
  'Genie TV': 'GENIE_TV',
  // OTT
  'Netflix': 'NETFLIX',
  'Disney+': 'DISNEY_PLUS',
  'Disney Plus': 'DISNEY_PLUS',
  'Coupang Play': 'COUPANG_PLAY',
  'wavve': 'WAVVE',
  'Wavve': 'WAVVE',
  'TVING': 'TVING',
  'Tving': 'TVING',
};

/**
 * TMDB networks 배열에서 우리가 아는 방송사 코드를 추출한다.
 * 모르는 방송사면 null — 호출부에서 해당 드라마 스킵.
 */
export function pickChannelCode(networks: { name: string }[]): string | null {
  for (const net of networks) {
    const code = NETWORK_NAME_TO_CODE[net.name];
    if (code) return code;
  }
  return null;
}

export function mapStatus(tmdbStatus: string): DramaStatus {
  switch (tmdbStatus) {
    case 'Returning Series':
      return 'ON_AIR';
    case 'Ended':
    case 'Canceled':
      return 'ENDED';
    case 'In Production':
    case 'Planned':
    case 'Pilot':
      return 'UPCOMING';
    default:
      return 'ENDED';
  }
}

export function toDramaRow(
  detail: TMDBTVDetail,
  channelId: string
): DramaRow {
  // 한국 드라마의 경우 original_name이 항상 한국어 원제.
  // name은 ko-KR 로케일 요청 시 한국어, 영어 영문제목이 있으면 영문이 올 수도 있음.
  // → 한국어를 강제하기 위해 original_name을 우선 사용.
  const korTitle = detail.original_name || detail.name;
  const enTitle =
    detail.name && detail.name !== korTitle ? detail.name : null;
  return {
    title: korTitle,
    title_en: enTitle,
    synopsis: detail.overview || null,
    poster_url: posterURL(detail.poster_path),
    channel_id: channelId,
    status: mapStatus(detail.status),
    total_episodes: detail.number_of_episodes,
    start_date: detail.first_air_date || null,
    end_date: detail.last_air_date || null,
    tmdb_id: detail.id,
  };
}

export function toEpisodeRows(
  episodes: TMDBEpisode[],
  dramaId: string,
  channelCode: string,
  defaultRuntime: number,
  override?: { hour: number | null; minute: number | null } | null
): EpisodeRow[] {
  const slotOverride = override && override.hour != null
    ? { hour: override.hour, minute: override.minute ?? 0 }
    : null;
  return episodes
    .filter((ep) => ep.air_date) // 방영일 없는 회차는 스킵 (예고편 등)
    .map((ep) => ({
      drama_id: dramaId,
      number: ep.episode_number,
      air_time: estimateAirTimeUTC(ep.air_date!, channelCode, slotOverride),
      duration_min: ep.runtime ?? defaultRuntime,
      is_special: ep.season_number === 0, // 시즌 0은 스페셜/예고
    }));
}

// --- 출연진 매핑 ---

export interface PersonRow {
  tmdb_id: number;
  name: string;
  profile_url: string | null;
}

export interface DramaCastRow {
  drama_id: string;
  person_id: string;
  character: string | null;
  display_order: number;
}

/** 드라마당 상위 N명만 저장. order는 작을수록 주연. */
export const MAX_CAST_PER_DRAMA = 12;

export function toPersonRows(cast: TMDBCastMember[]): PersonRow[] {
  return cast
    .filter((c) => c.order < MAX_CAST_PER_DRAMA)
    .map((c) => ({
      tmdb_id: c.id,
      name: c.name || c.original_name,
      profile_url: profileURL(c.profile_path),
    }));
}

export function toCastRows(
  cast: TMDBCastMember[],
  dramaId: string,
  personIdByTmdbId: Map<number, string>
): DramaCastRow[] {
  return cast
    .filter((c) => c.order < MAX_CAST_PER_DRAMA)
    .map((c) => {
      const personId = personIdByTmdbId.get(c.id);
      if (!personId) return null;
      return {
        drama_id: dramaId,
        person_id: personId,
        character: c.character || null,
        display_order: c.order,
      };
    })
    .filter((r): r is DramaCastRow => r !== null);
}

// --- Availability 매핑 ---

export interface AvailabilityRow {
  drama_id: string;
  channel_id: string;
  link: string | null;
}

/**
 * TMDB watch providers (KR · flatrate) → drama_availability 행 변환.
 * 우리 NETWORK_NAME_TO_CODE 매핑 + 채널 ID 룩업으로 매칭. 알 수 없는 provider는 스킵.
 */
export function toAvailabilityRows(
  providers: TMDBWatchProvidersResponse,
  dramaId: string,
  channelMap: Map<string, string>
): AvailabilityRow[] {
  const kr = providers.results.KR;
  const flatrate = kr?.flatrate ?? [];
  if (flatrate.length === 0) return [];
  const link = kr?.link ?? null;
  const rows: AvailabilityRow[] = [];
  const seen = new Set<string>();
  for (const p of flatrate) {
    const code = NETWORK_NAME_TO_CODE[p.provider_name];
    if (!code) continue;
    const channelId = channelMap.get(code);
    if (!channelId) continue;
    if (seen.has(channelId)) continue; // 같은 채널 중복 방지
    seen.add(channelId);
    rows.push({ drama_id: dramaId, channel_id: channelId, link });
  }
  return rows;
}

/** 본방 채널을 availability 에도 항상 기록. (RPC 단순화용) */
export function primaryAvailabilityRow(
  dramaId: string,
  channelId: string
): AvailabilityRow {
  return { drama_id: dramaId, channel_id: channelId, link: null };
}
