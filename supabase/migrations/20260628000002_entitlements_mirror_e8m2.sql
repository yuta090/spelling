-- =============================================================================
-- 0009 サーバ権利ミラーの核（Apple非依存）— 課金を世帯共有に（本筋C）
--
-- 位置づけ:
--   支払いは iPad の StoreKit2（Apple IAP）で、Apple ID にローカル紐づく。別端末・別Apple ID の
--   親や親Webでも「課金済み」を知るため、世帯(household)スコープで entitlements に状態を写す。
--   状態の取り込み口（どちらも将来・Apple登録後）:
--     (1) App Store Server Notifications V2 を受ける Edge Function（更新/解約/返金を追従）
--     (2) 購入直後に iPad が StoreKit2 で検証 → Edge に渡す client-push
--   どちらの経路でも **最終的にこの upsert を呼ぶ**。本migrationは Apple に依存しない
--   「冪等な書き込み・単調ガード・世帯権利チェック」だけを先に確定し、SQLテストで検証する。
--
--   ※ entitlements 表/RLS は 0003 で作成済み（status: none/trial/active/grace/expired/revoked、
--      unique(household_id, product_id)、SELECT は has_access、書込みポリシー無し＝service_role のみ）。
--
-- 契約（バグ源）:
--   * 書込みは service_role（Edge）専用。クライアント(authenticated/anon)からは書けない。
--   * 冪等: (household_id, product_id) で upsert。
--   * 単調ガード: イベント時刻(p_event_at = ASSN signedDate / 取引時刻)が既存以下なら replay として無視。
--     → 順序逆転・重複で届いた通知で「active を expired にダウングレード」させない。
--   * なりすまし防止: original_transaction_id が確定済みで食い違う更新は拒否。
--   * 解約後の「巻き戻しなし」はクライアント側ポリシー（生成時ゲート）で担保。サーバ権利は
--     現在の課金状態を素直に持つ（status/expires_at）。
-- =============================================================================

-- 単調ガード用に、最後に適用したイベント時刻を持つ。
alter table public.entitlements
  add column if not exists last_event_at timestamptz;

-- app schema functions below are callable RPC entrypoints; schema USAGE is still required in addition to EXECUTE.
revoke usage on schema app from anon, public;
grant usage on schema app to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 権利の upsert（service_role / Edge から呼ぶ。SECURITY DEFINER で RLS 書込み制限を貫通）。
--   返り値 = 適用後の status（stale で未適用なら既存 status）。
-- ----------------------------------------------------------------------------
create or replace function app.upsert_entitlement(
  p_household_id            uuid,
  p_product_id             text,
  p_status                 text,
  p_expires_at             timestamptz,
  p_original_transaction_id text,
  p_environment            text,
  p_event_at               timestamptz
)
returns text
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_existing public.entitlements%rowtype;
  v_status text;
begin
  if p_household_id is null or p_product_id is null then
    raise exception 'household_id and product_id are required';
  end if;
  if p_status is null
     or p_status not in ('none','trial','active','grace','expired','revoked') then
    raise exception 'invalid entitlement status: %', coalesce(p_status, '<null>');
  end if;
  if p_event_at is null then
    raise exception 'event_at is required (monotonic guard)';
  end if;

  loop
    select * into v_existing from public.entitlements
      where household_id = p_household_id and product_id = p_product_id
      for update;

    if found then
      -- なりすまし防止: 確定済み original_transaction_id と食い違う更新は拒否。
      if v_existing.original_transaction_id is not null
         and p_original_transaction_id is not null
         and v_existing.original_transaction_id <> p_original_transaction_id then
        raise exception 'original_transaction_id mismatch for household/product';
      end if;
      -- 単調ガード: 古い/同時刻イベントは replay として無視（逆順・重複で状態を戻さない）。
      if v_existing.last_event_at is not null and p_event_at <= v_existing.last_event_at then
        return v_existing.status;
      end if;
      update public.entitlements e
        set status                  = p_status,
            expires_at              = p_expires_at,
            original_transaction_id = coalesce(p_original_transaction_id, v_existing.original_transaction_id),
            environment             = coalesce(p_environment, v_existing.environment),
            last_event_at           = p_event_at,
            deleted_at              = null,
            updated_at              = greatest(clock_timestamp(), v_existing.updated_at + interval '1 microsecond')
        where e.id = v_existing.id
        returning e.status into v_status;
      if not found then
        raise exception 'entitlement update was rejected by lww guard';
      end if;
      return v_status;
    else
      begin
        insert into public.entitlements(
          household_id, product_id, status, expires_at,
          original_transaction_id, environment, last_event_at)
          values (p_household_id, p_product_id, p_status, p_expires_at,
                  p_original_transaction_id, p_environment, p_event_at);
        return p_status;
      exception
        when unique_violation then
          -- A concurrent first insert won the (household_id, product_id) race; lock and re-evaluate.
      end;
    end if;
  end loop;
end;
$$;

revoke all on function app.upsert_entitlement(uuid, text, text, timestamptz, text, text, timestamptz) from public;
-- 書込みは Edge(service_role)のみ。authenticated/anon には grant しない。
grant execute on function app.upsert_entitlement(uuid, text, text, timestamptz, text, text, timestamptz) to service_role;

-- ----------------------------------------------------------------------------
-- 世帯権利チェック（サーバ機能のゲート）。
--   trial/active/grace かつ（無期限 or 未失効）なら有効。
--   サーバ機能エンドポイントは「クライアントの bool」ではなくこれで検証する（設計 §3）。
-- ----------------------------------------------------------------------------
create or replace function app.household_has_active_entitlement(p_household_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select (
    coalesce((select auth.role()), '') = 'service_role'
    or app.has_access(p_household_id, null)
  ) and exists (
    select 1 from public.entitlements e
    where e.household_id = p_household_id
      and e.deleted_at is null
      and e.status in ('trial', 'active', 'grace')
      and (e.expires_at is null or e.expires_at > now())
  );
$$;

revoke all on function app.household_has_active_entitlement(uuid) from public;
-- 自世帯の権利状態は SELECT ポリシーで既に読めるので、利便のため authenticated にも許可。
grant execute on function app.household_has_active_entitlement(uuid) to authenticated, service_role;
