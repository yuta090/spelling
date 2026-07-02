-- =============================================================================
-- words.profile_id 必須化 ＋ 世帯×プロファイル複合FK の制約テスト（Phase 5b）
--   scripts/db/test.sh から実行（スタブ＋migrations 適用済みDBに対して走る）。
--   接続は superuser(postgres)＝RLSバイパス。ここでは RLS ではなく **テーブル制約** を検証する:
--     (1) profile_id = NULL の words INSERT は NOT NULL 制約で失敗する。
--     (2) 別世帯の profile を指す words INSERT は複合FKで失敗する（世帯×プロファイル整合）。
--     (3) 同世帯の profile を指す正しい words INSERT は成功する。
-- =============================================================================
\set ON_ERROR_STOP on

do $$
declare
  hh_a  uuid := gen_random_uuid();
  hh_b  uuid := gen_random_uuid();
  pf_a  uuid := gen_random_uuid();   -- 世帯Aのプロファイル
  pf_b  uuid := gen_random_uuid();   -- 世帯Bのプロファイル
  ok    boolean;
begin
  insert into public.households(id, title) values (hh_a, 'A'), (hh_b, 'B');
  insert into public.profiles(id, household_id, display_name) values
    (pf_a, hh_a, 'child-a'),
    (pf_b, hh_b, 'child-b');

  -- (1) profile_id = NULL は NOT NULL 制約で弾かれる。
  ok := false;
  begin
    insert into public.words(id, household_id, profile_id, text)
      values (gen_random_uuid(), hh_a, null, 'apple');
  exception when not_null_violation then
    ok := true;
  end;
  if not ok then
    raise exception 'FAIL(1): profile_id=NULL の words INSERT が通ってしまった（NOT NULL 化されていない）';
  end if;

  -- (2) 世帯Aの word が世帯Bの profile を指すのは複合FKで弾かれる。
  ok := false;
  begin
    insert into public.words(id, household_id, profile_id, text)
      values (gen_random_uuid(), hh_a, pf_b, 'banana');
  exception when foreign_key_violation then
    ok := true;
  end;
  if not ok then
    raise exception 'FAIL(2): 別世帯 profile を指す words INSERT が通ってしまった（複合FKが無い）';
  end if;

  -- (3) 同世帯の profile を指す正しい INSERT は成功する。
  insert into public.words(id, household_id, profile_id, text)
    values (gen_random_uuid(), hh_a, pf_a, 'cherry');

  raise notice 'words_profile_required_test: OK';
end $$;
