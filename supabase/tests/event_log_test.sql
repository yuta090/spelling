-- =============================================================================
-- event_log（運用テレメトリ・送信専用テーブル）の RLS / 制約 / 送信RPC テスト
--   scripts/db/test.sh から実行（スタブ＋migrations 適用済みDBに対して走る）。
--   接続は superuser(postgres)＝RLSバイパス。クライアント挙動は `set local role authenticated`
--   ＋ request.jwt.claims で「誰として呼ぶか」を切り替えて検証する。
--   書き込みは SECURITY DEFINER RPC `public.log_events(jsonb)` 経由（テーブル直 INSERT 権限は無い）。
--   各 DO ブロックは autocommit の1トランザクション → 終了で role/claims は自動リセット。
-- =============================================================================
\set ON_ERROR_STOP on

create temp table _ectx(k text primary key, v text);

create or replace function _act_as(p_sub text, p_is_anon boolean) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_sub, 'role', 'authenticated', 'is_anonymous', p_is_anon)::text,
    true
  );
  select null::void;
$$;

-- 1イベント分の JSON 配列を組む小ヘルパ（テスト可読性のため）。
create or replace function _ev(
  hid uuid, code text, category text, severity int,
  pid uuid default null, eid uuid default null, payload jsonb default null
) returns jsonb
language sql as $$
  select jsonb_build_array(jsonb_build_object(
    'event_id', coalesce(eid, gen_random_uuid()),
    'household_id', hid,
    'profile_id', pid,
    'device_id', gen_random_uuid(),
    'occurred_at', now(),
    'severity', severity,
    'category', category,
    'code', code,
    'app_version', '1.0.0',
    'os_version', '17.0',
    'payload', payload
  ));
$$;

-- ---------------------------------------------------------------------------
-- 0) セットアップ: 親が世帯と子プロファイルを作り、子端末(匿名uid)を devices に登録。
-- ---------------------------------------------------------------------------
do $$
declare
  parent text := 'ee111111-1111-1111-1111-111111111111';
  dev1   text := 'ee222222-2222-2222-2222-222222222222';
  hid uuid; pid uuid;
begin
  perform _act_as(parent, false);
  hid := public.create_household('Telemetry Test HH');
  insert into public.profiles(household_id, display_name) values (hid, 'Kid') returning id into pid;
  insert into public.devices(household_id, profile_id, auth_user_id, device_public_id)
    values (hid, pid, dev1::uuid, 'ipad-telemetry');
  insert into _ectx values ('parent', parent), ('dev1', dev1), ('hid', hid::text), ('pid', pid::text);
  raise notice 'PASS 0: setup (hid=%, pid=%)', hid, pid;
end $$;

-- ---------------------------------------------------------------------------
-- 1) 親メンバーは RPC で自世帯の行を書ける（profile_id は NULL 可）。
-- ---------------------------------------------------------------------------
do $$
declare parent text; hid uuid; ins int; n int;
begin
  select v into parent from _ectx where k='parent';
  select v::uuid into hid from _ectx where k='hid';
  perform _act_as(parent, false);
  set local role authenticated;
  ins := public.log_events(_ev(hid, 'sync.push_failed', 'sync', 30, payload => '{"reason":"timeout"}'::jsonb));
  reset role;
  assert ins = 1, 'parent should insert 1 via RPC, got '||ins;
  select count(*) into n from public.event_log where household_id = hid;
  assert n = 1, 'one row must land, got '||n;
  raise notice 'PASS 1: parent member writes via RPC (profile_id NULL)';
end $$;

-- ---------------------------------------------------------------------------
-- 2) 紐づく子端末(匿名)も RPC で自世帯＋自pid の行を書ける。
-- ---------------------------------------------------------------------------
do $$
declare dev1 text; hid uuid; pid uuid; ins int; n int;
begin
  select v into dev1 from _ectx where k='dev1';
  select v::uuid into hid from _ectx where k='hid';
  select v::uuid into pid from _ectx where k='pid';
  perform _act_as(dev1, true);
  set local role authenticated;
  ins := public.log_events(_ev(hid, 'session.practice_summary', 'session', 20, pid => pid,
           payload => '{"result":"completed","word_count_bucket":"6-10"}'::jsonb));
  reset role;
  assert ins = 1, 'child device should insert 1 via RPC, got '||ins;
  select count(*) into n from public.event_log where household_id = hid;
  assert n = 2, 'second row must land, got '||n;
  raise notice 'PASS 2: paired child device writes via RPC';
end $$;

