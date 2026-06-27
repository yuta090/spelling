-- =============================================================================
-- ペアリング RPC のテスト（create_pairing_code / consume_pairing_code）
--   scripts/db/test.sh から実行（スタブ＋migrations 適用済みのDBに対して走る）。
--   各 DO ブロックが1シナリオ。ASSERT 失敗で psql が非0終了 → ランナーが赤。
-- =============================================================================
\set ON_ERROR_STOP on

-- pepper をセッションに設定（本番は ALTER DATABASE SET。テストでは固定値）。
set app.pairing_pepper = 'test-pepper-do-not-use-in-prod-0123456789';

-- 識別子（固定）。
--   parent = 親, dev1/dev2/dev3 = 子端末の匿名 uid。
create temp table _ctx(k text primary key, v text);

-- 「誰として呼ぶか」を request.jwt.claims に流し込むヘルパ（auth.uid()/auth.jwt() が読む）。
create or replace function _act_as(p_sub text, p_is_anon boolean) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_sub, 'role', 'authenticated', 'is_anonymous', p_is_anon)::text,
    true   -- transaction-local
  );
  select null::void;
$$;

-- ---------------------------------------------------------------------------
-- 0) セットアップ: 親が世帯を作り、子プロファイルを1つ用意。
-- ---------------------------------------------------------------------------
do $$
declare
  parent text := '11111111-1111-1111-1111-111111111111';
  hid uuid; pid uuid;
begin
  perform _act_as(parent, false);
  hid := public.create_household('Test Household');
  insert into public.profiles(household_id, display_name) values (hid, 'Kid') returning id into pid;
  insert into _ctx values ('parent', parent), ('hid', hid::text), ('pid', pid::text);
  raise notice 'PASS 0: setup (hid=%, pid=%)', hid, pid;
end $$;

-- ---------------------------------------------------------------------------
-- 1) 発行: 親が6桁コードを発行。平文は保存されず、HMACハッシュが保存される。
-- ---------------------------------------------------------------------------
do $$
declare
  parent text; hid uuid; pid uuid; code text; exp timestamptz;
begin
  select v into parent from _ctx where k='parent';
  select v::uuid into hid from _ctx where k='hid';
  select v::uuid into pid from _ctx where k='pid';

  perform _act_as(parent, false);
  select c.code, c.expires_at into code, exp from public.create_pairing_code(hid, pid) c;

  assert code ~ '^[0-9]{6}$', 'code must be 6 digits, got '||coalesce(code,'<null>');
  assert exp > now(), 'expiry must be in the future';
  assert exists(select 1 from public.pairing_codes
                where code_hash = app.pairing_code_hash(code) and consumed_at is null and expires_at = exp),
         'hashed code must be stored';
  assert not exists(select 1 from public.pairing_codes where code_hash = code),
         'plaintext code must NOT be stored';

  insert into _ctx values ('code1', code);
  raise notice 'PASS 1: issue (code=%)', code;
end $$;

-- ---------------------------------------------------------------------------
-- 2) 発行: 非メンバー（別の親アカウント）は弾かれる。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; raised boolean := false;
begin
  select v::uuid into hid from _ctx where k='hid';
  perform _act_as('99999999-9999-9999-9999-999999999999', false);  -- 他人
  begin
    perform public.create_pairing_code(hid, null);
  exception when others then raised := true;
  end;
  assert raised, 'non-member must not be able to issue a code';
  raise notice 'PASS 2: non-member cannot issue';
end $$;

-- ---------------------------------------------------------------------------
-- 3) 発行: 匿名ユーザーは、仮に member 行があっても発行できない。
-- ---------------------------------------------------------------------------
do $$
declare
  hid uuid;
  anon_member text := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  raised boolean := false;
begin
  select v::uuid into hid from _ctx where k='hid';
  insert into public.household_members(household_id, user_id, role)
    values (hid, anon_member::uuid, 'parent')
    on conflict (household_id, user_id) do nothing;

  perform _act_as(anon_member, true);
  begin
    perform public.create_pairing_code(hid, null);
  exception when others then raised := true;
  end;
  assert raised, 'anonymous member must not be able to issue a code';
  raise notice 'PASS 3: anonymous member cannot issue';
end $$;

-- ---------------------------------------------------------------------------
-- 4) 消費(正常): 子端末(匿名)が正しいコードを消費 → ok。devices 登録・code 消費済み。
-- ---------------------------------------------------------------------------
do $$
declare
  dev1 text := 'd1111111-1111-1111-1111-111111111111';
  code text; hid uuid; pid uuid; st text; rh uuid; rp uuid;
begin
  select v into code from _ctx where k='code1';
  select v::uuid into hid from _ctx where k='hid';
  select v::uuid into pid from _ctx where k='pid';

  perform _act_as(dev1, true);
  select s.status, s.household_id, s.profile_id into st, rh, rp
    from public.consume_pairing_code(code, 'ipad-1') s;

  assert st = 'ok', 'expected ok, got '||st;
  assert rh = hid and rp = pid, 'must return linked household/profile';
  assert exists(select 1 from public.devices
                where auth_user_id = dev1::uuid and household_id = hid and profile_id = pid and revoked_at is null),
         'device row must be created bound to anon uid';
  assert exists(select 1 from public.pairing_codes
                where code_hash = app.pairing_code_hash(code) and consumed_at is not null),
         'code must be marked consumed';

  insert into _ctx values ('dev1', dev1);
  raise notice 'PASS 4: consume ok + device linked';
