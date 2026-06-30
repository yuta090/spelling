-- OCR ベンチ用スキーマ（アプリの同期スキーマとは分離した専用テーブル）
-- Supabase の SQL Editor で実行する。
--
-- 設計（収集ファースト）:
--   - アプリが「普通に使われた手書き」をこのテーブル＋Storageバケット ocr-bench に収集する。
--   - 収集時点では ground_truth / legible は NULL（＝未ラベル）。
--   - あとで人が画像を見て ground_truth（実際に書かれた文字）と legible を埋める＝ラベル付け。
--   - bench.py は「ラベル済み（ground_truth IS NOT NULL）」の行だけ全モデルに投入する。
--   - target（出題語）と ground_truth を分けることで 誤受理/誤拒否/捏造 を機械的に測れる。

create table if not exists public.ocr_bench_samples (
  id            uuid primary key default gen_random_uuid(),
  storage_path  text not null,              -- バケット ocr-bench 内のパス（例: 2026-06-27/uuid.png）
  target        text not null,              -- 出題された単語（子が書くべき語）

  -- ↓ アプリが収集時に入れる（参考情報。ラベルではない）
  local_ocr     text,                       -- アプリのローカルOCR(VNRecognizeText)の読み取り結果
  local_correct boolean,                    -- ローカル採点が「正解」と判定したか
  source        text,                       -- 'session' | 'test' など、どの画面からか
  device_hint   text,                       -- 端末/プロフィールの匿名識別（任意・分析用）

  -- ↓ 人があとで埋める（ラベル）
  ground_truth  text,                        -- 実際に書かれた文字（NULL=未ラベル）
  legible       boolean,                     -- 人が読めるか（NULL=未ラベル / 判読不能サンプルは false）
  neatness      smallint,                    -- 字の丁寧さの人手ラベル 1〜4（NULL=未ラベル / 任意）。
                                             -- 綴り正誤とは独立。モデルの neatness 判定の人手一致を測る用。
  constraint ocr_bench_samples_neatness_range
    check (neatness is null or neatness between 1 and 4),

  created_at    timestamptz not null default now()
);

-- 既存テーブルへの後付け（create table if not exists は既存テーブルを変更しないため、再実行で安全に列追加）。
alter table public.ocr_bench_samples
  add column if not exists neatness smallint;
do $$ begin
  alter table public.ocr_bench_samples
    add constraint ocr_bench_samples_neatness_range
    check (neatness is null or neatness between 1 and 4);
exception when duplicate_object then null; end $$;

-- 未ラベルを探しやすく
create index if not exists ocr_bench_samples_unlabeled
  on public.ocr_bench_samples (created_at)
  where ground_truth is null;

-- RLS 有効化（収集はアプリの認証ユーザー、ベンチ実行は service_role キーでバイパス）。
alter table public.ocr_bench_samples enable row level security;

-- アプリ（authenticated）からの INSERT を許可。読み取り/更新は service_role か別ポリシーで。
-- ※ 収集をオプトインのテスターだけにするなら、アプリ側のフラグで制御する。
drop policy if exists "authenticated can insert captures" on public.ocr_bench_samples;
create policy "authenticated can insert captures"
  on public.ocr_bench_samples for insert
  to authenticated
  with check (true);

-- private バケット（ダッシュボード Storage で作ってもよい）。
insert into storage.buckets (id, name, public)
values ('ocr-bench', 'ocr-bench', false)
on conflict (id) do nothing;

-- Storage への INSERT（アップロード）を authenticated に許可（ocr-bench バケットのみ）。
drop policy if exists "authenticated can upload ocr-bench" on storage.objects;
create policy "authenticated can upload ocr-bench"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'ocr-bench');

-- ラベルの取り方:
--   truth_correct = normalize(ground_truth) == normalize(target)
--   正しく書けた  -> ground_truth == target
--   スペルミス    -> 例) target='because', ground_truth='becuase'
--   判読不能      -> legible=false, ground_truth は意図/最良推定（捏造検出用）
--   丁寧さ        -> neatness 1〜4（任意）。綴り正誤と無関係に「字の整い」だけで付ける。
--                    1=読みにくい 2=ふつう 3=きれい 4=お手本級。モデルの neatness 判定の人手一致を測る用。
