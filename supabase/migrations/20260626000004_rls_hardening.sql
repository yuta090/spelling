-- =============================================================================
-- 0004 RLS hardening（Codex Architect レビュー反映）
-- 対応: #1 子書込みを自プロファイル厳密一致に / #2 クライアントDELETE禁止(論理削除のみ) /
--       #4 サーバー管理 server_changed_at(同期カーソル) / #5 pairing/devices/membersはEdge専用 /
--       #7 匿名ユーザーの create_household 拒否
-- 残(別フェーズ): #3 LWWマージRPC, #6 複合FK整合, #8 決定論UUID, #9 Storage署名URL
-- =============================================================================

-- ---- #1: device アクセスを「自プロファイル厳密一致」に狭める -------------------
-- 旧 device_can_access は pid is null を許していた（世帯レベル行に全端末アクセス可）。
-- 書込み/プロファイル行は厳密一致のみに。世帯レベル行の“閲覧”は device_in_household で別途。
create or replace function app.device_can_access(hid uuid, pid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.devices d
    where d.auth_user_id = (select auth.uid())
      and d.revoked_at is null
      and d.household_id = hid
      and pid is not null
      and d.profile_id = pid
  );
$$;

create or replace function app.device_in_household(hid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.devices d
    where d.auth_user_id = (select auth.uid())
      and d.revoked_at is null
      and d.household_id = hid
  );
$$;
revoke all on function app.device_in_household(uuid) from public;
grant execute on function app.device_in_household(uuid) to authenticated;

-- 子端末が世帯レコード自体を“閲覧”できるよう SELECT を追加（書込みは不可）。
drop policy if exists households_child_read on public.households;
create policy households_child_read on public.households
  for select using (app.device_in_household(id));

-- ---- #2: クライアント(anon/authenticated)のハード DELETE を全面禁止 -------------
-- 同期は論理削除(deleted_at の UPDATE)のみ。物理削除は service_role(Edge)だけ。
do $$
declare t text;
begin
  for t in select tablename from pg_tables
           where schemaname='public' and tablename <> 'schema_migrations'
  loop
    execute format('revoke delete on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---- #5: ペアリング系はクライアント書込み禁止（発行/消費はEdge=service_role） ----
revoke insert, update, delete on
  public.devices, public.pairing_codes, public.household_members
  from anon, authenticated;
-- （SELECTは既存ポリシーで親/自端末に限定。create_household RPC は SECURITY DEFINER で動くため影響なし）

-- ---- #4: サーバー管理の変更時刻（同期カーソル用） -------------------------------
-- updated_at はクライアント設定の LWW 時刻。カーソルにはサーバーが必ず採番する値を使う。
create or replace function app.set_server_changed_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.server_changed_at := now();
  return new;
end;
$$;

do $$
declare t text;
begin
  for t in select tablename from pg_tables
           where schemaname='public' and tablename <> 'schema_migrations'
  loop
    execute format('alter table public.%I add column if not exists server_changed_at timestamptz not null default now()', t);
    execute format('drop trigger if exists trg_server_changed_at on public.%I', t);
    execute format('create trigger trg_server_changed_at before insert or update on public.%I for each row execute function app.set_server_changed_at()', t);
    execute format('create index if not exists idx_%s_scat on public.%I(server_changed_at)', t, t);
  end loop;
end $$;

-- ---- #7: 匿名ユーザーは世帯オーナーになれない（親はメール認証必須） --------------
create or replace function public.create_household(p_title text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  hid uuid;
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'authentication required';
  end if;
  if coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) then
    raise exception 'anonymous users cannot create a household';
  end if;
  insert into public.households(title) values (p_title) returning id into hid;
  insert into public.household_members(household_id, user_id, role)
    values (hid, uid, 'owner');
  return hid;
end;
$$;
