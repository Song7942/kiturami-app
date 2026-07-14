// Cloudflare Pages Function: 환율 조회 (/api/fxrate)
// 우선순위:
//  1) 하나은행 고시환율 일봉(두나무 API) → 전월 말일(마지막 영업일)의 시가 = 그날의 최초매매기준율
//  2) 하나은행 고시환율 최신값 (두나무 recent)
//  3) 시장환율 (open.er-api.com)
export async function onRequestGet(context) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'public, max-age=1800'
  };
  const out = { usd: null, rub: null, date: null, type: null, source: null };
  const ua = { headers: { 'User-Agent': 'Mozilla/5.0 (fxrate-proxy)' } };

  // 전월 말일 (YYYY-MM-DD 문자열 비교용)
  const now = new Date();
  const prevEnd = new Date(now.getFullYear(), now.getMonth(), 0); // 지난달 마지막 날
  const prevEndStr = prevEnd.getFullYear() + String(prevEnd.getMonth() + 1).padStart(2, '0') + String(prevEnd.getDate()).padStart(2, '0'); // YYYYMMDD

  // 1) 일봉에서 전월 말일(이전 영업일 포함) 시가 = 최초매매기준율
  async function fromCandles(code) {
    try {
      const r = await fetch(`https://quotation-api-cdn.dunamu.com/v1/forex/candles/days?code=${code}&count=50`, ua);
      if (!r.ok) return null;
      const arr = await r.json();
      if (!Array.isArray(arr) || !arr.length) return null;
      // date 필드는 'yyyyMMdd' 또는 'yyyy-MM-dd' 형태 → 숫자만 비교
      const norm = d => String(d || '').replace(/[^0-9]/g, '').slice(0, 8);
      // 전월 말일 이하 중 가장 최근 영업일 캔들
      const cands = arr.filter(c => norm(c.candleDateTime || c.date) <= prevEndStr)
                       .sort((a, b) => norm(b.candleDateTime || b.date).localeCompare(norm(a.candleDateTime || a.date)));
      const c = cands[0];
      if (!c) return null;
      const open = Number(c.openingPrice);
      if (!(open > 0)) return null;
      const unit = Number(c.currencyUnit) > 1 ? Number(c.currencyUnit) : 1;
      return { price: open / unit, date: norm(c.candleDateTime || c.date) };
    } catch (e) { return null; }
  }

  const [u1, r1] = await Promise.all([fromCandles('FRX.KRWUSD'), fromCandles('FRX.KRWRUB')]);
  if (u1) { out.usd = u1.price; out.date = u1.date; out.type = 'month-end-first'; out.source = '하나은행 전월말일 최초매매기준율'; }
  if (r1) { out.rub = r1.price; if (!out.date) out.date = r1.date; if(!out.type){ out.type='month-end-first'; out.source='하나은행 전월말일 최초매매기준율'; } }

  // 2) 부족한 통화는 최신 고시환율로 보충
  if (!out.usd || !out.rub) {
    try {
      const res = await fetch('https://quotation-api-cdn.dunamu.com/v1/forex/recent?codes=FRX.KRWUSD,FRX.KRWRUB', ua);
      if (res.ok) {
        const arr = await res.json();
        for (const q of arr || []) {
          const unit = Number(q.currencyUnit) > 1 ? Number(q.currencyUnit) : 1;
          if (q.currencyCode === 'USD' && !out.usd && q.basePrice) { out.usd = q.basePrice / unit; out.date = out.date || q.date; }
          if (q.currencyCode === 'RUB' && !out.rub && q.basePrice) { out.rub = q.basePrice / unit; out.date = out.date || q.date; }
        }
        if (out.usd && !out.type) { out.type = 'latest'; out.source = '하나은행 최신 고시환율'; }
      }
    } catch (e) { /* fall through */ }
  }

  // 3) 최후 폴백: 시장환율
  if (!out.usd || !out.rub) {
    try {
      const r2 = await fetch('https://open.er-api.com/v6/latest/KRW');
      const j = await r2.json();
      if (j && j.rates) {
        if (!out.usd && j.rates.USD) out.usd = Math.round((1 / j.rates.USD) * 100) / 100;
        if (!out.rub && j.rates.RUB) out.rub = Math.round((1 / j.rates.RUB) * 100) / 100;
        out.source = out.source ? out.source + ' + 시장환율 보충' : '시장환율(open.er-api.com)';
        if (!out.type) out.type = 'market';
      }
    } catch (e) { /* ignore */ }
  }

  if (!out.usd && !out.rub) {
    return new Response(JSON.stringify({ error: 'rate fetch failed' }), { status: 502, headers });
  }
  return new Response(JSON.stringify(out), { headers });
}
