/* ══ 임시판: 가격정보 '자료'만 비운다 ══
   화면과 기능은 그대로 두고, 가격 표만 빈 채로 열리게 한다.
   Supabase 로 오가는 길목에서 가격 표만 막으므로 본체 코드는 건드리지 않는다.
   · kt_prices · kt_price_calc · kt_price_settings  → 늘 빈 결과, 쓰기도 삼킨다
   · kt_company_prices → 권한 줄(@PERMS)만 통과. 회사별 가격 줄은 읽기·쓰기 모두 막는다
   (클라우드의 자료는 그대로 있다. 이 파일에서만 안 보이는 것이다.)                   */
(function () {
  if (!window.supabase || !window.supabase.createClient) return;
  var EMPTY = /^kt_(prices|price_calc|price_settings)$/;
  var PERMT = 'kt_company_prices';
  var WRITES = ['upsert', 'insert', 'update', 'delete'];
  /* 읽을 때: 권한 줄(@PERMS)만 통과.
     권한을 읽는 곳은 select('rep,buy_price') 라 company 칸이 아예 없으므로 그것도 통과시킨다.
     (가격을 읽는 곳들은 company 를 함께 뽑으므로 여기서 걸린다) */
  var keepRead  = function (x) { return !!x && (x.company === undefined || x.company === '@PERMS'); };
  /* 쓸 때: company 를 반드시 적어 보내므로 '@PERMS' 인 줄만 통과 */
  var keepWrite = function (x) { return !!x && x.company === '@PERMS'; };

  /* 늘 비어 있는 흉내 — 이어 부르기(체인)를 모두 받아 준다 */
  function emptyB() {
    var s = {};
    ['select', 'eq', 'neq', 'in', 'is', 'ilike', 'like', 'gt', 'gte', 'lt', 'lte', 'order',
     'limit', 'range', 'not', 'or', 'filter', 'contains', 'match', 'abortSignal', 'csv'
    ].forEach(function (m) { s[m] = function () { return s; }; });
    s.single = s.maybeSingle = function () { s.__one = true; return s; };
    WRITES.forEach(function (m) { s[m] = function () { return s; }; });
    s.then = function (res, rej) {
      return Promise.resolve({ data: s.__one ? null : [], error: null, count: 0 }).then(res, rej);
    };
    s.catch = function (f) { return s.then(null, f); };
    return s;
  }

  /* 권한 줄만 오가게 하는 감싸개 */
  function wrapB(b) {
    return new Proxy(b, {
      get: function (t, k) {
        if (k === 'then') {
          return function (res, rej) {
            return t.then(function (r) {
              if (r && Array.isArray(r.data)) r = { data: r.data.filter(keepRead), error: r.error, count: r.count };
              return res ? res(r) : r;
            }, rej);
          };
        }
        var v = t[k];
        if (typeof v === 'function') {
          if (WRITES.indexOf(k) >= 0) {
            return function (val, opt) {
              if (k === 'delete') return emptyB();                    /* 가격 지우기는 삼킨다 */
              var arr = Array.isArray(val) ? val : [val];
              var keep = arr.filter(keepWrite);
              if (!keep.length) return emptyB();
              var out = v.call(t, Array.isArray(val) ? keep : keep[0], opt);
              return (out && typeof out.then === 'function') ? wrapB(out) : out;
            };
          }
          return function () {
            var o = v.apply(t, arguments);
            return (o && typeof o === 'object' && typeof o.then === 'function') ? wrapB(o) : o;
          };
        }
        return v;
      }
    });
  }

  var orig = window.supabase.createClient;
  window.supabase.createClient = function () {
    var c = orig.apply(this, arguments);
    var from = c.from.bind(c);
    c.from = function (t) {
      if (EMPTY.test(t)) return emptyB();
      if (t === PERMT) return wrapB(from(t));
      return from(t);
    };
    return c;
  };
})();
