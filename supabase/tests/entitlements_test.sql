-- =============================================================================
-- サーバ権利ミラー核のテスト（app.upsert_entitlement / household_has_active_entitlement）
--   scripts/db/test.sh から実行（スタブ＋migrations 適用済みのDBに対して走る）。
--   upsert は service_role/定義者専用。テストは superuser で直接呼ぶが、
--   entitlement gate は service_role JWT claim を入れてサーバ呼び出し相当にする。
-- =============================================================================
\set ON_ERROR_STOP on

select set_config('request.jwt.claims', '{"role":"service_role"}', false);

-- テスト用の世帯を直接用意（superuser は RLS をバイパス）。FK のため households 行が要る。
create temp table _ectx(k text primary key, v text);
do $$
declare hid uuid;
begin
  insert into public.households(title) values ('Entitlement Test') returning id into hid;
  insert into _ectx values ('hid', hid::text);
  raise notice 'PASS 0: setup household %', hid;
end $$;

-- ---------------------------------------------------------------------------
-- 1) 新規 upsert: 行が作られ active・有効になる。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; st text;
begin
  select v::uuid into hid from _ectx where k='hid';
  st := app.upsert_entitlement(hid, 'family.monthly', 'active',
        now() + interval '30 days', 'OTX-1', 'Production', now());
  assert st = 'active', 'returned status should be active, got '||st;
  assert app.household_has_active_entitlement(hid), 'household must be active';
  assert (select count(*) from public.entitlements where household_id=hid) = 1, 'one row';
  raise notice 'PASS 1: insert active';
end $$;

-- ---------------------------------------------------------------------------
-- 2) 冪等: 同じイベントを再適用しても重複行を作らない。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; ev timestamptz := now();
begin
  select v::uuid into hid from _ectx where k='hid';
  perform app.upsert_entitlement(hid, 'family.monthly', 'active', now()+interval '30 days', 'OTX-1', 'Production', ev);
  perform app.upsert_entitlement(hid, 'family.monthly', 'active', now()+interval '30 days', 'OTX-1', 'Production', ev);
  assert (select count(*) from public.entitlements where household_id=hid and product_id='family.monthly') = 1,
         'upsert must be idempotent (one row)';
  raise notice 'PASS 2: idempotent';
end $$;

-- ---------------------------------------------------------------------------
-- 3) 単調ガード: 既存より古いイベントは無視（active を古いexpiredで巻き戻さない）。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; st text;
begin
  select v::uuid into hid from _ectx where k='hid';
  -- まず新しいイベントで active（基準時刻を確定）。
  perform app.upsert_entitlement(hid, 'family.monthly', 'active', now()+interval '30 days', 'OTX-1', 'Production', now());
  -- 古いイベントで expired を送る → 無視されるべき。
  st := app.upsert_entitlement(hid, 'family.monthly', 'expired', now()-interval '1 day', 'OTX-1', 'Production', now()-interval '10 minutes');
  assert st = 'active', 'stale event must be ignored, status stayed active; got '||st;
  assert app.household_has_active_entitlement(hid), 'still active after stale downgrade attempt';
  raise notice 'PASS 3: monotonic guard ignores stale';
end $$;

-- ---------------------------------------------------------------------------
-- 4) 更新(更新通知): 新しいイベントで失効日が延びる。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; exp timestamptz;
begin
  select v::uuid into hid from _ectx where k='hid';
  perform app.upsert_entitlement(hid, 'family.monthly', 'active', now()+interval '60 days', 'OTX-1', 'Production', now()+interval '1 second');
  select expires_at into exp from public.entitlements where household_id=hid and product_id='family.monthly';
  assert exp > now()+interval '40 days', 'renewal must extend expiry';
  raise notice 'PASS 4: renewal extends';
end $$;

-- ---------------------------------------------------------------------------
-- 5) 失効: 新しいイベントで expired → 権利は無効になる。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; st text;
begin
  select v::uuid into hid from _ectx where k='hid';
  st := app.upsert_entitlement(hid, 'family.monthly', 'expired', now()-interval '1 minute', 'OTX-1', 'Production', now()+interval '2 seconds');
  assert st = 'expired', 'status should be expired, got '||st;
  assert not app.household_has_active_entitlement(hid), 'expired household must not be active';
  raise notice 'PASS 5: expire downgrades';
end $$;

-- ---------------------------------------------------------------------------
-- 6) なりすまし防止: original_transaction_id 不一致は拒否。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; raised boolean := false;
begin
  select v::uuid into hid from _ectx where k='hid';
  begin
    perform app.upsert_entitlement(hid, 'family.monthly', 'active', now()+interval '30 days', 'OTX-EVIL', 'Production', now()+interval '3 seconds');
  exception when others then raised := true;
  end;
  assert raised, 'mismatched original_transaction_id must be rejected';
  raise notice 'PASS 6: otx mismatch rejected';
