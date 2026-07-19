// DramaApp 크롤러 메인 엔트리.
// 흐름: TMDB discover → 각 TV 상세 + 시즌 → 우리 스키마 upsert.

import 'dotenv/config';
import {
  discoverKoreanDramas,
  getTVDetail,
  getSeasonDetail,
  getTVCredits,
  getWatchProviders,
} from './tmdb.js';
import {
  loadChannelMap,
  makeClient,
  upsertDrama,
  upsertEpisodes,
  upsertPersonsAndGetIDs,
  upsertDramaCasts,
  upsertAvailability,
  getAirTimeOverride,
  setAirTimeOverride,
} from './supabase.js';
import { fetchNaverAirTime } from './naver.js';
import {
  pickChannelCode,
  toDramaRow,
  toEpisodeRows,
  toPersonRows,
  toCastRows,
  toAvailabilityRows,
  primaryAvailabilityRow,
} from './mapping.js';

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v || v.trim() === '') {
    throw new Error(`환경변수 ${key} 가 비어 있음. crawler/.env 확인.`);
  }
  const trimmed = v.trim();
  // HTTP 헤더/URL에는 ASCII 만 허용됨. 한글/공백/따옴표 등이 섞여 들어오면
  // fetch 단계에서 난해한 ByteString 오류로 죽으므로 사전 차단.
  for (let i = 0; i < trimmed.length; i++) {
    const code = trimmed.charCodeAt(i);
    if (code > 126 || code < 32) {
      throw new Error(
        `환경변수 ${key} 에 비 ASCII 문자가 포함됨 (위치 ${i}, 코드 ${code}). ` +
        `Supabase/TMDB 값을 복사할 때 안내 문구/한글 IME 입력이 섞였을 가능성. ` +
        `해당 Secret 을 삭제 후 원본 위치에서 복사 아이콘으로 재등록하세요.`
      );
    }
  }
  return trimmed;
}

