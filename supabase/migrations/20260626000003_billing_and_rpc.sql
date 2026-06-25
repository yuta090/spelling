-- =============================================================================
-- 0003 Billing (entitlements) + bootstrap RPC
-- =============================================================================

-- 課金状態（家族プラン＝世帯単位）。書込みは Edge Function(service_role)が
-- App Store Server Notifications を検証して行う。クライアントは閲覧のみ。
create table if not exists public.entitlements (
  id                      uuid primary key default gen_random_uuid(),
  household_id            uuid not null references public.households(id) on delete cascade,
  product_id              text not null,
  status                  text not null default 'none'
                            check (status in ('none','trial','active','grace','expired','revoked')),
  expires_at              timestamptz,
  original_transaction_id text,
  environment             text,                 -- 'Production' / 'Sandbox'
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  deleted_at              timestamptz,
  unique (household_id, product_id)
);
create index if not exists idx_entitlements_hh on public.entitlements(household_id);

alter table public.entitlements enable row level security;

-- 閲覧は has_access（子端末もプレミアム解放判定のため読める）。
-- 書込みポリシーは作らない → authenticated は書けず、service_role のみ更新可。
create policy entitlements_select on public.entitlements for select
  using (app.has_access(household_id, null));

-- ============================ bootstrap RPC ==================================
-- households の INSERT は「メンバーであること」を要求するため、メンバー0の初回は
-- 直接 insert できない（鶏卵）。SECURITY DEFINER の RPC で世帯＋オーナーを原子的に作る。
create or replace function public.create_household(p_title text default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  hid uuid;
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'authentication required';
  end if;
  insert into public.households(title) values (p_title) returning id into hid;
  insert into public.household_members(household_id, user_id, role)
    values (hid, uid, 'owner');
  return hid;
end;
$$;
revoke all on function public.create_household(text) from public;
grant execute on function public.create_household(text) to authenticated;
