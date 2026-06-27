-- =============================================================================
-- 0008 ペアリング RPC（発行 / 消費）— 子iPad(匿名) ⇄ 親世帯
--
-- 方針（codex Architect 助言・本筋B）:
--   ペアリングは「DBトランザクション問題」。発行/消費は SECURITY DEFINER の RPC で行う
--   （Edge Function/service_role は使わない）。理由:
--     * 消費を auth.uid() に束縛できる（呼び出し元IDを Postgres/GoTrue が暗号的に検証。
--       Edge+service_role だと JWT から uid を自前で取り出して信用する形になり攻撃面が増える）。
--     * 単回消費の原子性が1トランザクションのCTE（consumed_at is null ガード＋行ロック）で堅い。
--     * 既存 public.create_household() RPC と一貫。
--     * 将来の Edge（App Store通知/APNs/署名URL）はこの RPC を呼べばよい。
--   設計詳細: docs/parent-web-cloud-design.md §4, docs/supabase-sync-design.md §2。
--
-- 契約（バグ源）:
--   * 6桁コードは平文を保存しない。HMAC-SHA256（サーバ pepper 付き）でハッシュ化して保存。
--     生コード空間は 10^6 と小さいので salt では不十分 → pepper（GUC app.pairing_pepper）必須。
--   * 単回・15分失効。消費は consumed_at is null かつ未失効の行を1件だけ原子的に更新。
--   * 消費は匿名(is_anonymous=true)セッション専用。devices.auth_user_id は必ず auth.uid()。
--     クライアントから household_id/profile_id/auth_user_id を受け取らない。
--   * 総当たり対策: 匿名ユーザ単位のレート制限（15分で10回・超過で30分ロック）。
--     想定失敗（誤コード/失効/消費済み）は RAISE せず status 返却（カウンタのロールバック防止）。
--
-- ⚠️ 適用前提: 本番DBに pepper を設定すること（生成コードを検証可能にする唯一の鍵）。
--     ALTER DATABASE postgres SET app.pairing_pepper = '<32+文字のランダム秘密>';
--   未設定なら app.pairing_code_hash() が fail-closed で例外を投げる（誤って空鍵で運用しない）。
-- =============================================================================

-- ----------------------------------------------------------------------------
-- レート制限テーブル（消費の総当たり対策）。RLS 有効・ポリシー無し＝RPC(定義者)のみ書込み。
-- ----------------------------------------------------------------------------
create table if not exists public.pairing_consume_limits (
  auth_user_id      uuid primary key,
  window_started_at timestamptz not null default now(),
  attempt_count     int not null default 0,
  locked_until      timestamptz
);
alter table public.pairing_consume_limits enable row level security;
-- ポリシーは作らない（authenticated/anon は触れない）。RPC は SECURITY DEFINER で更新する。
revoke all on public.pairing_consume_limits from public;
revoke all on public.pairing_consume_limits from anon, authenticated;

-- ----------------------------------------------------------------------------
-- グローバル分バケット制限（総当たり対策の本命）。
-- 攻撃者は匿名サインインを無制限に作れるため「匿名uid単位」の制限だけでは
-- uid を量産すれば回避できる（Security Analyst 指摘・HIGH）。コードは15分で失効するので、
-- 「全体で1分あたりの消費試行」を頭打ちにすれば、1コードの寿命内の総試行数が抑えられ、
-- uid を何個作っても総当たり確率を実質ゼロに保てる（Redis等の追加基盤は不要）。
-- ----------------------------------------------------------------------------
create table if not exists public.pairing_global_throttle (
  minute_bucket timestamptz primary key,
  attempt_count int not null default 0
);
alter table public.pairing_global_throttle enable row level security;
revoke all on public.pairing_global_throttle from public;
revoke all on public.pairing_global_throttle from anon, authenticated;

-- 消費時のアクティブコード探索を速くする部分索引（未消費のみ）。
create index if not exists idx_pairing_codes_active_hash
  on public.pairing_codes(code_hash) where consumed_at is null;

-- ----------------------------------------------------------------------------
-- 既存の潜在バグ修正: pairing_codes は同期/LWW 対象ではない（サーバ内部・クライアント書込み禁止）。
-- 0005 lww_guard は全 public テーブルに付くが updated_at 列を前提とする。pairing_codes には
-- updated_at が無いため、消費(consumed_at の UPDATE)で「record new has no field updated_at」になる。
-- pairing_codes に LWW 意味論は不要なので外す（server_changed_at/sync_version は無害なので残す）。
-- ----------------------------------------------------------------------------
drop trigger if exists trg_aa_lww_guard on public.pairing_codes;

-- ----------------------------------------------------------------------------
-- 内部ヘルパー（app スキーマ・PostgREST 非公開）
-- ----------------------------------------------------------------------------

-- pepper を GUC から取得（未設定は fail-closed）。pgcrypto 不要なので search_path=''。
create or replace function app._pairing_pepper()
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare
  v text := current_setting('app.pairing_pepper', true);
begin
  if v is null or v = '' then
    raise exception 'pairing pepper not configured (set GUC app.pairing_pepper)';
  end if;
  return v;
