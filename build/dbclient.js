/* ══ 내 서버의 자료를 쓰는 연결부 ══════════════════════════════════
   화면은 종전 그대로 sb.from('표').select()... 를 부르고,
   이 연결부가 그것을 api/db.php 로 보냅니다. 클라우드로 나가는 길은 없습니다.
   로그인은 api/auth.php 가 서버에서 맞춰 보므로 비밀번호 해시가 브라우저로 오지 않습니다. */
(function () {
  var API = 'api/db.php';
  var AUTH = 'api/auth.php';

  function post(url, body) {
    return fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
      body: JSON.stringify(body)
    }).then(function (r) { return r.json().catch(function () { return { error: { message: 'bad response' } }; }); })
      .catch(function (e) { return { data: null, error: { message: String(e && e.message || e) } }; });
  }

  /* supabase-js 의 이어 부르기(체인)를 흉내 낸다 */
  function builder(table) {
    var q = { t: table, op: 'select', cols: '*', filters: [], order: [], limit: 0, offset: 0, single: false, rows: null };
    var sent = null;

    function run() {
      if (!sent) sent = post(API, q).then(function (r) {
        if (r && r.error) return { data: (r.data !== undefined ? r.data : null), error: r.error, count: r.count };
        return { data: (r && r.data !== undefined) ? r.data : null, error: null, count: r ? r.count : 0 };
      });
      return sent;
    }

    var B = {
      select: function (cols, opt) { if (q.op === 'select') { q.cols = cols || '*'; } return B; },
      eq:    function (c, v) { q.filters.push(['eq', c, v]); return B; },
      neq:   function (c, v) { q.filters.push(['neq', c, v]); return B; },
      gt:    function (c, v) { q.filters.push(['gt', c, v]); return B; },
      gte:   function (c, v) { q.filters.push(['gte', c, v]); return B; },
      lt:    function (c, v) { q.filters.push(['lt', c, v]); return B; },
      lte:   function (c, v) { q.filters.push(['lte', c, v]); return B; },
      like:  function (c, v) { q.filters.push(['like', c, v]); return B; },
      ilike: function (c, v) { q.filters.push(['ilike', c, v]); return B; },
      in:    function (c, a) { q.filters.push(['in', c, a || []]); return B; },
      is:    function (c, v) { q.filters.push([v === null ? 'isnull' : 'eq', c, v]); return B; },
      not:   function (c, op, v) { q.filters.push((op === 'is' && v === null) ? ['isnotnull', c] : ['neq', c, v]); return B; },
      order: function (c, o) { q.order.push([c, !(o && o.ascending === false)]); return B; },
      limit: function (n) { q.limit = n; return B; },
      range: function (a, b) { q.offset = a; q.limit = (b - a + 1); return B; },
      maybeSingle: function () { q.single = true; return B; },
      single:      function () { q.single = true; return B; },
      insert: function (rows) { q.op = 'insert'; q.rows = rows; return B; },
      upsert: function (rows, opt) { q.op = 'upsert'; q.rows = rows; if (opt && opt.onConflict) q.onConflict = opt.onConflict; return B; },
      update: function (row) { q.op = 'update'; q.rows = row; return B; },
      delete: function () { q.op = 'delete'; return B; },
      then: function (res, rej) { return run().then(res, rej); },
      catch: function (f) { return run().catch(f); },
      finally: function (f) { return run().then(function (r) { try { f(); } catch (e) {} return r; }); }
    };
    return B;
  }

  window.supabase = {
    createClient: function () {
      return {
        from: function (t) { return builder(t); },
        channel: function () { return { on: function () { return this; }, subscribe: function () { return this; } }; },
        removeChannel: function () {},
        auth: { getUser: function () { return Promise.resolve({ data: { user: null } }); } }
      };
    }
  };

  /* 로그인·로그아웃은 서버로 */
  window.addEventListener('load', function () {
    if (typeof window.doLogin === 'function' && !window.doLogin.__ktSrv) {
      var login = function () {
        var idEl = document.getElementById('loginId'), pwEl = document.getElementById('loginPw');
        var id = idEl ? idEl.value.trim() : '', pw = pwEl ? pwEl.value : '';
        var say = function (m) { try { authSetErr('authLoginErr', m); } catch (e) { alert(m); } };
        var T = (typeof AUTH_T !== 'undefined' && typeof authLang !== 'undefined') ? AUTH_T[authLang] : null;
        return post(AUTH, { op: 'login', id: id, pw: pw }).then(function (r) {
          if (r && r.ok && r.user) {
            try { sessionStorage.setItem('kt_session', JSON.stringify(r.user)); } catch (e) {}
            enterApp(r.user);
            return;
          }
          var why = r ? r.reason : 'error';
          if (why === 'pending')  return say((T && T.errPending) ? T.errPending(r.supplier || '') : '가입 승인 대기 중입니다.');
          if (why === 'rejected') return say((T && T.errRejected) || '가입 신청이 거부되었습니다.');
          say((T && T.errLogin) || '아이디 또는 비밀번호가 맞지 않습니다.');
        });
      };
      login.__ktSrv = true;
      window.doLogin = login;
    }
    if (typeof window.doLogout === 'function' && !window.doLogout.__ktSrv) {
      var orig = window.doLogout;
      var out = function () { try { post(AUTH, { op: 'logout' }); } catch (e) {} return orig.apply(this, arguments); };
      out.__ktSrv = true;
      window.doLogout = out;
    }
  });
})();
