-- =============================================================================
-- 0629_4t7k  運用テレメトリ event_log（送信専用テーブル）
-- 目的: 不具合発見と機能改善に効く「運用ログ＋低頻度セッション要約」を、Supabase に
--       負荷をかけず確実に集める土台。
-- 設計: docs/telemetry-design.md
--
-- 【重要な性質（同期テーブルと別物）】
--  * append-only の **送信専用**。クライアントからは INSERT のみ。SELECT/UPDATE/DELETE 不可。
--  * sync_version / updated_at / deleted_at を **持たない**（pull もしない・LWW も tombstone もしない）。
--  * よって 0005 の lww_guard / 0006 の sync_version トリガ網（作成当時のテーブルにのみ付与）は
--    この表には掛からない。今後それらのループを再実行しないこと（updated_at 不在で壊れる）。
--  * 児童プライバシー: payload は低カーディナリティ値のみ。氏名・手書き・自由入力・生年月日は載せない。
--    profile_id は既定 NULL（行動分析目的で安易に付けない。障害切り分けに要る時だけ）。
-- =============================================================================

create table if not exists public.event_log (
  event_id     uuid primary key,                       -- 端末生成の決定論UUID（再送の冪等キー）
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid references public.profiles(id) on delete set null,
  device_id    uuid not null,                          -- 非秘密の端末識別子
  occurred_at  timestamptz not null,                   -- 端末でのイベント発生時刻（UTC）
  received_at  timestamptz not null default now(),     -- サーバ受信時刻（クライアントは送らない）
  severity     smallint not null
                 check (severity in (20, 30, 40, 50)), -- info/warn/error/fatal
  category     text not null
                 check (category in ('sync','ocr','crash','telemetry','session')),
  code         text not null
                 check (char_length(code) between 1 and 64
                        and code in (
                          'sync.pull_failed',
                          'sync.push_failed',
                          'ocr.failed',
                          'crash.mx_diagnostic',
                          'telemetry.dropped',
                          'session.practice_summary'
                        )),                             -- ★ allowlist。拡張は意図的にマイグレーション必須
  app_version  text not null check (char_length(app_version) <= 32),
  os_version   text not null check (char_length(os_version) <= 32),
  payload      jsonb
                 check (payload is null
                        or octet_length(payload::text) <= 2048)  -- payload サイズ上限（巨大化防止）
);

-- 索引: 世帯ごとの時系列（ダッシュボード）＋ エラー以上の調査（部分索引で軽量）。
create index if not exists idx_event_log_household_time
  on public.event_log (household_id, occurred_at desc);
create index if not exists idx_event_log_error_code
  on public.event_log (code, occurred_at desc)
  where severity >= 40;

-- ============================ RLS: INSERT-only ===============================
-- SELECT/UPDATE/DELETE ポリシは **作らない** ＝ クライアントからは読めない・消せない（append-only 担保）。
-- INSERT は「自分の世帯（親メンバー or 紐づく端末）」の行のみ許可（既存 app.has_access を再利用）。
alter table public.event_log enable row level security;

-- 直接 INSERT 用ポリシ（多層防御）。実際の書き込みは下の RPC 経由だが、万一 grant が付いても
-- 自世帯以外には書けないようにしておく。
create policy event_log_insert_own_household on public.event_log
  for insert to authenticated
  with check (app.has_access(household_id, profile_id));

-- クライアントにはテーブル権限を **一切与えない**（SELECT/INSERT/UPDATE/DELETE すべて不可）。
--  → event_log は読めない・改竄/削除できない＝真の送信専用 append-only。
-- 書き込みは下記 SECURITY DEFINER RPC `log_events` 経由のみ（冪等送信を安全に行うため）。
revoke all on public.event_log from anon, authenticated;

-- ============================ 送信 RPC（冪等・一括） =========================
-- なぜ RPC か（直接 INSERT…ON CONFLICT DO NOTHING を使わない理由）:
--   * ON CONFLICT DO NOTHING は競合検査に SELECT 権限を要求し、さらに RLS 下では
--     「競合した既存行が SELECT ポリシで可視」でないと "new row violates RLS" を投げる。
--     送信専用で SELECT ポリシを作らない方針と両立しない（再送＝冪等の肝が壊れる）。
--   * SECURITY DEFINER で RLS をバイパスしつつ、関数内で `app.has_access` により
--     「呼び出し元が自世帯にだけ書ける」ことを行ごとに検証する（auth.uid() は呼び出し元のまま）。
-- 入力: events = イベントオブジェクトの JSON 配列。戻り: 実際に INSERT した件数（重複は除く）。
create or replace function public.log_events(events jsonb)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  e jsonb;
  hid uuid;
  pid uuid;
  inserted integer := 0;
begin
  if jsonb_typeof(events) is distinct from 'array' then
    raise exception 'events must be a JSON array';
  end if;
  if jsonb_array_length(events) > 200 then
    raise exception 'too many events in one call (max 200)';
  end if;

  for e in select * from jsonb_array_elements(events) loop
    hid := (e ->> 'household_id')::uuid;
    pid := nullif(e ->> 'profile_id', '')::uuid;

    -- 自世帯にだけ書ける（親メンバー or 紐づく端末）。それ以外は拒否（一括失敗）。
    if hid is null or not app.has_access(hid, pid) then
      raise exception 'access denied for household %', hid using errcode = '42501';
    end if;

    insert into public.event_log(
      event_id, household_id, profile_id, device_id, occurred_at,
      severity, category, code, app_version, os_version, payload
    ) values (
      (e ->> 'event_id')::uuid, hid, pid, (e ->> 'device_id')::uuid,
      (e ->> 'occurred_at')::timestamptz, (e ->> 'severity')::smallint,
      e ->> 'category', e ->> 'code', e ->> 'app_version', e ->> 'os_version',
      case when (e ? 'payload') then e -> 'payload' else null end
    )
    on conflict (event_id) do nothing;  -- 冪等: 再送は握りつぶす（UPDATE 経路に入らない）

    if found then
      inserted := inserted + 1;
    end if;
  end loop;

  return inserted;
end;
$$;

revoke all on function public.log_events(jsonb) from public, anon;
grant execute on function public.log_events(jsonb) to authenticated;

comment on table public.event_log is
  '運用テレメトリ（送信専用・append-only・クライアントからは読めない）。書き込みは RPC log_events 経由のみ。設計: docs/telemetry-design.md';
comment on function public.log_events(jsonb) is
  'event_log への冪等一括送信（SECURITY DEFINER・has_access で自世帯限定）。クライアントの唯一の書き込み口。';
comment on column public.event_log.profile_id is
  '既定 NULL。行動分析目的で安易に付けない（児童プライバシー）。障害切り分けに要る時のみ。';
comment on column public.event_log.payload is
  '低カーディナリティ値のみ（バケット/フラグ/列挙）。氏名・手書き・自由入力・生年月日は禁止。<=2KB。';