end $$;

-- ---------------------------------------------------------------------------
-- 5) 単回: 既に消費済みのコードは別端末でも無効。
-- ---------------------------------------------------------------------------
do $$
declare code text; st text;
begin
  select v into code from _ctx where k='code1';
  perform _act_as('d2222222-2222-2222-2222-222222222222', true);
  select s.status into st from public.consume_pairing_code(code, 'ipad-2') s;
  assert st = 'invalid_or_expired', 'consumed code must be single-use, got '||st;
  raise notice 'PASS 5: single-use enforced';
end $$;

-- ---------------------------------------------------------------------------
-- 6) 失効: expires_at が過去のコードは無効。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; st text;
begin
  select v::uuid into hid from _ctx where k='hid';
  -- 失効済みコードを直接仕込む（superuser は RLS をバイパス）。
  insert into public.pairing_codes(household_id, code_hash, expires_at, created_by)
    values (hid, app.pairing_code_hash('654321'), now() - interval '1 minute',
            '11111111-1111-1111-1111-111111111111');
  perform _act_as('d4444444-4444-4444-4444-444444444444', true);
  select s.status into st from public.consume_pairing_code('654321', null) s;
  assert st = 'invalid_or_expired', 'expired code must be invalid, got '||st;
  raise notice 'PASS 6: expired code rejected';
end $$;

-- ---------------------------------------------------------------------------
-- 7) 誤コード: 存在しないコードは無効。RAISE せずカウンタが残る。
-- ---------------------------------------------------------------------------
do $$
declare st text; attempts int;
begin
  perform _act_as('d5555555-5555-5555-5555-555555555555', true);
  select s.status into st from public.consume_pairing_code('000001', null) s;
  assert st = 'invalid_or_expired', 'unknown code must be invalid, got '||st;
  select attempt_count into attempts
    from public.pairing_consume_limits
    where auth_user_id = 'd5555555-5555-5555-5555-555555555555';
  assert attempts = 1, 'invalid expected failure must persist rate counter, got '||coalesce(attempts::text, '<null>');
  raise notice 'PASS 7: unknown code rejected without rollback';
end $$;

-- ---------------------------------------------------------------------------
-- 8) レート制限: 同一匿名uidの連続失敗は10回まで、11回目でロック。
-- ---------------------------------------------------------------------------
do $$
declare st text; i int;
begin
  perform _act_as('d6666666-6666-6666-6666-666666666666', true);
  for i in 1..10 loop
    select s.status into st from public.consume_pairing_code('111111', null) s;
    assert st = 'invalid_or_expired', format('attempt %s should be invalid, got %s', i, st);
  end loop;
  select s.status into st from public.consume_pairing_code('111111', null) s;
  assert st = 'rate_limited', '11th attempt must be rate_limited, got '||st;
  raise notice 'PASS 8: brute-force rate limit';
end $$;

-- ---------------------------------------------------------------------------
-- 9) already_paired: 既にペアリング済みの端末が別コードを消費しても再登録しない。
-- ---------------------------------------------------------------------------
do $$
declare parent text; hid uuid; pid uuid; code text; dev1 text; st text; rh uuid; cnt int;
begin
  select v into parent from _ctx where k='parent';
  select v::uuid into hid from _ctx where k='hid';
  select v::uuid into pid from _ctx where k='pid';
  select v into dev1 from _ctx where k='dev1';

  perform _act_as(parent, false);
  select c.code into code from public.create_pairing_code(hid, pid) c;

  perform _act_as(dev1, true);
  select s.status, s.household_id into st, rh from public.consume_pairing_code(code, 'ipad-1') s;
  assert st = 'already_paired', 'already-paired device must not re-pair, got '||st;
  assert rh = hid, 'already_paired must report existing household';
  select count(*) into cnt from public.devices where auth_user_id = dev1::uuid and revoked_at is null;
  assert cnt = 1, 'must not create a second device row, found '||cnt;
  -- そのコードは消費されていない（再利用可能）。
  assert exists(select 1 from public.pairing_codes
                where code_hash = app.pairing_code_hash(code) and consumed_at is null),
         'code must remain unconsumed when caller already paired';
  raise notice 'PASS 9: already_paired';
end $$;

-- ---------------------------------------------------------------------------
-- 10) 匿名以外は消費不可（親アカウントが端末行になるのを防ぐ）。
-- ---------------------------------------------------------------------------
do $$
declare raised boolean := false;
begin
  perform _act_as('77777777-7777-7777-7777-777777777777', false);  -- not anonymous
  begin
    perform public.consume_pairing_code('222222', null);
  exception when others then raised := true;
  end;
  assert raised, 'non-anonymous session must be rejected on consume';
  raise notice 'PASS 10: non-anonymous consume rejected';