end $$;

-- ---------------------------------------------------------------------------
-- 7) 不正 status は拒否。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; raised boolean := false;
begin
  select v::uuid into hid from _ectx where k='hid';
  begin
    perform app.upsert_entitlement(hid, 'family.yearly', 'bogus', null, 'OTX-2', 'Production', now());
  exception when others then raised := true;
  end;
  assert raised, 'invalid status must be rejected';
  raise notice 'PASS 7: invalid status rejected';
end $$;

-- ---------------------------------------------------------------------------
-- 8) has_active_entitlement: 状態と失効日を正しく反映する。
-- ---------------------------------------------------------------------------
do $$
declare hid2 uuid;
begin
  insert into public.households(title) values ('HH2') returning id into hid2;
  -- trial・未来失効 → 有効
  perform app.upsert_entitlement(hid2, 'family.monthly', 'trial', now()+interval '7 days', 'OTX-T', 'Sandbox', now());
  assert app.household_has_active_entitlement(hid2), 'trial w/ future expiry is active';
  -- grace・無期限(null) → 有効
  perform app.upsert_entitlement(hid2, 'family.monthly', 'grace', null, 'OTX-T', 'Sandbox', now()+interval '1 second');
  assert app.household_has_active_entitlement(hid2), 'grace w/ null expiry is active';
  -- active だが失効済み → 無効
  perform app.upsert_entitlement(hid2, 'family.monthly', 'active', now()-interval '1 second', 'OTX-T', 'Sandbox', now()+interval '2 seconds');
  assert not app.household_has_active_entitlement(hid2), 'active but past expiry is NOT active';
  raise notice 'PASS 8: has_active reflects status+expiry';
end $$;

-- ---------------------------------------------------------------------------
-- 9) 別世帯に漏れない（世帯スコープ）。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; hid3 uuid;
begin
  select v::uuid into hid from _ectx where k='hid';
  insert into public.households(title) values ('HH3-no-entitlement') returning id into hid3;
  assert not app.household_has_active_entitlement(hid3), 'unrelated household has no entitlement';
  raise notice 'PASS 9: household-scoped';
end $$;

-- ---------------------------------------------------------------------------
-- 10) 同時刻イベントは replay として扱い、別 status で上書きしない。
-- ---------------------------------------------------------------------------
do $$
declare
  hid uuid;
  ev timestamptz := clock_timestamp();
  st text;
  stored_status text;
begin
  insert into public.households(title) values ('HH-equal-event') returning id into hid;
  perform app.upsert_entitlement(hid, 'family.monthly', 'active',
          now()+interval '30 days', 'OTX-EQ', 'Production', ev);

  st := app.upsert_entitlement(hid, 'family.monthly', 'expired',
        now()-interval '1 day', 'OTX-EQ', 'Production', ev);
  select status into stored_status
    from public.entitlements
    where household_id=hid and product_id='family.monthly';

  assert st = 'active', 'equal timestamp replay must return existing active status, got '||st;
  assert stored_status = 'active', 'equal timestamp replay must not mutate status, got '||stored_status;
  raise notice 'PASS 10: equal event is replay-only';
end $$;

-- ---------------------------------------------------------------------------
-- 11) last_event_at が NULL の既存行は、最初のミラー更新で採用できる。
-- ---------------------------------------------------------------------------
do $$
declare
  hid uuid;
  st text;
  stored_last_event_at timestamptz;
begin
  insert into public.households(title) values ('HH-null-last-event') returning id into hid;
  insert into public.entitlements(
    household_id, product_id, status, expires_at,
    original_transaction_id, environment, last_event_at
  ) values (
    hid, 'family.monthly', 'expired', now()-interval '1 day',
    'OTX-NULL-LAST', 'Production', null
  );

  st := app.upsert_entitlement(hid, 'family.monthly', 'active',
        now()+interval '30 days', 'OTX-NULL-LAST', 'Production', clock_timestamp());
  select last_event_at into stored_last_event_at
    from public.entitlements
    where household_id=hid and product_id='family.monthly';

  assert st = 'active', 'null last_event_at row should accept first event, got '||st;
  assert stored_last_event_at is not null, 'first accepted event must set last_event_at';
  assert app.household_has_active_entitlement(hid), 'adopted legacy row should be active';
  raise notice 'PASS 11: null last_event_at adopted';
end $$;

-- ---------------------------------------------------------------------------
-- 12) lww_guard: 同一トランザクション内の論理削除からの復活が NULL return で黙殺されない。
-- ---------------------------------------------------------------------------
do $$
declare
  hid uuid;
  ev timestamptz := clock_timestamp();
  st text;
  deleted_value timestamptz;
