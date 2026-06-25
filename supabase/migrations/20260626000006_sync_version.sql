-- =============================================================================
-- 0006 sync_version（単調増加の同期カーソル）— Code Reviewer 指摘 #1/#2 対応
-- server_changed_at(timestamptz) は同時刻タイ＆文字列比較で取りこぼし/順序不正の恐れ。
-- グローバル連番 bigint をサーバー採番し、これを「差分プルのカーソル」にする（単一列・厳密単調・タイ無し）。
-- =============================================================================

create sequence if not exists app.sync_version_seq;

-- 既存トリガ関数を拡張：更新/挿入のたびに server_changed_at と sync_version を採番。
-- （LWWガード 0005 が stale を NULL 返却で弾くため、本トリガは実反映時のみ発火）
create or replace function app.set_server_changed_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.server_changed_at := now();
  new.sync_version := nextval('app.sync_version_seq');
  return new;
end;
$$;

-- 全同期テーブルに列＋索引を追加（既存行は default で連番採番＝バックフィル）。
do $$
declare t text;
begin
  for t in select tablename from pg_tables
           where schemaname='public' and tablename <> 'schema_migrations'
  loop
    execute format('alter table public.%I add column if not exists sync_version bigint not null default nextval(''app.sync_version_seq'')', t);
    execute format('create index if not exists idx_%s_syncver on public.%I(sync_version)', t, t);
  end loop;
end $$;
