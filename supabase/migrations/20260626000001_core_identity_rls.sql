-- =============================================================================
-- 0001 Core identity + RLS helpers
-- 世帯(household)・親メンバー・子プロファイル・端末ペアリング と、RLS の土台。
-- 設計: docs/supabase-sync-design.md  / RLS方針: postgres-rls スキル(Supabase向け調整)
--
-- 【Supabase向けRLSの方針（一般スキルからの意図的な逸脱を明記）】
--  * テナント文脈は auth.uid()（JWT）で取得 → SET LOCAL のプール漏れ問題は構造的に発生しない。
--  * service_role は設計上 RLS をバイパスする（Edge Function のサーバー側専用。クライアントへ配布しない）。
--    そのため FORCE ROW LEVEL SECURITY は使わない（PostgREST は authenticated/anon ロールで接続し
--    テーブル所有者ではないため、ENABLE だけでポリシーに従う）。
--  * 親メンバー判定は household_members を参照するため、RLS再帰回避に SECURITY DEFINER 関数を使う。
--  * 全データ行に household_id を持たせ（非正規化）、policy列に索引を張る。
-- =============================================================================

create extension if not exists pgcrypto;      -- gen_random_uuid()

-- 内部ヘルパー関数は app スキーマに隔離（PostgREST の公開対象外）
create schema if not exists app;

-- =============================== Tables ======================================

-- 世帯（オーナー＝親）
create table if not exists public.households (
  id          uuid primary key default gen_random_uuid(),
  title       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- 親メンバー（RLSの基点）
create table if not exists public.household_members (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null,                    -- auth.users.id（親）
  role         text not null default 'parent' check (role in ('owner','parent')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (household_id, user_id)
);
create index if not exists idx_members_household on public.household_members(household_id);
create index if not exists idx_members_user      on public.household_members(user_id);

-- 子プロファイル（アプリログインなし）
create table if not exists public.profiles (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references public.households(id) on delete cascade,
  display_name    text not null default '',
  app_language    text not null default 'japanese',
  active_step_id  uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index if not exists idx_profiles_household on public.profiles(household_id);

-- ペアリング済み端末（子iPad等）。子は匿名認証 → auth_user_id に紐づく。
create table if not exists public.devices (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references public.households(id) on delete cascade,
  profile_id       uuid references public.profiles(id) on delete set null,
  device_public_id text,                          -- 非秘密の端末識別子
  auth_user_id     uuid not null,                 -- 匿名auth.users.id（端末）
  paired_at        timestamptz not null default now(),
  revoked_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (auth_user_id)
);
create index if not exists idx_devices_household on public.devices(household_id);
create index if not exists idx_devices_authuser  on public.devices(auth_user_id);

-- ペアリングコード（単回・短命）。発行/消費は Edge Function(service_role)が担う。
create table if not exists public.pairing_codes (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid references public.profiles(id) on delete cascade,
  code_hash    text not null,                     -- 生コードは保存しない
  expires_at   timestamptz not null,
  consumed_at  timestamptz,
  created_by   uuid not null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_pairing_household on public.pairing_codes(household_id);

-- ============================ RLS helper funcs ===============================
-- いずれも STABLE + SECURITY DEFINER + search_path='' で、再帰回避と注入防止。

create or replace function app.is_household_member(hid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.household_members m
    where m.household_id = hid
      and m.user_id = (select auth.uid())
      and m.deleted_at is null
  );
$$;

create or replace function app.device_can_access(hid uuid, pid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.devices d
    where d.auth_user_id = (select auth.uid())
      and d.revoked_at is null
      and d.household_id = hid
      and (pid is null or d.profile_id = pid)
  );
$$;

-- 親メンバー or 紐づく端末。データ各表の policy はこれ1本で表現する。
create or replace function app.has_access(hid uuid, pid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select app.is_household_member(hid) or app.device_can_access(hid, pid);
$$;

revoke all on function app.is_household_member(uuid) from public;
revoke all on function app.device_can_access(uuid, uuid) from public;
revoke all on function app.has_access(uuid, uuid) from public;
grant execute on function app.is_household_member(uuid) to authenticated;
grant execute on function app.device_can_access(uuid, uuid) to authenticated;
grant execute on function app.has_access(uuid, uuid) to authenticated;

-- ================================ Enable RLS =================================
alter table public.households       enable row level security;
alter table public.household_members enable row level security;
alter table public.profiles         enable row level security;
alter table public.devices          enable row level security;
alter table public.pairing_codes    enable row level security;

-- ================================ Policies ===================================
-- households: 親メンバー or 紐づく端末がアクセス可。作成は本人を後で member 化（Edge or トリガ）。
create policy households_access on public.households
  for all
  using (app.has_access(id, null))
  with check (app.has_access(id, null));

-- household_members: その世帯の親メンバーのみ。
create policy members_access on public.household_members
  for all
  using (app.is_household_member(household_id))
  with check (app.is_household_member(household_id));

-- profiles: 親=全プロファイル / 端末=自分のプロファイルのみ。
create policy profiles_access on public.profiles
  for all
  using (app.has_access(household_id, id))
  with check (app.has_access(household_id, id));

-- devices: 親=世帯の端末を管理 / 端末=自分の行のみ参照。
create policy devices_parent on public.devices
  for all
  using (app.is_household_member(household_id))
  with check (app.is_household_member(household_id));
create policy devices_self_select on public.devices
  for select
  using (auth_user_id = (select auth.uid()));

-- pairing_codes: 親のみ（消費は service_role の Edge Function で）。
create policy pairing_parent on public.pairing_codes
  for all
  using (app.is_household_member(household_id))
  with check (app.is_household_member(household_id));

-- 注: service_role は RLS をバイパス（Edge Function 専用）。クライアントには anon/authenticated のみ配布。
