// Cloudflare Pages Function: 메일 보내기 (/api/notify)
//
// 발주시뮬레이션에서 '재가' 를 누르면 이 길로 메일 한 통을 보냅니다.
// 보내는 일만 하고, 무엇을 보낼지는 부르는 쪽(index.html)이 정합니다.
//
// 필요한 환경변수(Cloudflare Pages > Settings > Environment variables):
//   RESEND_API_KEY : Resend(https://resend.com) 의 API 키   — 필수
//   NOTIFY_FROM    : 보내는 사람. 예) KITURAMI <noreply@보유도메인>  — 필수
//                    (Resend 에서 도메인 인증을 마친 주소여야 합니다)
//   NOTIFY_TO      : 기본 받는 사람. 부르는 쪽이 to 를 주면 그것을 씁니다.  — 선택
//
// 키가 없으면 메일을 보내지 않고 {ok:false, reason:'no_key'} 를 돌려줍니다.
// 부르는 쪽은 이 답을 보고 '메일은 못 보냈지만 재가는 되었다' 고 알립니다.

const MAX_LEN = 20000;

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status: status || 200,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }
  });
}

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export async function onRequestPost(context) {
  const { request, env } = context;

  let body;
  try { body = await request.json(); }
  catch (e) { return json({ ok: false, reason: 'bad_json' }, 400); }

  const subject = String(body.subject || '').slice(0, 200).trim();
  const text = String(body.text || '').slice(0, MAX_LEN);
  const to = String(body.to || env.NOTIFY_TO || '').slice(0, 300).trim();

  if (!subject) return json({ ok: false, reason: 'no_subject' }, 400);
  if (!to || to.indexOf('@') < 0) return json({ ok: false, reason: 'no_to' }, 400);

  const key = env.RESEND_API_KEY;
  const from = env.NOTIFY_FROM;
  if (!key || !from) return json({ ok: false, reason: 'no_key' });

  const html = '<div style="font-family:system-ui,-apple-system,Segoe UI,sans-serif;font-size:13px;'
    + 'line-height:1.6;white-space:pre-line">' + esc(text) + '</div>';

  try {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: from,
        to: to.split(',').map(s => s.trim()).filter(Boolean),
        subject: subject,
        text: text,
        html: html
      })
    });
    const out = await r.text();
    if (!r.ok) return json({ ok: false, reason: 'send_failed', status: r.status, detail: out.slice(0, 400) });
    return json({ ok: true, detail: out.slice(0, 200) });
  } catch (e) {
    return json({ ok: false, reason: 'error', detail: String(e && e.message || e).slice(0, 300) });
  }
}

// 설정이 되어 있는지 확인용 (키 값은 절대 돌려주지 않습니다)
export async function onRequestGet(context) {
  const { env } = context;
  return json({ ok: true, ready: !!(env.RESEND_API_KEY && env.NOTIFY_FROM),
                to: env.NOTIFY_TO ? 'set' : 'unset' });
}