begin
  insert into public.households(title) values ('HH-lww-reactivate') returning id into hid;
  perform app.upsert_entitlement(hid, 'family.monthly', 'active',
          now()+interval '30 days', 'OTX-LWW', 'Production', ev);

  update public.entitlements
    set deleted_at = now(), updated_at = now()
    where household_id=hid and product_id='family.monthly';

  st := app.upsert_entitlement(hid, 'family.monthly', 'active',
        now()+interval '30 days', 'OTX-LWW', 'Production', ev + interval '1 second');
  select deleted_at into deleted_value
    from public.entitlements
    where household_id=hid and product_id='family.monthly';

  assert st = 'active', 'reactivation should return active, got '||st;
  assert deleted_value is null, 'reactivation must clear deleted_at despite lww_guard';
  assert app.household_has_active_entitlement(hid), 'reactivated entitlement should be active';
  raise notice 'PASS 12: lww_guard reactivation works';
end $$;

-- ---------------------------------------------------------------------------
-- 13) partial update は original_transaction_id / environment を NULL で消さない。
-- ---------------------------------------------------------------------------
do $$
declare
  hid uuid;
  stored_original text;
  stored_environment text;
  stored_status text;
begin
  insert into public.households(title) values ('HH-partial-update') returning id into hid;
  perform app.upsert_entitlement(hid, 'family.monthly', 'active',
          now()+interval '30 days', 'OTX-COALESCE', 'Production', clock_timestamp());
  perform app.upsert_entitlement(hid, 'family.monthly', 'grace',
          now()+interval '3 days', null, null, clock_timestamp() + interval '1 second');

  select original_transaction_id, environment, status
    into stored_original, stored_environment, stored_status
    from public.entitlements
    where household_id=hid and product_id='family.monthly';

  assert stored_original = 'OTX-COALESCE', 'partial update must preserve original_transaction_id';
  assert stored_environment = 'Production', 'partial update must preserve environment';
  assert stored_status = 'grace', 'newer partial update should still apply status';
  raise notice 'PASS 13: partial updates preserve identifiers';
end $$;

-- ---------------------------------------------------------------------------
-- 14) upsert_entitlement の実行権限は service_role のみ。
-- ---------------------------------------------------------------------------
do $$
begin
  assert not has_schema_privilege('anon', 'app', 'USAGE'), 'anon must not have app schema usage';
  assert has_schema_privilege('authenticated', 'app', 'USAGE'), 'authenticated needs app schema usage for read gate RPC';
  assert has_schema_privilege('service_role', 'app', 'USAGE'), 'service_role needs app schema usage for entitlement RPC';
  assert not has_function_privilege(
    'anon',
    'app.upsert_entitlement(uuid,text,text,timestamptz,text,text,timestamptz)'::regprocedure,
    'EXECUTE'
  ), 'anon must not execute upsert_entitlement';
  assert not has_function_privilege(
    'authenticated',
    'app.upsert_entitlement(uuid,text,text,timestamptz,text,text,timestamptz)'::regprocedure,
    'EXECUTE'
  ), 'authenticated must not execute upsert_entitlement';
  assert has_function_privilege(
    'service_role',
    'app.upsert_entitlement(uuid,text,text,timestamptz,text,text,timestamptz)'::regprocedure,
    'EXECUTE'
  ), 'service_role must execute upsert_entitlement';
  raise notice 'PASS 14: upsert execute grant is service_role-only';
end $$;

-- ---------------------------------------------------------------------------
-- 15) household_has_active_entitlement は authenticated に他世帯の状態を漏らさない。
-- ---------------------------------------------------------------------------
do $$
declare
  uid uuid := '00000000-0000-0000-0000-0000000000a1';
  own_hid uuid;
  other_hid uuid;
begin
  insert into public.households(title) values ('HH-auth-own') returning id into own_hid;
  insert into public.households(title) values ('HH-auth-other') returning id into other_hid;
  insert into public.household_members(household_id, user_id, role)
    values (own_hid, uid, 'owner');

  perform app.upsert_entitlement(own_hid, 'family.monthly', 'active',
          now()+interval '30 days', 'OTX-OWN', 'Production', clock_timestamp());
  perform app.upsert_entitlement(other_hid, 'family.monthly', 'active',
          now()+interval '30 days', 'OTX-OTHER', 'Production', clock_timestamp());

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', uid::text, 'role', 'authenticated', 'is_anonymous', false)::text,
    true
  );
  assert app.household_has_active_entitlement(own_hid), 'member should see own active entitlement';
  assert not app.household_has_active_entitlement(other_hid), 'member must not learn other household active entitlement';

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  assert app.household_has_active_entitlement(other_hid), 'service_role gate should see active entitlement';
  raise notice 'PASS 15: active gate enforces caller household access';
end $$;
