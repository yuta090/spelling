-- =============================================================================
-- entitlements の public ラッパ RPC のテスト（0010）。
-- =============================================================================
\set ON_ERROR_STOP on
select set_config('request.jwt.claims', '{"role":"service_role"}', false);

create temp table _pctx(k text primary key, v text);
do $$
declare hid uuid;
begin
  insert into public.households(title) values ('Public RPC Test') returning id into hid;
  insert into _pctx values ('hid', hid::text);
end $$;

-- 1) public.upsert_entitlement が app へ委譲して行を作る。
do $$
declare hid uuid; st text;
begin
  select v::uuid into hid from _pctx where k='hid';
  st := public.upsert_entitlement(hid, 'com.yuta090.SpellingTrainer.parentplan.monthly',
        'active', now()+interval '30 days', 'OTX-PUB', 'Production', now());
  assert st = 'active', 'wrapper should return active, got '||st;
  assert public.household_has_active_entitlement(hid), 'wrapper gate should report active';
  assert (select count(*) from public.entitlements where household_id=hid) = 1, 'one row via wrapper';
  raise notice 'PASS 1: public wrapper delegates to app';
end $$;

-- 2) 権限: upsert は service_role のみ・クライアントは不可。has_active は authenticated 可。
do $$
begin
  assert     has_function_privilege('service_role',
               'public.upsert_entitlement(uuid,text,text,timestamptz,text,text,timestamptz)', 'execute'),
             'service_role must execute upsert wrapper';
  assert not has_function_privilege('authenticated',
               'public.upsert_entitlement(uuid,text,text,timestamptz,text,text,timestamptz)', 'execute'),
             'authenticated must NOT execute upsert wrapper';
  assert not has_function_privilege('anon',
               'public.upsert_entitlement(uuid,text,text,timestamptz,text,text,timestamptz)', 'execute'),
             'anon must NOT execute upsert wrapper';
  assert     has_function_privilege('authenticated',
               'public.household_has_active_entitlement(uuid)', 'execute'),
             'authenticated may call has_active wrapper';
  raise notice 'PASS 2: wrapper grants are correct';
end $$;
