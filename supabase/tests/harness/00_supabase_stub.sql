-- =============================================================================
-- Supabase 環境スタブ（ローカル/CI でのSQLテスト用・本番には流さない）
--
-- 目的: Docker の `supabase start` 無しに、素の Postgres 上で本番マイグレーションを
-- そのまま適用・検証できるよう、Supabase が用意する最小限の足場だけ再現する。
--   * ロール: anon / authenticated / service_role
--   * auth スキーマと auth.uid() / auth.jwt() / auth.role()
--     → 本番(GoTrue+PostgREST)と同じく `request.jwt.claims` GUC から読む実装に合わせる。
--       テストでは `set request.jwt.claims = '{"sub":...,"role":...,"is_anonymous":...}'` で
--       「誰として呼ぶか」を切り替える。
--
-- ⚠️ このファイルは supabase/migrations/ には置かない（テスト専用）。
-- =============================================================================

-- ロール（存在しなければ作る）。grant 先として必要。
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

create schema if not exists auth;

-- 本番 Supabase の auth.uid()/auth.jwt()/auth.role() と同等。
-- request.jwt.claims（JSON）の sub / role を返す。未設定なら NULL。
create or replace function auth.jwt()
returns jsonb
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), ''),
    '{}'
  )::jsonb
$$;

create or replace function auth.uid()
returns uuid
language sql stable
as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;

create or replace function auth.role()
returns text
language sql stable
as $$
  select auth.jwt() ->> 'role'
$$;

grant usage on schema auth to anon, authenticated, service_role;

-- =============================================================================
-- storage スキーマのスタブ（本番 Supabase Storage が用意する最小限だけ再現）
--
-- 目的: `storage.objects` に対する RLS ポリシー（drawings バケット）を素の Postgres で
-- 検証できるようにする。本番では Supabase Storage 拡張がこれらを提供するため、
-- migrations 側は `create schema if not exists` 等の冪等な前提でこのスタブに乗る。
-- =============================================================================
create schema if not exists storage;

-- 本番の storage オブジェクト所有者ロール（supabase_storage_admin）を再現。
-- migration は CREATE POLICY のためこのロールに SET ROLE する（所有者権限が要るため）。
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') then
    create role supabase_storage_admin nologin noinherit;
  end if;
end
$$;

-- バケット定義（本番同様 id をキーに）。
create table if not exists storage.buckets (
  id         text primary key,
  name       text not null,
  public     boolean not null default false,
  created_at timestamptz not null default now()
);

-- オブジェクト（本番の主要列のみ）。RLS 判定に使う bucket_id / name / owner を持つ。
create table if not exists storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text references storage.buckets(id),
  name       text not null,
  owner      uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 本番同様、storage テーブルの所有者を supabase_storage_admin にする（CREATE POLICY 権限のため）。
alter table storage.buckets owner to supabase_storage_admin;
alter table storage.objects owner to supabase_storage_admin;

-- 本番の storage.foldername(name): パスをスラッシュで割り、末尾(ファイル名)を除いた配列を返す。
--   例: 'hid/attempts/x.png' -> {hid, attempts}
create or replace function storage.foldername(name text)
returns text[]
language sql immutable
as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;

alter table storage.objects enable row level security;

grant usage on schema storage to anon, authenticated, service_role, supabase_storage_admin;
grant all on storage.buckets to service_role;
grant all on storage.objects to service_role;
grant select, insert, update, delete on storage.objects to authenticated, anon;
grant select on storage.buckets to authenticated, anon;
