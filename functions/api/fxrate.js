// Cloudflare Pages Function: 환율 조회 (/api/fxrate)
// 우선순위:
//  1) 한국수출입은행 공개 API → 전월 말일(마지막 영업일)의 매매기준율
//  2) 시장환율 (open.er-api.com) — 1)에서 못 구한 통화만 보충
//
// 인증키는 Cloudflare 환경변수 KOREAEXIM_KEY (Secret) 로 주입됩니다.
// 코드에 키를 넣지 마세요.
//
// 참고: 종전에 쓰던 두나무 중계 API(quotation-api-cdn.dunamu.com)는
//       도메인이 폐지되어 항상 실패했고, 그 결과 늘 시장환율로 폴백되고 있었습니다.

const KEB_ENDPOINT = 'https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON';
const LOOKBACK_DAYS = 8;   // 전월 말일이 주말·공휴일이면 직전 영업일로 되짚는 최대 일수

export async function onRequestGet(context) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'public, max-age=1800'
  };

  const out = { usd: null, rub: null, date: null, type: null, source: null };
  const key = context.env && context.env.KOREAEXIM_KEY;

  // ── 1) 수출입은행: 전월 말일 기준 매매기준율 ──
  if (key) {
    const rows = await fetchMonthEndRates(key);
    if (rows) {
      const usd = pickRate(rows.data, 'USD');
      const rub = pickRate(rows.data, 'RUB');
      if (usd) out.usd = round2(usd);
      if (rub) out.rub = round2(rub);
      if (out.usd || out.rub) {
        out.date = rows.date;
        out.type = 'month-end';
        out.source = '수출입은행 전월말일 매매기준율';
      }
    }
  }

  // ── 2) 시장환율로 부족한 통화 보충 ──
  if (!out.usd || !out.rub) {
    try {
      const r = await fetch('https://open.er-api.com/v6/latest/KRW');
      const j = await r.json();
      if (j && j.rates) {
        if (!out.usd && j.rates.USD) out.usd = round2(1 / j.rates.USD);
        if (!out.rub && j.rates.RUB) out.rub = round2(1 / j.rates.RUB);
        out.source = out.source
          ? out.source + ' + 시장환율 보충'
          : '시장환율(open.er-api.com)';
        if (!out.type) out.type = 'market';
      }
    } catch (e) { /* 아래에서 처리 */ }
  }

  if (!out.usd && !out.rub) {
    return new Response(JSON.stringify({ error: 'rate fetch failed' }), { status: 502, headers });
  }
  return new Response(JSON.stringify(out), { headers });
}

// 전월 말일부터 최대 LOOKBACK_DAYS 일 거슬러 올라가며 고시가 있는 날을 찾는다.
// (주말·공휴일에는 수출입은행이 빈 배열을 돌려줌)
async function fetchMonthEndRates(key) {
  // Workers 는 UTC 로 도므로 KST(+9) 기준으로 날짜를 잡는다
  const kstNow = new Date(Date.now() + 9 * 3600 * 1000);
  // 이번 달 0일 = 전월 말일
  const prevEnd = Date.UTC(kstNow.getUTCFullYear(), kstNow.getUTCMonth(), 0);

  for (let i = 0; i < LOOKBACK_DAYS; i++) {
    const d = new Date(prevEnd - i * 86400000);
    const ymd = toYmd(d);
    const data = await fetchKeb(key, ymd);
    if (data) return { data, date: ymd };
  }
  return null;
}

async function fetchKeb(key, ymd) {
  const url = `${KEB_ENDPOINT}?authkey=${encodeURIComponent(key)}&searchdate=${ymd}&data=AP01`;
  try {
    const r = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (fxrate-proxy)' } });
    if (!r.ok) return null;
    const arr = await r.json();
    if (!Array.isArray(arr) || !arr.length) return null;   // 휴장일이면 빈 배열
    // result: 1=성공, 2=DATA코드오류, 3=인증코드오류, 4=일일제한마감
    const ok = arr.filter(x => Number(x.result) === 1);
    return ok.length ? ok : null;
  } catch (e) {
    return null;   // JSON 이 아닌 응답(점검 페이지 등) 포함
  }
}

// cur_unit 은 'USD', 'JPY(100)' 처럼 100단위 표기가 붙는 통화가 있어 1단위로 환산한다.
function pickRate(rows, code) {
  const row = rows.find(x => String(x.cur_unit || '').toUpperCase().startsWith(code));
  if (!row) return null;                                   // 취급하지 않는 통화
  const val = Number(String(row.deal_bas_r || '').replace(/,/g, ''));
  if (!(val > 0)) return null;
  const m = String(row.cur_unit).match(/\((\d+)\)/);
  const unit = m ? Number(m[1]) : 1;
  return unit > 1 ? val / unit : val;
}

function toYmd(d) {
  return d.getUTCFullYear()
    + String(d.getUTCMonth() + 1).padStart(2, '0')
    + String(d.getUTCDate()).padStart(2, '0');
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
