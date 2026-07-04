// 채널별 통상 방영 시간 추정.
// TMDB는 air_date (날짜)만 주고 시간(시:분)은 안 줌.
// Week 6+에서 방송사 정밀 크롤로 덮어쓸 예정 — 지금은 한국 드라마 표준 슬롯 기준 추정.

export interface AirSlot {
  hour: number;   // 0-23 (KST)
  minute: number;
}

// 채널 코드 → 기본 방영 시간(KST).
// 실제로는 요일/장르/회차에 따라 다르지만 MVP 추정용.
const DEFAULT_SLOTS: Record<string, AirSlot> = {
  // 지상파
  KBS2: { hour: 22, minute: 0 },
  MBC:  { hour: 22, minute: 0 },
  SBS:  { hour: 22, minute: 0 },
  // 종편 / 케이블
  tvN:  { hour: 21, minute: 0 },
  JTBC: { hour: 22, minute: 30 },
  ENA:  { hour: 21, minute: 0 },
  MBN:  { hour: 21, minute: 50 },
  GENIE_TV: { hour: 21, minute: 0 },
  // OTT — 보통 자정 직후(00:00) 또는 오전 공개. 한국 OTT는 17:00 패턴이 많음.
  // 데이터로 충분히 식별 가능한 시간대 부여.
  NETFLIX:      { hour: 17, minute: 0 },
  DISNEY_PLUS:  { hour: 17, minute: 0 },
  COUPANG_PLAY: { hour: 20, minute: 0 },
  WAVVE:        { hour: 22, minute: 0 },
  TVING:        { hour: 20, minute: 0 },
};

/** 'YYYY-MM-DD' (KST 방영일) → ISO UTC timestamp */
export function estimateAirTimeUTC(
  airDateKST: string,
  channelCode: string
): string {
  const slot = DEFAULT_SLOTS[channelCode] ?? { hour: 22, minute: 0 };
  // KST = UTC+9. air_date가 2026-05-24 22:00 KST 라면 UTC는 2026-05-24 13:00.
  const utcHour = slot.hour - 9;
  // utcHour < 0 이면 전날 UTC가 됨 (예: 06:00 KST = 21:00 UTC 전날).
  // 한국 드라마는 거의 저녁 시간대이므로 음수 안 나옴. 안전망으로만 처리.
  if (utcHour < 0) {
    const d = new Date(`${airDateKST}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() - 1);
    d.setUTCHours(utcHour + 24, slot.minute, 0, 0);
    return d.toISOString();
  }
  const hh = String(utcHour).padStart(2, '0');
  const mm = String(slot.minute).padStart(2, '0');
  return `${airDateKST}T${hh}:${mm}:00Z`;
}
