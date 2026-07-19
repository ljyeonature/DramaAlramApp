// 네이버 통합검색 결과에서 드라마 방영시간을 추출.
// TMDB 가 시간 정보를 주지 않아서 HTML 스크래핑으로 보완.
// - 공식 API 아님 (Search API 는 방영시간 필드 없음). 개인 프로젝트 규모에서만 사용.
// - HTML 구조가 바뀌면 파서가 깨질 수 있음. keyword 앵커링("방영시간"/"편성")으로 완충.
// - 실패는 조용히 null 반환 → 채널 기본값 fallback.

export interface NaverAirTime {
  hour: number;
  minute: number;
  raw: string; // 디버깅용 원본 매칭 문자열
}

const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

/**
 * `<제목> 드라마 방영` 으로 네이버 검색 → HTML 텍스트에서 시간 추출.
 * 발견 못 하면 null.
 */
export async function fetchNaverAirTime(title: string): Promise<NaverAirTime | null> {
  const query = encodeURIComponent(`${title} 드라마 방영`);
  const url = `https://search.naver.com/search.naver?where=nexearch&query=${query}`;
  try {
    const res = await fetch(url, {
      headers: {
        'User-Agent': UA,
        'Accept-Language': 'ko-KR,ko;q=0.9',
      },
    });
    if (!res.ok) return null;
    const html = await res.text();
    // HTML 태그 제거 후 텍스트 기반 파싱 — cheerio 없이 최소 의존성.
    const text = stripTags(html);
    return parseAirTimeText(text);
  } catch {
    return null;
  }
}

/**
 * HTML → plain text. `<script>` / `<style>` 제거 후 태그 스트립.
 * 정확한 DOM 파싱은 아니지만 keyword 앵커 조합엔 충분.
 */
export function stripTags(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ');
}

/**
 * 텍스트에서 시간 패턴 추출.
 * 전략 순서 (신뢰도 높은 것 우선):
 *   1) "방영시간|편성시간|방송시간" 앵커 근처 시간 표기
 *   2) 앵커 없으면 → 강한 패턴 "요일(+요일...) (오전|오후|밤|저녁) N시"
 *   3) 앵커 근처 HH:MM 24시간 표기
 *
 * 앵커 우선: 페이지 상단·광고·댓글에 흘러다니는 "N시" 오탐 회피.
 * 강한 패턴 fallback: 앵커가 없는 페이지에서도 드라마 정보 카드 형식은 잡음.
 */
export function parseAirTimeText(text: string): NaverAirTime | null {
  const periodPattern =
    /(오전|오후|밤|저녁|낮|아침)\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?/;

  // 1) 앵커 스코프.
  const anchor = text.search(/방영\s*시간|편성\s*시간|방송\s*시간/);
  if (anchor >= 0) {
    const window = text.slice(anchor, anchor + 300);
    const p = window.match(periodPattern);
    if (p) {
      const parsed = normalizePeriodTime(p[1], p[2], p[3]);
      if (parsed) return { ...parsed, raw: p[0].trim() };
    }
    // 3) 앵커 근처 HH:MM.
    const hhmm = window.match(/(?<!\d)(\d{1,2}):(\d{2})(?!\d)/);
    if (hhmm) {
      const h = parseInt(hhmm[1], 10);
      const min = parseInt(hhmm[2], 10);
      if (validateTime(h, min)) return { hour: h, minute: min, raw: hhmm[0] };
    }
  }

  // 2) 앵커 없음 → 요일+시간 강한 패턴으로 fallback.
  //    "토일 오후 9시" / "매주 월,화 오후 10시" / "월요일 저녁 8시 30분"
  const weekdayPattern =
    /(?:매주\s*)?(?:월|화|수|목|금|토|일)(?:[·,\s]*(?:월|화|수|목|금|토|일))*(?:요일)?\s*(오전|오후|밤|저녁|낮|아침)\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?/;
  const w = text.match(weekdayPattern);
  if (w) {
    const parsed = normalizePeriodTime(w[1], w[2], w[3]);
    if (parsed) return { ...parsed, raw: w[0].trim() };
  }

  return null;
}

/** 오전/오후/밤/저녁 표기를 24시간 hour 로 정규화. 실패 시 null. */
function normalizePeriodTime(
  period: string,
  hourRaw: string,
  minuteRaw?: string
): { hour: number; minute: number } | null {
  let h = parseInt(hourRaw, 10);
  const min = minuteRaw ? parseInt(minuteRaw, 10) : 0;
  // 오후/밤/저녁: 12 오프셋. 오후 12시는 그대로 (정오).
  if ((period === '오후' || period === '밤' || period === '저녁') && h < 12) {
    h += 12;
  }
  // 오전 12시 = 자정 = 0시.
  if (period === '오전' && h === 12) h = 0;
  return validateTime(h, min) ? { hour: h, minute: min } : null;
}

function validateTime(h: number, m: number): boolean {
  return h >= 0 && h <= 23 && m >= 0 && m < 60;
}