end $$;

-- ---------------------------------------------------------------------------
-- 11) 未認証は消費不可。
-- ---------------------------------------------------------------------------
do $$
declare raised boolean := false;
begin
  perform set_config('request.jwt.claims', '{}', true);  -- no sub
  begin
    perform public.consume_pairing_code('333333', null);
  exception when others then raised := true;
  end;
  assert raised, 'unauthenticated consume must raise';
  raise notice 'PASS 11: unauthenticated consume rejected';
end $$;

-- ---------------------------------------------------------------------------
-- 12) pepper 未設定は fail-closed（空鍵で運用しない）。
-- ---------------------------------------------------------------------------
do $$
declare raised boolean := false;
begin
  perform set_config('app.pairing_pepper', '', true);  -- このトランザクションだけ空に
  begin
    perform app.pairing_code_hash('123456');
  exception when others then raised := true;
  end;
  assert raised, 'empty pepper must fail closed';
  raise notice 'PASS 12: pepper fail-closed';
end $$;

-- ---------------------------------------------------------------------------
-- 13) 形式検証: 6桁数字以外は invalid_or_expired（ハッシュを引く前に弾く）。試行はカウント。
-- ---------------------------------------------------------------------------
do $$
declare st text; attempts int;
begin
  perform _act_as('da777777-7777-7777-7777-777777777777', true);
  select s.status into st from public.consume_pairing_code('abc', null) s;
  assert st = 'invalid_or_expired', 'malformed code must be invalid, got '||st;
  select s.status into st from public.consume_pairing_code('12345', null) s;  -- 5桁
  assert st = 'invalid_or_expired', '5-digit code must be invalid, got '||st;
  select attempt_count into attempts from public.pairing_consume_limits
    where auth_user_id = 'da777777-7777-7777-7777-777777777777';
  assert attempts = 2, 'malformed attempts must still count, got '||coalesce(attempts::text,'<null>');
  raise notice 'PASS 13: malformed code rejected (counted)';
end $$;

-- ---------------------------------------------------------------------------
-- 14) device_public_id が長すぎる場合は拒否（肥大化スパム防止）。
-- ---------------------------------------------------------------------------
do $$
declare raised boolean := false;
begin
  perform _act_as('db888888-8888-8888-8888-888888888888', true);
  begin
    perform public.consume_pairing_code('123456', repeat('x', 129));
  exception when others then raised := true;
  end;
  assert raised, 'over-long device_public_id must be rejected';
  raise notice 'PASS 14: over-long device id rejected';
end $$;

-- ---------------------------------------------------------------------------
-- 15) グローバル分制限: 全体で1分あたりの上限を超えると、新規uidでも rate_limited。
--     （uid量産による総当たり回避の検証）
-- ---------------------------------------------------------------------------
do $$
declare st text;
begin
  -- 現在の分バケットを上限ちょうどに仕込む（superuser）。
  delete from public.pairing_global_throttle;
  insert into public.pairing_global_throttle(minute_bucket, attempt_count)
    values (date_trunc('minute', now()), 60);
  perform _act_as('dc999999-9999-9999-9999-999999999999', true);  -- まっさらな新規uid
  select s.status into st from public.consume_pairing_code('123456', null) s;
  assert st = 'rate_limited', 'fresh uid must still be globally throttled, got '||st;
  delete from public.pairing_global_throttle;  -- 後続テストに影響させない
  raise notice 'PASS 15: global throttle defeats uid-farming';
end $$;

-- ---------------------------------------------------------------------------
-- 16) TTL は 900秒(15分)にクランプされる。
-- ---------------------------------------------------------------------------
do $$
declare parent text; hid uuid; exp timestamptz;
begin
  select v into parent from _ctx where k='parent';
  select v::uuid into hid from _ctx where k='hid';
  perform _act_as(parent, false);
  select c.expires_at into exp from public.create_pairing_code(hid, null, 99999) c;
  assert exp <= now() + interval '15 minutes' + interval '2 seconds',
         'ttl must be clamped to <=15min, got '||(exp - now())::text;
  raise notice 'PASS 16: ttl clamped to 15min';
end $$;

-- ---------------------------------------------------------------------------
-- 17) cleanup_pairing は消費済み/失効コード・古い制限/バケットを掃除する。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; before_cnt int; after_cnt int;
begin
  select v::uuid into hid from _ctx where k='hid';
  insert into public.pairing_codes(household_id, code_hash, expires_at, created_by, consumed_at)
    values (hid, app.pairing_code_hash('999999'), now() - interval '2 days',
            '11111111-1111-1111-1111-111111111111', now() - interval '2 days');
  select count(*) into before_cnt from public.pairing_codes
    where expires_at < now() - interval '1 day';
  assert before_cnt >= 1, 'should have an old code to clean';
  perform app.cleanup_pairing();
  select count(*) into after_cnt from public.pairing_codes
    where expires_at < now() - interval '1 day';
  assert after_cnt = 0, 'cleanup must remove old codes, left '||after_cnt;
  raise notice 'PASS 17: cleanup_pairing prunes stale rows';
end $$;

drop function _act_as(text, boolean);
