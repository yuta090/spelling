-- =============================================================================
-- drawings バケットの Storage RLS テスト（0007 migration）
--   scripts/db/test.sh から実行（スタブ＋migrations 適用済みDBに対して走る）。
--   各 DO ブロックが1シナリオ。ASSERT 失敗で psql が非0終了 → ランナーが赤。
--
-- 検証:
--   * バケット drawings が非公開で存在する。
--   * 親メンバーは自世帯パス配下を読める／書ける。
--   * 紐づく子端末（devices 経由）は自世帯パス配下を読める／書ける。
--   * 無関係のユーザーは読めない／書けない（RLS で 0 行 / with check 失敗）。
-- =============================================================================
\set ON_ERROR_STOP on

-- 「誰として呼ぶか」を request.jwt.claims に流し込むヘルパ。
create or replace function _act_as(p_sub text, p_is_anon boolean) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_sub, 'role', 'authenticated', 'is_anonymous', p_is_anon)::text,
    true
  );
  select null::void;
$$;

create temp table _ctx(k text primary key, v text);

-- ---------------------------------------------------------------------------
-- 0) セットアップ: 親が世帯A・世帯Bを作り、Aに子プロファイル＋子端末を紐づける。
-- ---------------------------------------------------------------------------
do $$
declare
  parent_a text := '11111111-1111-1111-1111-111111111111';
  parent_b text := '22222222-2222-2222-2222-222222222222';
  child_a  text := '33333333-3333-3333-3333-333333333333';  -- 世帯Aに紐づく子端末の匿名uid
  outsider text := '44444444-4444-4444-4444-444444444444';  -- どこにも属さない
  hid_a uuid; hid_b uuid; pid_a uuid; pid_a2 uuid;
begin
  perform _act_as(parent_a, false);
  hid_a := public.create_household('Household A');
  insert into public.profiles(household_id, display_name) values (hid_a, 'Kid A') returning id into pid_a;
  -- 同じ世帯の別プロファイル（きょうだい）。子端末A は pid_a に紐づくので pid_a2 配下は書けないはず。
  insert into public.profiles(household_id, display_name) values (hid_a, 'Kid A2') returning id into pid_a2;
  -- 子端末を世帯A・プロファイル pid_a に紐づけ（consume_pairing_code 相当を直挿し）。
  insert into public.devices(household_id, profile_id, auth_user_id)
    values (hid_a, pid_a, child_a::uuid);

  perform _act_as(parent_b, false);
  hid_b := public.create_household('Household B');

  insert into _ctx values
    ('parent_a', parent_a), ('parent_b', parent_b),
    ('child_a', child_a), ('outsider', outsider),
    ('hid_a', hid_a::text), ('hid_b', hid_b::text),
    ('pid_a', pid_a::text), ('pid_a2', pid_a2::text);
  raise notice 'PASS 0: setup (hid_a=%, hid_b=%)', hid_a, hid_b;
end $$;

-- ---------------------------------------------------------------------------
-- 1) バケットは非公開で存在する。
-- ---------------------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from storage.buckets where id = 'drawings' and public = false;
  assert n = 1, 'drawings bucket should exist and be private';
  raise notice 'PASS 1: private bucket exists';
end $$;

-- ---------------------------------------------------------------------------
-- 2) 親メンバー: 自世帯・任意プロファイル配下にアップロードできる（with check 通過）。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid;
        pid_a uuid := (select v from _ctx where k='pid_a')::uuid;
begin
  perform _act_as((select v from _ctx where k='parent_a'), false);
  set local role authenticated;
  insert into storage.objects(bucket_id, name)
    values ('drawings', hid_a::text || '/' || pid_a::text || '/attempts/aaaa1111-0000-0000-0000-000000000001.png');
  reset role;
  raise notice 'PASS 2: parent can upload under own household/profile path';
end $$;

-- ---------------------------------------------------------------------------
-- 3) 紐づく子端末: 自プロファイル配下にアップロードできる（device_can_access 経由）。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid;
        pid_a uuid := (select v from _ctx where k='pid_a')::uuid;
begin
  perform _act_as((select v from _ctx where k='child_a'), true);
  set local role authenticated;
  insert into storage.objects(bucket_id, name)
    values ('drawings', hid_a::text || '/' || pid_a::text || '/attempts/aaaa1111-0000-0000-0000-000000000002.png');
  reset role;
  raise notice 'PASS 3: paired child device can upload under own profile path';
end $$;

-- ---------------------------------------------------------------------------
-- 3b) 子端末は同じ世帯でも「別プロファイル」配下には書けない（プロファイル厳密一致）。
--     RLS 由来の拒否だけを合格とするため SQLSTATE 42501 に限定する（誤許可の見逃し防止）。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid;
        pid_a2 uuid := (select v from _ctx where k='pid_a2')::uuid; blocked boolean := false;
begin
  perform _act_as((select v from _ctx where k='child_a'), true);
  set local role authenticated;
  begin
    insert into storage.objects(bucket_id, name)
      values ('drawings', hid_a::text || '/' || pid_a2::text || '/attempts/aaaa1111-0000-0000-0000-000000000003.png');
  exception when sqlstate '42501' then
    blocked := true;
  end;
  reset role;
  assert blocked, 'child device must not write under a sibling profile path';
  raise notice 'PASS 3b: child cannot write under sibling profile';
end $$;

