// Cloudflare Pages Function: 환율 조회 (/api/fxrate)
//
// 전월 말일(마지막 영업일) 기준으로 두 통화를 각각 공식 소스에서 가져옵니다.
//   USD : 한국수출입은행 공개 API — 매매기준율        (환경변수 KOREAEXIM_KEY)
//   RUB : 한국은행 ECOS — 주요국통화의 대원화환율(731Y001) (환경변수 ECOS_KEY)
// 둘 중 못 구한 통화만 시장환율(open.er-api.com)로 보충합니다.
//
// 인증키는 Cloudflare 환경변수(Secret)로 주입됩니다. 코드에 키를 넣지 마세요.
//
// 이력:
//  - 종전 두나무 중계 API(quotation-api-cdn.dunamu.com)는 도메인이 폐지되어
//    항상 실패했고 그 결과 늘 시장환율로 폴백되고 있었음.
//  - 수출입은행은 RUB을 취급하지 않아 RUB만 한국은행에서 가져옴.

const KEB_ENDPOINT = 'https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON';
const ECOS_ENDPOINT = 'https://ecos.bok.or.kr/api/StatisticSearch';
const ECOS_FX_TABLE = '731Y001';   // 주요국통화의 대원화환율 (일별)
const LOOKBACK_DAYS = 8;           // 전월 말일이 휴장일이면 직전 영업일로 되짚는 최대 일수

export async function onRequestGet(context) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'public, max-age=1800'
  };

  const env = context.env || {};
  // srcUsd/srcRub 는 기관 코드('keb'|'ecos'|'market')를 그대로 내보낸다.
  // 화면이 언어에 맞는 이름을 붙이므로 여기서 사람이 읽는 문자열을 만들지 않는다.
  // (source 는 종전 호환용 한국어 문자열)
  const out = { usd: null, rub: null, date: null, type: null, source: null, srcUsd: null, srcRub: null };
  const days = monthEndLookback();
  const sources = [];

  // ── USD: 수출입은행 매매기준율 ──
  if (env.KOREAEXIM_KEY) {
    const hit = await walkBack(days, ymd => fetchKebUsd(env.KOREAEXIM_KEY, ymd));
    if (hit) {
      out.usd = round2(hit.value);
      out.date = hit.date;
      out.srcUsd = 'keb';
      sources.push('USD 수출입은행 매매기준율');
    }
  }

  // ── RUB: 한국은행 ECOS ──
  if (env.ECOS_KEY) {
    const hit = await walkBack(days, ymd => fetchEcosRub(env.ECOS_KEY, ymd));
    if (hit) {
      out.rub = round2(hit.value);
      if (!out.date) out.date = hit.date;
      out.srcRub = 'ecos';
      sources.push('RUB 한국은행');
    }
  }

  if (out.usd || out.rub) out.type = 'month-end';

  // ── 못 구한 통화만 시장환율로 보충 ──
  if (!out.usd || !out.rub) {
    try {
      const r = await fetch('https://open.er-api.com/v6/latest/KRW');
      const j = await r.json();
      if (j && j.rates) {
        if (!out.usd && j.rates.USD) { out.usd = round2(1 / j.rates.USD); out.srcUsd = 'market'; sources.push('USD 시장환율'); }
        if (!out.rub && j.rates.RUB) { out.rub = round2(1 / j.rates.RUB); out.srcRub = 'market'; sources.push('RUB 시장환율'); }
        if (!out.type) out.type = 'market';
      }
    } catch (e) { /* 아래에서 처리 */ }
  }

  out.source = sources.length ? sources.join(' + ') : null;

  if (!out.usd && !out.rub) {
    return new Response(JSON.stringify({ error: 'rate fetch failed' }), { status: 502, headers });
  }
  return new Response(JSON.stringify(out), { headers });
}

// 전월 말일부터 하루씩 거슬러 올라간 날짜 목록 (주말·공휴일 대응)
function monthEndLookback() {
  // Workers 는 UTC 로 도므로 KST(+9) 기준으로 날짜를 잡는다
  const kstNow = new Date(Date.now() + 9 * 3600 * 1000);
  const prevEnd = Date.UTC(kstNow.getUTCFullYear(), kstNow.getUTCMonth(), 0);  // 이번 달 0일 = 전월 말일
  const days = [];
  for (let i = 0; i < LOOKBACK_DAYS; i++) days.push(toYmd(new Date(prevEnd - i * 86400000)));
  return days;
}

// 고시가 나올 때까지 하루씩 되짚으며 fn(ymd) 실행
async function walkBack(days, fn) {
  for (const ymd of days) {
    const value = await fn(ymd);
    if (value !== null && value !== undefined) return { value, date: ymd };
  }
  return null;
}

async function fetchKebUsd(key, ymd) {
  const url = `${KEB_ENDPOINT}?authkey=${encodeURIComponent(key)}&searchdate=${ymd}&data=AP01`;
  try {
    const r = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (fxrate-proxy)' } });
    if (!r.ok) return null;
    const arr = await r.json();
    if (!Array.isArray(arr) || !arr.length) return null;      // 휴장일이면 빈 배열
    // result: 1=성공, 2=DATA코드오류, 3=인증코드오류, 4=일일제한마감
    const row = arr.find(x => Number(x.result) === 1 && String(x.cur_unit || '').toUpperCase().startsWith('USD'));
    if (!row) return null;
    const val = Number(String(row.deal_bas_r || '').replace(/,/g, ''));
    return val > 0 ? val : null;
  } catch (e) {
    return null;   // JSON 이 아닌 응답(점검 페이지 등) 포함
  }
}

// ECOS 731Y001 을 통째로 받아 항목명에 '루블'이 들어간 행을 찾는다.
// (항목코드를 하드코딩하지 않으므로 코드가 바뀌어도 견딤. 취급하지 않으면 자연히 null)
async function fetchEcosRub(key, ymd) {
  const url = `${ECOS_ENDPOINT}/${encodeURIComponent(key)}/json/kr/1/100/${ECOS_FX_TABLE}/D/${ymd}/${ymd}`;
  try {
    const r = await fetch(url);
    if (!r.ok) return null;
    const j = await r.json();
    const rows = j && j.StatisticSearch && j.StatisticSearch.row;
    if (!Array.isArray(rows) || !rows.length) return null;    // 휴장일 또는 RESULT 오류
    const row = rows.find(x => /루블|RUB/i.test(String(x.ITEM_NAME1 || '')));
    if (!row) return null;                                     // 한국은행이 루블을 고시하지 않음
    const val = Number(String(row.DATA_VALUE || '').replace(/,/g, ''));
    return val > 0 ? val : null;
  } catch (e) {
    return null;
  }
}

function toYmd(d) {
  return d.getUTCFullYear()
    + String(d.getUTCMonth() + 1).padStart(2, '0')
    + String(d.getUTCDate()).padStart(2, '0');
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
