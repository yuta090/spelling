-- =============================================================================
-- 0005 LWW guard trigger（Architectレビュー #3）
-- 素の upsert は「API到着順で後勝ち」になり、updated_at ベースの LWW を保証しない。
-- サーバー側のトリガで、古い updated_at の更新を無視し、同時刻の“復活(削除解除)”を却下する。
-- これにより SpellingSyncCore.LastWriteWins と意味論を一致させる。
--
-- トリガ名 trg_aa_* は trg_server_changed_at より先に発火する（NULL返却で更新自体を中止＝
-- server_changed_at の無駄な更新も防ぐ）。
-- =============================================================================

create or replace function app.lww_guard()
returns trigger language plpgsql set search_path = ''
as $$
begin
  -- 古い更新は無視（stale write → 更新自体を中止）
  if new.updated_at < old.updated_at then
    return null;
  end if;
  -- 同時刻のタイ: 既に削除済みを“復活(deleted_at を NULL化)”する更新は却下（削除優先）
  if new.updated_at = old.updated_at
     and old.deleted_at is not null
     and new.deleted_at is null then
    return null;
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  for t in select tablename from pg_tables
           where schemaname='public' and tablename <> 'schema_migrations'
  loop
    execute format('drop trigger if exists trg_aa_lww_guard on public.%I', t);
    execute format('create trigger trg_aa_lww_guard before update on public.%I for each row execute function app.lww_guard()', t);
  end loop;
end $$;