-- ---------------------------------------------------------------------------
-- 3c) 見本(reviews)は親のみ書ける。親は書け、子は自プロファイル配下でも書けない
--     （reviews 本体テーブルの is_household_member 書込みをミラー）。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid;
        pid_a uuid := (select v from _ctx where k='pid_a')::uuid; blocked boolean := false;
begin
  -- 親: 見本を置ける。
  perform _act_as((select v from _ctx where k='parent_a'), false);
  set local role authenticated;
  insert into storage.objects(bucket_id, name)
    values ('drawings', hid_a::text || '/' || pid_a::text || '/reviews/aaaa1111-0000-0000-0000-000000000001.png');
  reset role;

  -- 子: 自分のプロファイル配下でも見本(reviews)は置けない（親限定）。
  perform _act_as((select v from _ctx where k='child_a'), true);
  set local role authenticated;
  begin
    insert into storage.objects(bucket_id, name)
      values ('drawings', hid_a::text || '/' || pid_a::text || '/reviews/aaaa1111-0000-0000-0000-000000000004.png');
  exception when sqlstate '42501' then
    blocked := true;
  end;
  reset role;
  assert blocked, 'child must not write review (example) images (parent-only)';
  raise notice 'PASS 3c: reviews write is parent-only';
end $$;

-- ---------------------------------------------------------------------------
-- 3d) 兄弟プロファイル(pid_a2)配下に親が1件置く（次の cross-profile READ 検証用）。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid;
        pid_a2 uuid := (select v from _ctx where k='pid_a2')::uuid;
begin
  perform _act_as((select v from _ctx where k='parent_a'), false);
  set local role authenticated;
  insert into storage.objects(bucket_id, name)
    values ('drawings', hid_a::text || '/' || pid_a2::text || '/attempts/aaaa1111-0000-0000-0000-000000000005.png');
  reset role;
  raise notice 'PASS 3d: sibling-profile object seeded';
end $$;

-- 現在の世帯A配下オブジェクト（4件）:
--   pid_a/attempts x2, pid_a/reviews x1, pid_a2/attempts x1

-- ---------------------------------------------------------------------------
-- 4) 読み取りスコープ: 親=世帯内全部 / 別世帯=0 / 子=自プロファイルのみ（兄弟は読めない）。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid;
        pid_a uuid := (select v from _ctx where k='pid_a')::uuid;
        pid_a2 uuid := (select v from _ctx where k='pid_a2')::uuid; n int;
begin
  -- 親A: 世帯A配下は全4件見える。
  perform _act_as((select v from _ctx where k='parent_a'), false);
  set local role authenticated;
  select count(*) into n from storage.objects
    where bucket_id='drawings' and (storage.foldername(name))[1] = hid_a::text;
  reset role;
  assert n = 4, format('parent should read all 4 household objects, got %s', n);

  -- 親B(別世帯): 世帯A配下は1件も見えない。
  perform _act_as((select v from _ctx where k='parent_b'), false);
  set local role authenticated;
  select count(*) into n from storage.objects
    where bucket_id='drawings' and (storage.foldername(name))[1] = hid_a::text;
  reset role;
  assert n = 0, format('other-household parent must not read, got %s', n);

  -- 子A: 自プロファイル(pid_a)配下の3件だけ見える。
  perform _act_as((select v from _ctx where k='child_a'), true);
  set local role authenticated;
  select count(*) into n from storage.objects
    where bucket_id='drawings' and (storage.foldername(name))[2] = pid_a::text;
  assert n = 3, format('child should read own-profile 3 objects, got %s', n);
  -- 兄弟プロファイル(pid_a2)配下は読めない。
  select count(*) into n from storage.objects
    where bucket_id='drawings' and (storage.foldername(name))[2] = pid_a2::text;
  reset role;
  assert n = 0, format('child must NOT read sibling-profile objects, got %s', n);
  raise notice 'PASS 4: read scoped to household + profile';
end $$;

-- ---------------------------------------------------------------------------
-- 5) 部外者は他世帯パス配下にアップロードできない（with check 失敗＝42501）。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid;
        pid_a uuid := (select v from _ctx where k='pid_a')::uuid; blocked boolean := false;
begin
  perform _act_as((select v from _ctx where k='outsider'), false);
  set local role authenticated;
  begin
    insert into storage.objects(bucket_id, name)
      values ('drawings', hid_a::text || '/' || pid_a::text || '/attempts/aaaa1111-0000-0000-0000-000000000009.png');
  exception when sqlstate '42501' then
    blocked := true;
  end;
  reset role;
  assert blocked, 'outsider upload into another household path must be rejected';
  raise notice 'PASS 5: outsider upload rejected';
end $$;

-- ---------------------------------------------------------------------------
-- 6) 削除ポリシー無し = 親でも削除は拒否（append-only 方針）。全4件残る。
-- ---------------------------------------------------------------------------
do $$
declare hid_a uuid := (select v from _ctx where k='hid_a')::uuid; n int;
begin
  perform _act_as((select v from _ctx where k='parent_a'), false);
  set local role authenticated;
  delete from storage.objects
    where bucket_id='drawings' and (storage.foldername(name))[1] = hid_a::text;
  select count(*) into n from storage.objects
    where bucket_id='drawings' and (storage.foldername(name))[1] = hid_a::text;
  reset role;
  assert n = 4, format('delete must be denied by RLS (rows should remain), got %s', n);
  raise notice 'PASS 6: delete denied (no delete policy)';
end $$;

do $$ begin raise notice 'ALL drawings_storage tests passed'; end $$;
