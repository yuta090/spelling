-- =============================================================================
-- 0007 drawings storage bucket + RLS（採点同期の画像置き場）
--
-- 子の手書き（attempts.drawing_path）と親の見本（reviews.parent_example_path）を
-- Supabase Storage に置くための非公開バケット `drawings` と、世帯単位のアクセス制御。
--
-- パス規約（アプリ側 DrawingStorage と一致させること）:
--   {household_id}/{profile_id}/attempts/{attempt_id}.png
--   {household_id}/{profile_id}/reviews/{attempt_id}.png
-- foldername(name)[1]=household_id, [2]=profile_id, [3]=種別(attempts|reviews)。
--
-- ポリシーは attempts/reviews 本体テーブルの RLS を Storage 上に忠実にミラーする:
--   * attempts は append-only（本体は SELECT+INSERT のみ）。
--       → 手書き画像も INSERT=has_access（自プロファイル端末=子 も可）、UPDATE 不可（不変）。
--   * reviews の書込みは親のみ（本体は is_household_member）。
--       → 見本画像は INSERT/UPDATE とも is_household_member（親のみ・子端末は不可）。
--   * SELECT は両種別とも has_access（親は世帯内全部、子は自プロファイル配下のみ）。
-- has_access(hid,pid) は rls_hardening #1 で device_can_access が「プロファイル厳密一致」を
-- 要求するため、pid を必ずパスに含める（子端末は自分の pid 配下だけ読み書きできる）。
--
-- 本番では storage スキーマ／テーブルは Supabase Storage 拡張が用意し、所有者は
-- supabase_storage_admin。CREATE POLICY は所有者権限が要るため、そのロールに切り替えて実行する。
-- ローカル/CI の SQL テストは harness/00_supabase_stub.sql が同等物（ロール・所有権含む）を用意する。
-- =============================================================================

create schema if not exists storage;

do $$
begin
  -- 本番/テストとも storage オブジェクトの所有者ロールに切り替えてから DDL/DML する
  -- （postgres は当該ロールのメンバー or superuser なので SET ROLE できる）。
  if exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') then
    -- ポリシー式が参照する app スキーマ（has_access/is_household_member）への USAGE を
    -- 所有者ロールへ付与（CREATE POLICY 時の名前解決に必要）。app 所有者=postgres が実行。
    execute 'grant usage on schema app to supabase_storage_admin';
    set local role supabase_storage_admin;
  end if;

  -- 非公開バケット（public=false）。署名URL/認証経由でのみアクセス。
  insert into storage.buckets (id, name, public)
  values ('drawings', 'drawings', false)
  on conflict (id) do nothing;

  -- 読み取り: 世帯メンバー or 自プロファイル端末（attempts/reviews 両方）。
  execute $p$drop policy if exists drawings_read on storage.objects$p$;
  execute $p$
    create policy drawings_read on storage.objects for select to authenticated
      using (
        bucket_id = 'drawings'
        and app.has_access((storage.foldername(name))[1]::uuid, (storage.foldername(name))[2]::uuid)
      )
  $p$;

  -- 手書き(attempts)の追加: 自プロファイル端末（子）を含む has_access。UPDATE ポリシーは無し=不変。
  execute $p$drop policy if exists drawings_insert_attempts on storage.objects$p$;
  execute $p$
    create policy drawings_insert_attempts on storage.objects for insert to authenticated
      with check (
        bucket_id = 'drawings'
        and (storage.foldername(name))[3] = 'attempts'
        and app.has_access((storage.foldername(name))[1]::uuid, (storage.foldername(name))[2]::uuid)
      )
  $p$;

  -- 見本(reviews)の追加/上書き: 親メンバーのみ（子端末は不可）。
  execute $p$drop policy if exists drawings_insert_reviews on storage.objects$p$;
  execute $p$
    create policy drawings_insert_reviews on storage.objects for insert to authenticated
      with check (
        bucket_id = 'drawings'
        and (storage.foldername(name))[3] = 'reviews'
        and app.is_household_member((storage.foldername(name))[1]::uuid)
      )
  $p$;

  execute $p$drop policy if exists drawings_update_reviews on storage.objects$p$;
  execute $p$
    create policy drawings_update_reviews on storage.objects for update to authenticated
      using (
        bucket_id = 'drawings'
        and (storage.foldername(name))[3] = 'reviews'
        and app.is_household_member((storage.foldername(name))[1]::uuid)
      )
      with check (
        bucket_id = 'drawings'
        and (storage.foldername(name))[3] = 'reviews'
        and app.is_household_member((storage.foldername(name))[1]::uuid)
      )
  $p$;

  -- 旧・全種別まとめ update ポリシーが以前のリビジョンで残っていれば掃除（冪等）。
  execute $p$drop policy if exists drawings_insert on storage.objects$p$;
  execute $p$drop policy if exists drawings_update on storage.objects$p$;
end $$;

-- 削除ポリシーは意図的に無し（= 拒否）。attempts が append-only なのと揃える。
