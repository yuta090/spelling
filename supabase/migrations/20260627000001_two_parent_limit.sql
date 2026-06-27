-- =============================================================================
-- 0007 世帯あたり親（管理者）は最大2人まで（Phase 2 ガードレール）
-- household_members は unique(household_id, user_id) だが人数上限が無い。
-- BEFORE INSERT/UPDATE トリガで「role in (owner,parent) かつ未削除」を 2 件までに制限する。
-- SECURITY DEFINER（RLS を貫いて全件数える）＋ households 行ロックで同時 insert を直列化。
-- 設計: docs/freemium-impl-design-2026-06-27.md §3（世帯=最大2親）, codex Architect レビュー。
-- =============================================================================

create or replace function app.enforce_two_parent_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent_count int;
begin
  -- 論理削除された行は対象外（削除メンバーは数えない）。
  if new.deleted_at is not null then
    return new;
  end if;

  -- 同一世帯のメンバー変更を直列化（同時 insert が両方「空き」を見て 3 人目が入るのを防ぐ）。
  perform 1 from public.households where id = new.household_id for update;

  select count(*)
  into parent_count
  from public.household_members hm
  where hm.household_id = new.household_id
    and hm.role in ('owner', 'parent')
    and hm.deleted_at is null
    and hm.id is distinct from new.id;   -- UPDATE 時に自分自身を二重に数えない

  if parent_count >= 2 then
    raise exception '世帯の親（管理者）は最大2人までです'
      using errcode = '23514';   -- check_violation
  end if;

  return new;
end;
$$;

-- トリガ関数は直接呼ぶものではないので public の実行権限を外す（既存ヘルパと同じ防御姿勢）。
revoke execute on function app.enforce_two_parent_limit() from public;

-- household_id / role / deleted_at が変わるとき（= 親が増えうる契機）にだけ評価する。
drop trigger if exists household_members_two_parent_limit on public.household_members;
create trigger household_members_two_parent_limit
before insert or update of household_id, role, deleted_at
on public.household_members
for each row
execute function app.enforce_two_parent_limit();

-- 注意（本番適用前）: 既存データに親3人以上の世帯が無いか事前確認すること。
-- このトリガは「以後の違反」を防ぐが、既存行の遡及検査はしない。
--   select household_id, count(*) from public.household_members
--   where role in ('owner','parent') and deleted_at is null
--   group by 1 having count(*) > 2;
