// TMDB API 클라이언트 — 한국 드라마 디스커버 + 상세 + 시즌.
// 인증: v4 Bearer Token (헤더 Authorization: Bearer ...).
// Rate limit: 40 requests / 10s. throttle()로 250ms 간격 유지.

const TMDB_BASE = 'https://api.themoviedb.org/3';
const TMDB_IMG_BASE = 'https://image.tmdb.org/t/p/w500';

let lastRequestAt = 0;
const MIN_INTERVAL_MS = 250;

async function throttle(): Promise<void> {
  const elapsed = Date.now() - lastRequestAt;
  if (elapsed < MIN_INTERVAL_MS) {
    await new Promise((r) => setTimeout(r, MIN_INTERVAL_MS - elapsed));
  }
  lastRequestAt = Date.now();
}

async function tmdbFetch<T>(path: string, token: string): Promise<T> {
  await throttle();
  const url = `${TMDB_BASE}${path}`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`TMDB ${res.status} on ${path}: ${body.slice(0, 200)}`);
  }
  return res.json() as Promise<T>;
}

// --- 응답 타입 (필요한 필드만) ---

export interface TMDBDiscoverResponse {
  page: number;
  total_pages: number;
  total_results: number;
  results: TMDBTVSummary[];
}

export interface TMDBTVSummary {
  id: number;
  name: string;
  original_name: string;
  overview: string;
  poster_path: string | null;
  first_air_date: string; // 'YYYY-MM-DD'
  origin_country: string[];
  original_language: string;
}

export interface TMDBTVDetail {
  id: number;
  name: string;
  original_name: string;
  overview: string;
  poster_path: string | null;
  first_air_date: string | null;
  last_air_date: string | null;
  status: string; // "Returning Series" | "Ended" | "In Production" | ...
  number_of_episodes: number | null;
  number_of_seasons: number;
  episode_run_time: number[];
  networks: TMDBNetwork[];
  seasons: TMDBSeasonSummary[];
}

export interface TMDBNetwork {
  id: number;
  name: string;
  origin_country: string;
}

export interface TMDBSeasonSummary {
  season_number: number;
  episode_count: number;
  air_date: string | null;
}

export interface TMDBSeasonDetail {
  season_number: number;
  episodes: TMDBEpisode[];
}

export interface TMDBEpisode {
  id: number;
  episode_number: number;
  season_number: number;
  name: string;
  air_date: string | null; // 'YYYY-MM-DD' (KST 기준 방영일)
  runtime: number | null;
}

// --- 공개 API ---

export async function discoverKoreanDramas(
  token: string,
  page: number,
  options: { startDate?: string } = {}
): Promise<TMDBDiscoverResponse> {
  // 드라마 장르(18) + 한국 + 한국어 + 최신 방영일 순.
  // language=ko-KR: 응답의 name/overview를 한국어로.
  // startDate: 'YYYY-MM-DD' — 해당 일자 이후 첫방한 드라마만.
  const params = new URLSearchParams({
    with_origin_country: 'KR',
    with_original_language: 'ko',
    with_genres: '18',
    sort_by: 'first_air_date.desc',
    language: 'ko-KR',
    page: String(page),
  });
  if (options.startDate) {
    params.set('first_air_date.gte', options.startDate);
  }
  return tmdbFetch<TMDBDiscoverResponse>(`/discover/tv?${params}`, token);
}

export async function getTVDetail(
  token: string,
  id: number
): Promise<TMDBTVDetail> {
  return tmdbFetch<TMDBTVDetail>(`/tv/${id}?language=ko-KR`, token);
}

export async function getSeasonDetail(
  token: string,
  tvId: number,
  seasonNumber: number
): Promise<TMDBSeasonDetail> {
  return tmdbFetch<TMDBSeasonDetail>(
    `/tv/${tvId}/season/${seasonNumber}?language=ko-KR`,
    token
  );
}

export function posterURL(posterPath: string | null): string | null {
  if (!posterPath) return null;
  return `${TMDB_IMG_BASE}${posterPath}`;
}

const TMDB_PROFILE_BASE = 'https://image.tmdb.org/t/p/w185';

export function profileURL(profilePath: string | null): string | null {
  if (!profilePath) return null;
  return `${TMDB_PROFILE_BASE}${profilePath}`;
}

// --- Credits (출연진) ---

export interface TMDBCreditsResponse {
  cast: TMDBCastMember[];
  crew: TMDBCrewMember[];
}

export interface TMDBCastMember {
  id: number;
  name: string;
  original_name: string;
  character: string;
  profile_path: string | null;
  order: number;
}

export interface TMDBCrewMember {
  id: number;
  name: string;
  job: string;
  department: string;
}

export async function getTVCredits(
  token: string,
  tvId: number
): Promise<TMDBCreditsResponse> {
  return tmdbFetch<TMDBCreditsResponse>(
    `/tv/${tvId}/credits?language=ko-KR`,
    token
  );
}

// --- Watch providers (다시보기 가능 OTT) ---

export interface TMDBWatchProvidersResponse {
  id: number;
  results: Record<string, TMDBCountryProviders | undefined>;
}

export interface TMDBCountryProviders {
  link?: string;
  flatrate?: TMDBProvider[]; // 구독 스트리밍
  rent?: TMDBProvider[];
  buy?: TMDBProvider[];
}

export interface TMDBProvider {
  provider_id: number;
  provider_name: string;
  logo_path: string | null;
}

export async function getWatchProviders(
  token: string,
  tvId: number
): Promise<TMDBWatchProvidersResponse> {
  return tmdbFetch<TMDBWatchProvidersResponse>(
    `/tv/${tvId}/watch/providers`,
    token
  );
}