end;
$$;

-- 6桁コードを HMAC-SHA256(pepper) でハッシュ化（hex）。
-- pgcrypto(hmac) の所在は環境差（ローカル=public / Supabase=extensions）があるため、
-- ここだけ固定の search_path で両方を含める（注入不可・呼び出し元非依存）。
create or replace function app.pairing_code_hash(p_code text)
returns text
language sql stable security definer set search_path = pg_catalog, extensions, public
as $$
  select encode(hmac(p_code, app._pairing_pepper(), 'sha256'), 'hex')
$$;

-- CSPRNG で 6桁コードを生成（gen_random_bytes は pgcrypto）。
create or replace function app.gen_pairing_code()
returns text
language plpgsql volatile security definer set search_path = pg_catalog, extensions, public
as $$
declare
  b bytea := gen_random_bytes(4);
  n bigint;
begin
  -- 4バイト→非負の 32bit 整数 → mod 10^6（6桁の偏りは無視できる範囲）
  n := get_byte(b, 0)::bigint * 16777216
     + get_byte(b, 1)::bigint * 65536
     + get_byte(b, 2)::bigint * 256
     + get_byte(b, 3)::bigint;
  return lpad((n % 1000000)::text, 6, '0');
end;
$$;

revoke all on function app._pairing_pepper() from public;
revoke all on function app.pairing_code_hash(text) from public;
revoke all on function app.gen_pairing_code() from public;
-- これらは SECURITY DEFINER の RPC 内からのみ呼ぶ（定義者権限で実行）ため authenticated への grant は不要。

-- ----------------------------------------------------------------------------
-- 発行: 親（世帯メンバー）が6桁コードを発行。平文コードはこの1回だけ返す。
-- ----------------------------------------------------------------------------
create or replace function public.create_pairing_code(
  p_household_id uuid,
  p_profile_id   uuid default null,
  p_ttl_seconds  int  default 900            -- 15分
)
returns table(code text, expires_at timestamptz)
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_is_anon  boolean := coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false);
  v_code     text;
  v_hash     text;
  -- TTL は 60秒〜900秒(15分)にクランプ（長すぎる有効期限＝総当たりの的を大きくしない）。
  v_expires  timestamptz := now() + make_interval(secs => least(greatest(p_ttl_seconds, 60), 900));
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  if v_is_anon then
    raise exception 'anonymous users cannot create a pairing code';
  end if;
  -- 親メンバーのみ（匿名端末は member ではないのでここで弾かれる）。
  if not app.is_household_member(p_household_id) then
    raise exception 'not a household member';
  end if;
  -- profile を指定するなら同じ世帯のものであること。
  if p_profile_id is not null
     and not exists (
       select 1 from public.profiles
        where id = p_profile_id and household_id = p_household_id and deleted_at is null
     ) then
    raise exception 'profile does not belong to household';
  end if;

  -- アクティブ(未消費・未失効)な同一ハッシュが無いコードを引く。
  for i in 1..10 loop
    v_code := app.gen_pairing_code();
    v_hash := app.pairing_code_hash(v_code);
    -- 同じ6桁コードを同時発行した場合も active duplicate を作らない。
    perform pg_advisory_xact_lock(hashtextextended(v_hash, 0));
    if not exists (
      select 1 from public.pairing_codes pc
       where pc.code_hash = v_hash and pc.consumed_at is null and pc.expires_at > now()
    ) then
      insert into public.pairing_codes(household_id, profile_id, code_hash, expires_at, created_by)
        values (p_household_id, p_profile_id, v_hash, v_expires, v_uid);
      return query select v_code, v_expires;
      return;
    end if;
  end loop;
  raise exception 'could not generate a unique pairing code';
end;
$$;

revoke all on function public.create_pairing_code(uuid, uuid, int) from public;
grant execute on function public.create_pairing_code(uuid, uuid, int) to authenticated;