async function main(): Promise<void> {
  const supabaseUrl = requireEnv('SUPABASE_URL');
  const serviceKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  const tmdbToken = requireEnv('TMDB_BEARER_TOKEN');
  // CRAWL_MAX_PAGES: 안전 상한 (TMDB total_pages 보다 이게 작으면 여기서 끊김)
  // CRAWL_PAGES: legacy 호환 (구버전 .env)
  const maxPages = Math.max(
    1,
    Math.min(500, Number(
      process.env.CRAWL_MAX_PAGES ?? process.env.CRAWL_PAGES ?? 50
    ))
  );
  // CRAWL_START_DATE: 'YYYY-MM-DD' — 이 날짜 이후 첫방한 드라마만. 빈 값 = 전체.
  const startDate = process.env.CRAWL_START_DATE?.trim() || undefined;

  console.log(`[init] Supabase URL: ${supabaseUrl}`);
  console.log(`[init] 시작일 필터: ${startDate ?? '없음'} · 최대 페이지: ${maxPages}\n`);

  const client = makeClient(supabaseUrl, serviceKey);
  const channelMap = await loadChannelMap(client);
  console.log(`[init] 채널 로드 완료: ${[...channelMap.keys()].join(', ')}\n`);

  let totalDramas = 0;
  let totalEpisodes = 0;
  let totalCasts = 0;
  let totalAvailability = 0;
  let skipped = 0;
  let failed = 0;

  // 첫 페이지로 total_pages 파악 후 min(total_pages, maxPages) 까지 진행.
  let page = 1;
  let totalPages = 1;
  while (page <= Math.min(maxPages, totalPages)) {
    console.log(`[discover] page ${page}/${Math.min(maxPages, totalPages)}`);
    const discover = await discoverKoreanDramas(tmdbToken, page, { startDate });
    if (page === 1) {
      totalPages = discover.total_pages;
      console.log(`  TMDB 전체 ${totalPages} 페이지 · ${discover.total_results}건 매칭\n`);
    }

    for (const summary of discover.results) {
      try {
        const detail = await getTVDetail(tmdbToken, summary.id);
        const channelCode = pickChannelCode(detail.networks);

        if (!channelCode) {
          console.log(
            `  ⊘ skip ${detail.name} — 알 수 없는 네트워크 [${detail.networks
              .map((n) => n.name)
              .join(', ')}]`
          );
          skipped++;
          continue;
        }
        const channelId = channelMap.get(channelCode);
        if (!channelId) {
          console.log(`  ⊘ skip ${detail.name} — channel code "${channelCode}" not in DB`);
          skipped++;
          continue;
        }

        const dramaRow = toDramaRow(detail, channelId);
        const dramaId = await upsertDrama(client, dramaRow);
        totalDramas++;

        // 시즌 1만 처리 (한국 드라마는 보통 단일 시즌).
        // 시즌 0(스페셜)은 스킵.
        const season1 = detail.seasons.find((s) => s.season_number === 1);
        let epCount = 0;
        if (season1 && season1.episode_count > 0) {
          const seasonDetail = await getSeasonDetail(tmdbToken, detail.id, 1);
          const defaultRuntime = detail.episode_run_time[0] ?? 70;
          // 드라마별 시간 오버라이드가 세팅돼 있으면 채널 기본값 대신 사용.
          // 세팅 안 돼 있으면 Naver 검색으로 자동 추출 시도 후 영속화.
          let override = await getAirTimeOverride(client, dramaId);
          if (!override) {
            const naver = await fetchNaverAirTime(detail.name);
            if (naver) {
              await setAirTimeOverride(client, dramaId, naver.hour, naver.minute);
              override = { hour: naver.hour, minute: naver.minute };
              const mm = String(naver.minute).padStart(2, '0');
              console.log(
                `    ⏰ Naver 방영시간 → ${naver.hour}:${mm}  (raw: "${naver.raw}")`
              );
            }
            // Naver 실패해도 크롤은 계속 진행. 채널 기본값 fallback.
            await new Promise((r) => setTimeout(r, 300)); // rate limit
          }
          const epRows = toEpisodeRows(
            seasonDetail.episodes,
            dramaId,
            channelCode,
            defaultRuntime,
            override
          );
          epCount = await upsertEpisodes(client, epRows);
          totalEpisodes += epCount;
        }

        // 출연진. 실패해도 드라마 자체는 진행.
        let castCount = 0;
        try {
          const credits = await getTVCredits(tmdbToken, detail.id);
          const personRows = toPersonRows(credits.cast);
          if (personRows.length > 0) {
            const personIdMap = await upsertPersonsAndGetIDs(client, personRows);
            const castRows = toCastRows(credits.cast, dramaId, personIdMap);
            castCount = await upsertDramaCasts(client, castRows);
            totalCasts += castCount;
          }
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          console.warn(`    ⚠ cast 수집 실패 — ${msg}`);
        }

        // Availability: 본방 채널 + TMDB watch providers(KR/flatrate).
        let availCount = 0;
        try {
          const rows = [primaryAvailabilityRow(dramaId, channelId)];
          const providers = await getWatchProviders(tmdbToken, detail.id);
          const ottRows = toAvailabilityRows(providers, dramaId, channelMap);
          rows.push(...ottRows);
          availCount = await upsertAvailability(client, rows);
          totalAvailability += availCount;
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          console.warn(`    ⚠ availability 수집 실패 — ${msg}`);
        }

        const ottBadge = availCount > 1 ? ` · 다시보기 ${availCount - 1}곳` : '';
        console.log(
          `  ✓ ${detail.name} [${channelCode}] · 회차 ${epCount}건 · 출연 ${castCount}명${ottBadge}`
        );
      } catch (err) {
        failed++;
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`  ✗ ${summary.name} (tmdb_id=${summary.id}): ${msg}`);
      }
    }
    console.log('');
    page++;
  }

  console.log('═══════════════════════════════════════');
  console.log(
    `완료. 드라마: ${totalDramas} · 회차: ${totalEpisodes} · 출연: ${totalCasts} · availability: ${totalAvailability}`
  );
  console.log(`스킵: ${skipped} (알 수 없는 네트워크), 실패: ${failed}`);
  console.log('═══════════════════════════════════════');
}

main().catch((err) => {
  console.error('\n[FATAL]', err);
  process.exit(1);
});