-- ---------------------------------------------------------------------------
-- 3) 他人（非メンバー・非端末）は他世帯に書けない（RPC 内 has_access で拒否）。
-- ---------------------------------------------------------------------------
do $$
declare hid uuid; raised boolean := false;
begin
  select v::uuid into hid from _ectx where k='hid';
  perform _act_as('99999999-9999-9999-9999-999999999999', false);
  set local role authenticated;
  begin
    perform public.log_events(_ev(hid, 'ocr.failed', 'ocr', 30));
  exception when others then raised := true;
  end;
  reset role;
  assert raised, 'stranger must not write to another household';
  raise notice 'PASS 3: non-member write rejected by RPC has_access';
end $$;

-- ---------------------------------------------------------------------------
-- 4) 真の送信専用: クライアント(authenticated)はテーブルに直接 SELECT/UPDATE/DELETE できない
--    （テーブル権限を一切付与していない → すべて permission denied）。
-- ---------------------------------------------------------------------------
do $$
declare parent text; raised boolean;
begin
  select v into parent from _ectx where k='parent';
  perform _act_as(parent, false);

  raised := false;
  set local role authenticated;
  begin perform 1 from public.event_log limit 1; exception when others then raised := true; end;
  reset role;
  assert raised, 'authenticated must not SELECT event_log directly';

  raised := false;
  set local role authenticated;
  begin update public.event_log set severity = 40; exception when others then raised := true; end;
  reset role;
  assert raised, 'authenticated must not UPDATE event_log';

  raised := false;
  set local role authenticated;
  begin delete from public.event_log; exception when others then raised := true; end;
  reset role;
  assert raised, 'authenticated must not DELETE event_log';

  raise notice 'PASS 4: write-only (no direct SELECT/UPDATE/DELETE for clients)';
end $$;

-- ---------------------------------------------------------------------------
-- 5) CHECK 制約は RPC 経由でも効く（不正 category/allowlist外 code/不正 severity/過大 payload）。
-- ---------------------------------------------------------------------------
do $$
declare parent text; hid uuid; raised boolean;
begin
  select v into parent from _ectx where k='parent';
  select v::uuid into hid from _ectx where k='hid';
  perform _act_as(parent, false);

  raised := false; set local role authenticated;
  begin perform public.log_events(_ev(hid, 'ocr.failed', 'marketing', 30));
  exception when others then raised := true; end;
  reset role;
  assert raised, 'invalid category must be rejected';

  raised := false; set local role authenticated;
  begin perform public.log_events(_ev(hid, 'word_attempt_graded', 'session', 20));
  exception when others then raised := true; end;
  reset role;
  assert raised, 'non-allowlisted code must be rejected';

  raised := false; set local role authenticated;
  begin perform public.log_events(_ev(hid, 'sync.pull_failed', 'sync', 99));
  exception when others then raised := true; end;
  reset role;
  assert raised, 'invalid severity must be rejected';

  raised := false; set local role authenticated;
  begin perform public.log_events(_ev(hid, 'telemetry.dropped', 'telemetry', 20,
           payload => jsonb_build_object('blob', repeat('x', 3000))));
  exception when others then raised := true; end;
  reset role;
  assert raised, 'oversized payload must be rejected';

  raise notice 'PASS 5: CHECK constraints enforced through RPC';
end $$;

-- ---------------------------------------------------------------------------
-- 6) 冪等送信: 同一 event_id の再送は ON CONFLICT DO NOTHING で握りつぶす
--    （RPC は RLS をバイパスするので「既存行が SELECT 不可」でも安全に冪等）。
-- ---------------------------------------------------------------------------
do $$
declare parent text; hid uuid; eid uuid := gen_random_uuid(); ins1 int; ins2 int; n int;
begin
  select v into parent from _ectx where k='parent';
  select v::uuid into hid from _ectx where k='hid';
  perform _act_as(parent, false);
  set local role authenticated;
  ins1 := public.log_events(_ev(hid, 'sync.pull_failed', 'sync', 30, eid => eid));
  ins2 := public.log_events(_ev(hid, 'sync.pull_failed', 'sync', 30, eid => eid));  -- 再送
  reset role;
  assert ins1 = 1, 'first send inserts 1, got '||ins1;
  assert ins2 = 0, 'duplicate send inserts 0 (idempotent), got '||ins2;
  select count(*) into n from public.event_log where event_id = eid;
  assert n = 1, 'exactly one row for event_id, got '||n;
  raise notice 'PASS 6: idempotent re-send via RPC (ON CONFLICT DO NOTHING)';
end $$;

drop function _act_as(text, boolean);
drop function _ev(uuid, text, text, int, uuid, uuid, jsonb);
