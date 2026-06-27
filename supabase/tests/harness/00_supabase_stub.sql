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
