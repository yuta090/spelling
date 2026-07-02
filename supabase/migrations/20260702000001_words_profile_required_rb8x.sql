-- =============================================================================
-- 0007 words.profile_id を必須化（Phase 5b: 複数子リモート同期の解禁）
--
-- 未リリース（実ユーザー無し）につき **クリーンスレート** で作り直す（CLAUDE.md: 破壊的変更OK）:
--   ・profile_id = NULL の既存 words（旧・世帯 NULL ストリーム＝開発データ）を物理削除する。
--     Phase 5a では provisioning 未実装ゆえ words を profile_id=NULL の世帯スコープで push していた。
--     Phase 5b はクライアントが各子プロファイルを provisioning してから profile_id 付きで push する
--     ので、この NULL ストリームは不要になる（`WordRemoteOwner` の owner ゲートも撤去する）。
--   ・profiles(household_id, id) に unique を張り、words の FK を **複合** (household_id, profile_id)
--     → profiles(household_id, id) に張り替える。これで「words の世帯とプロファイルの世帯が一致」
--     を宣言的に保証する（Architect レビュー: 世帯×プロファイル整合ギャップの解消）。
--   ・words.profile_id を NOT NULL 化する（以後 NULL では push できない＝子スコープを必ず持つ）。
--
-- 依存: profiles の provisioning はクライアントが担う（親認証時に全ローカル子を upsert）。
-- =============================================================================

-- 1) 旧・世帯 NULL ストリーム（開発データ）を破棄する。
--    step_word_memberships にも profile_id NULL があれば掃除する（メンバーシップは未同期だが整合のため）。
delete from public.words where profile_id is null;
delete from public.step_word_memberships where profile_id is null;

-- 2) 複合FKの参照先として profiles(household_id, id) に unique を付与する。
--    id は既に主キー（＝自明に一意）なので、この unique は複合FKを張るための冗長制約。
alter table public.profiles
  add constraint profiles_household_id_uniq unique (household_id, id);

-- 3) words の「profile 単独FK」を、世帯整合を保証する「複合FK」へ張り替える。
--    既存のインラインFK名は Postgres 既定の words_profile_id_fkey。
alter table public.words drop constraint if exists words_profile_id_fkey;
alter table public.words
  add constraint words_household_profile_fkey
  foreign key (household_id, profile_id)
  references public.profiles (household_id, id)
  on delete cascade;

-- 4) profile_id を必須化する（NULL ストリームは 1) で消えている前提）。
alter table public.words
  alter column profile_id set not null;

-- 5) 新しい pull クエリ形状 `where profile_id = ? and sync_version > ? order by sync_version` に合う
--    複合インデックス（Phase 5b はプロファイル別に差分プルする）。データ増加時の走査を避ける。
create index if not exists idx_words_profile_syncver
  on public.words (profile_id, sync_version);