-- ----------------------------------------------------------------------------
-- 消費: 子iPad(匿名)がコードを入力 → 検証 → devices に登録。
--   返り値 status: 'ok' / 'invalid_or_expired' / 'rate_limited' / 'already_paired'
--   （想定失敗は RAISE せず status。auth/セッション不備のみ例外。）
-- ----------------------------------------------------------------------------
create or replace function public.consume_pairing_code(
  p_code             text,
  p_device_public_id text default null
)
returns table(status text, household_id uuid, profile_id uuid)
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_is_anon  boolean := coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false);
  v_now      timestamptz := now();
  v_hash     text;
  v_limit    public.pairing_consume_limits%rowtype;
  v_attempts int;
  v_hh       uuid;
  v_prof     uuid;
  v_bucket   timestamptz := date_trunc('minute', now());
  v_global   int;
  c_window   constant interval := interval '15 minutes';
  c_maxtry   constant int := 10;
  c_lock     constant interval := interval '30 minutes';
  c_global_max constant int := 60;   -- 全体で 1分あたりの消費試行上限（uid量産による総当たりを抑止）
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  -- 匿名(端末)セッション専用。親アカウントが誤って端末行になるのを防ぐ。
  if not v_is_anon then
    raise exception 'device (anonymous) session required';
  end if;
  -- 端末識別子は短い非秘密文字列。肥大化スパムを弾く。
  if p_device_public_id is not null and length(p_device_public_id) > 128 then
    raise exception 'device_public_id too long';
  end if;

  -- ---- グローバル分バケット制限（uid非依存・総当たりの本命対策） ----
  insert into public.pairing_global_throttle(minute_bucket, attempt_count)
    values (v_bucket, 1)
    on conflict (minute_bucket)
    do update set attempt_count = public.pairing_global_throttle.attempt_count + 1
    returning attempt_count into v_global;
  if v_global > c_global_max then
    return query select 'rate_limited'::text, null::uuid, null::uuid;
    return;
  end if;

  -- ---- レート制限（行ロックで直列化） ----
  insert into public.pairing_consume_limits(auth_user_id, window_started_at, attempt_count)
    values (v_uid, v_now, 0)
    on conflict (auth_user_id) do nothing;
  select * into v_limit from public.pairing_consume_limits
    where auth_user_id = v_uid for update;

  if v_limit.locked_until is not null and v_limit.locked_until > v_now then
    return query select 'rate_limited'::text, null::uuid, null::uuid;
    return;
  end if;

  -- 古い窓はリセット。
  if v_now - v_limit.window_started_at > c_window then
    update public.pairing_consume_limits
      set window_started_at = v_now, attempt_count = 0, locked_until = null
      where auth_user_id = v_uid;
    v_limit.attempt_count := 0;
  end if;

  v_attempts := v_limit.attempt_count + 1;
  update public.pairing_consume_limits
    set attempt_count = v_attempts
    where auth_user_id = v_uid;

  if v_attempts > c_maxtry then
    update public.pairing_consume_limits
      set locked_until = v_now + c_lock
      where auth_user_id = v_uid;
    return query select 'rate_limited'::text, null::uuid, null::uuid;
    return;
  end if;

  -- ---- 形式検証（6桁数字以外はハッシュも引かずに無効）。試行はカウント済み。 ----
  if p_code is null or p_code !~ '^[0-9]{6}$' then
    return query select 'invalid_or_expired'::text, null::uuid, null::uuid;
    return;
  end if;

  -- ---- 既にペアリング済みなら再消費しない ----
  select d.household_id, d.profile_id into v_hh, v_prof
    from public.devices d
    where d.auth_user_id = v_uid and d.revoked_at is null and d.deleted_at is null
    limit 1;
  if found then
    update public.pairing_consume_limits
      set attempt_count = 0, locked_until = null where auth_user_id = v_uid;
    return query select 'already_paired'::text, v_hh, v_prof;
    return;
  end if;

  -- ---- 原子的に1件だけ消費 ----
  v_hash := app.pairing_code_hash(p_code);
  with consumed as (
    update public.pairing_codes pc
       set consumed_at = v_now
     where pc.id = (
        select candidate.id from public.pairing_codes candidate
         where candidate.code_hash = v_hash
           and candidate.consumed_at is null
           and candidate.expires_at > v_now
         order by candidate.created_at
         limit 1
         for update skip locked
     )
     returning pc.household_id, pc.profile_id
  )
  select c.household_id, c.profile_id into v_hh, v_prof from consumed c;

  if not found then
    return query select 'invalid_or_expired'::text, null::uuid, null::uuid;
    return;
  end if;

  -- 端末を登録（auth_user_id は必ず呼び出し元の匿名uid）。
  insert into public.devices(household_id, profile_id, device_public_id, auth_user_id, paired_at)
    values (v_hh, v_prof, p_device_public_id, v_uid, v_now);

  -- 正規ペアリング成功 → 制限リセット。
  update public.pairing_consume_limits
    set attempt_count = 0, locked_until = null where auth_user_id = v_uid;

  return query select 'ok'::text, v_hh, v_prof;
end;
$$;

revoke all on function public.consume_pairing_code(text, text) from public;
grant execute on function public.consume_pairing_code(text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 後片付け（蓄積防止）。匿名uidは無限に作れるため放置すると各表が増え続ける。
-- 定期的に呼ぶ（Supabase なら pg_cron / scheduled Edge から）。クライアントには公開しない。
--   * 消費済み/失効した古いコード
--   * 失効済みの古いコード（未消費でも期限切れ）
--   * 直近に活動の無いレート制限行・ロック解除済み
--   * 古いグローバル分バケット
-- ----------------------------------------------------------------------------
create or replace function app.cleanup_pairing(p_keep interval default interval '1 day')
returns void
language plpgsql volatile security definer set search_path = ''
as $$
begin
  delete from public.pairing_codes
    where (consumed_at is not null and consumed_at < now() - p_keep)
       or (expires_at < now() - p_keep);
  delete from public.pairing_consume_limits
    where window_started_at < now() - p_keep
      and (locked_until is null or locked_until < now());
  delete from public.pairing_global_throttle
    where minute_bucket < now() - p_keep;
end;
$$;
revoke all on function app.cleanup_pairing(interval) from public;
-- 実行は service_role / 定義者（cron）のみ。authenticated には grant しない。
