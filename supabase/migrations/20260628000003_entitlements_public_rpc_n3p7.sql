-- =============================================================================
-- 0010 entitlements の PostgREST 公開ラッパ（本筋C・appstore-notify Edge から呼ぶ）
--
-- app.upsert_entitlement / app.household_has_active_entitlement は app スキーマにあり、
-- PostgREST は public しか公開しないため supabase-js の .rpc() から直接呼べない。
-- public に薄いラッパを置いて公開する（ロジックは app 側のまま）。
--   * upsert は service_role(Edge)のみ実行可。クライアントには公開しない。
--   * has_active はサーバ機能ゲート用。authenticated も自世帯分は呼べる（内部で has_access ゲート）。
-- =============================================================================

-- 取り込み Edge(appstore-notify) が service_role で呼ぶ upsert の公開口。
create or replace function public.upsert_entitlement(
  p_household_id            uuid,
  p_product_id             text,
  p_status                 text,
  p_expires_at             timestamptz,
  p_original_transaction_id text,
  p_environment            text,
  p_event_at               timestamptz
)
returns text
language sql volatile security definer set search_path = ''
as $$
  select app.upsert_entitlement(
    p_household_id, p_product_id, p_status, p_expires_at,
    p_original_transaction_id, p_environment, p_event_at)
$$;

revoke all on function public.upsert_entitlement(uuid, text, text, timestamptz, text, text, timestamptz) from public;
revoke execute on function public.upsert_entitlement(uuid, text, text, timestamptz, text, text, timestamptz) from anon, authenticated;
grant  execute on function public.upsert_entitlement(uuid, text, text, timestamptz, text, text, timestamptz) to service_role;

-- サーバ機能ゲートの公開口（自世帯のみ・内部で service_role or has_access を検証）。
create or replace function public.household_has_active_entitlement(p_household_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select app.household_has_active_entitlement(p_household_id)
$$;

revoke all on function public.household_has_active_entitlement(uuid) from public;
grant execute on function public.household_has_active_entitlement(uuid) to authenticated, service_role;
