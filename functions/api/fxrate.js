// Cloudflare Pages Function: 하나은행 고시 매매기준율 중계
// GET /api/fxrate → { usd, rub, date, source }
// 하나은행은 공개 API가 없어, 하나은행 고시환율을 제공하는 두나무 환율 API를 서버측에서 중계합니다.
export async function onRequestGet(context) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'public, max-age=1800'
  };
  const out = { usd: null, rub: null, date: null, round: null, source: null };
  try {
    const res = await fetch('https://quotation-api-cdn.dunamu.com/v1/forex/recent?codes=FRX.KRWUSD,FRX.KRWRUB', {
      headers: { 'User-Agent': 'Mozilla/5.0 (fxrate-proxy)' }
    });
    if (res.ok) {
      const arr = await res.json();
      for (const q of arr || []) {
        if (q.currencyCode === 'USD' && q.basePrice) { out.usd = q.basePrice; out.date = q.date; out.round = q.recurrenceCount; }
        if (q.currencyCode === 'RUB' && q.basePrice) {
          // 두나무 RUB은 100루블 단위 고시일 수 있음 → 1루블 기준으로 환산
          out.rub = q.currencyUnit && q.currencyUnit > 1 ? q.basePrice / q.currencyUnit : q.basePrice;
          if (!out.date) out.date = q.date;
        }
      }
      if (out.usd) out.source = '하나은행 고시환율(두나무 API)';
    }
  } catch (e) { /* fall through */ }
  // RUB 미고시 대비 폴백: 시장환율 교차 계산
  if (!out.usd || !out.rub) {
    try {
      const r2 = await fetch('https://open.er-api.com/v6/latest/KRW');
      const j = await r2.json();
      if (j && j.rates) {
        if (!out.usd && j.rates.USD) out.usd = Math.round((1 / j.rates.USD) * 100) / 100;
        if (!out.rub && j.rates.RUB) out.rub = Math.round((1 / j.rates.RUB) * 100) / 100;
        out.source = out.source ? out.source + ' + 시장환율(RUB)' : '시장환율(open.er-api.com)';
      }
    } catch (e) { /* ignore */ }
  }
  if (!out.usd && !out.rub) {
    return new Response(JSON.stringify({ error: 'rate fetch failed' }), { status: 502, headers });
  }
  return new Response(JSON.stringify(out), { headers });
}
