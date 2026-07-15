-- ═══════════════════════════════════════════════════════════════
-- KITURAMI 서비스 — 회사별 가격정보 · 품번조회 업로드 · 신규 계정
-- Supabase 대시보드 → SQL Editor 에 붙여넣고 실행하세요.
-- 여러 번 실행해도 안전합니다 (IF NOT EXISTS / ON CONFLICT).
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────
-- 1) 회사별 가격정보
--    회사명 단위로 대표품번별 구매가/공급가를 저장한다.
--    GP 는 저장하지 않고 (공급가-구매가)/공급가 로 화면에서 계산한다.
--    buy_price 가 NULL 이면 구매처의 공급가를 자동으로 가져와 표시한다
--    (직접 입력하면 그 값이 우선).
--
--    ※ 확인 결과 이 테이블은 이미 만들어져 있었고(행 0개), 열 구성도 동일했습니다.
--      다만 RLS 정책이 없어서 anon 키로 저장(insert/update)이 거부되는 상태였습니다
--      ("new row violates row-level security policy").
--      아래 3) 권한 부분이 그 문제를 해결합니다 — 반드시 실행해 주세요.
-- ───────────────────────────────────────────────────────────────
create table if not exists public.kt_company_prices (
  company      text        not null,
  rep          text        not null,
  buy_price    numeric,
  supply_price numeric,
  updated_at   timestamptz not null default now(),
  primary key (company, rep)
);

-- 이미 있던 테이블에 기본키가 없으면 추가한다.
-- 앱은 upsert(onConflict: company,rep) 로 저장하므로 이 기본키가 반드시 필요하다.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.kt_company_prices'::regclass and contype = 'p'
  ) then
    alter table public.kt_company_prices add primary key (company, rep);
  end if;
end $$;

create index if not exists kt_company_prices_company_idx
  on public.kt_company_prices (company);

-- ───────────────────────────────────────────────────────────────
-- 2) 품번조회 업로드(덮어쓰기) 저장소
--    index.html 의 PN_DATA 를 기준으로 하고, 여기에 저장된 행만
--    화면에서 덮어쓴다. 업로드한 대표품번만 행이 생긴다.
--    compats 는 호환품번 배열: 예) ["S491100057","AS491100057"]
-- ───────────────────────────────────────────────────────────────
create table if not exists public.kt_pn_overrides (
  rep        text        not null primary key,
  name_ko    text,
  name_ru    text,
  spec       text,
  compats    jsonb       not null default '[]'::jsonb,
  final      text,
  updated_at timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────────
-- 3) 권한
--    이 앱은 anon 키로 직접 접근하므로 기존 테이블과 동일하게
--    anon 역할에 읽기/쓰기를 허용한다.
-- ───────────────────────────────────────────────────────────────
grant select, insert, update, delete on public.kt_company_prices to anon, authenticated;
grant select, insert, update, delete on public.kt_pn_overrides   to anon, authenticated;

alter table public.kt_company_prices enable row level security;
alter table public.kt_pn_overrides   enable row level security;

drop policy if exists kt_company_prices_all on public.kt_company_prices;
create policy kt_company_prices_all on public.kt_company_prices
  for all to anon, authenticated using (true) with check (true);

drop policy if exists kt_pn_overrides_all on public.kt_pn_overrides;
create policy kt_pn_overrides_all on public.kt_pn_overrides
  for all to anon, authenticated using (true) with check (true);

-- ───────────────────────────────────────────────────────────────
-- 4) 계정 생성 — 비밀번호는 모두 1111
--    password_hash = SHA-256("1111") (앱의 sha256Hex 와 동일한 방식)
--    이미 있으면 건너뜁니다.
--
--    RUSSIA / KAZAK : 회사명 KITURAMI 소속 지역 계정
--                     → 가격정보에서 MASTER 의 원가·공급가·GP 를 조회
--    KITURAMI RUS   : 아이디 == 회사명 (회사 계정), 구매처는 KITURAMI
--                     → 주문탭 구매가로 KITURAMI RUSSIA 의 공급가를 가져옴
-- ───────────────────────────────────────────────────────────────
insert into public.kt_users
  (id, company, password_hash, contact_name, country, region, phone, email, supplier_company, status, is_admin)
values
  ('RUSSIA', 'KITURAMI',
   '0ffe1abd1a08215353c233d6e009613e95eec4253832a761af28ff37ac5a150c',
   'RUSSIA', '러시아', 'Москва', '+7 4950000000', 'russia@kiturami.local', null, 'approved', false),
  ('KAZAK', 'KITURAMI',
   '0ffe1abd1a08215353c233d6e009613e95eec4253832a761af28ff37ac5a150c',
   'KAZAK', '카자흐스탄', 'Алматы', '+7 7270000000', 'kazak@kiturami.local', null, 'approved', false),
  ('KITURAMI RUS', 'KITURAMI RUS',
   '0ffe1abd1a08215353c233d6e009613e95eec4253832a761af28ff37ac5a150c',
   'KITURAMI RUS', '러시아', 'Москва', '+7 4950000001', 'kiturami.rus@kiturami.local', 'KITURAMI', 'approved', false)
on conflict (id) do nothing;

-- ───────────────────────────────────────────────────────────────
-- 5) 확인
-- ───────────────────────────────────────────────────────────────
-- 계정이 잘 생성됐는지
select id, company, supplier_company, status from public.kt_users
where id in ('MASTER','RUSSIA','KAZAK','KITURAMI RUS') order by id;

-- 두 테이블에 anon 쓰기 정책이 걸렸는지 (각각 1행 이상 나와야 정상)
select tablename, policyname, roles, cmd
from pg_policies
where tablename in ('kt_company_prices','kt_pn_overrides')
order by tablename;

-- 기본키가 (company, rep) 인지
select conname, pg_get_constraintdef(oid) as def
from pg_constraint
where conrelid = 'public.kt_company_prices'::regclass and contype = 'p';
