-- =============================================================================
-- 0002 Learning data
-- ステップ/単語/答案/採点/復習/SRS/学校テスト/ゴール/報酬/設定。
-- すべて household_id を持ち（非正規化＝policy高速化）、app.has_access で隔離。
-- 共通列: id, household_id, profile_id, created_at, updated_at, deleted_at
-- 競合は record単位 last-write-wins（updated_at はクライアント設定可。既定 now()）。
-- =============================================================================

-- ステップ
create table if not exists public.steps (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references public.households(id) on delete cascade,
  profile_id      uuid references public.profiles(id) on delete cascade,
  number          int  not null default 1,
  title           text not null default '',
  registered_date date,
  is_child_step   boolean not null default false,
  sort_order      int  not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

-- 単語（英検級ラベルは親のみ。子には見せない＝アプリ層で制御）
create table if not exists public.words (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  profile_id    uuid references public.profiles(id) on delete cascade,
  step_id       uuid references public.steps(id) on delete set null,
  text          text not null,                 -- 正規化済みの綴り
  prompt_text   text not null default '',       -- 日本語訳/ヒント（ふりがな可）
  source        text not null default 'parent' check (source in ('parent','child')),
  display_order int  not null default 0,
  eiken_grade   text,                           -- '5','4','3','pre-2' 等（親のみ表示）
  ngsl_rank     int,
  dolch         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- ステップ⇔単語の多対多（配列の代替 join）
create table if not exists public.step_word_memberships (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid references public.profiles(id) on delete cascade,
  step_id      uuid not null references public.steps(id) on delete cascade,
  word_id      uuid not null references public.words(id) on delete cascade,
  sort_index   int  not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (step_id, word_id)
);

-- 答案（子の出力・不変＝append-only）
create table if not exists public.attempts (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references public.households(id) on delete cascade,
  profile_id      uuid references public.profiles(id) on delete cascade,
  session_id      uuid not null,
  step_id         uuid,
  word_id         uuid,
  expected_word   text not null default '',     -- スナップショット
  mode            text not null default 'test', -- practice/test/review
  recognized_text text not null default '',
  ocr_confidence  real,
  auto_decision   text not null default 'needsReview',
  drawing_path    text,                          -- Storage/R2 のキー
  submitted_at    timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

-- 親採点（Attempt と分離した別行）
create table if not exists public.reviews (
  id                  uuid primary key default gen_random_uuid(),
  household_id        uuid not null references public.households(id) on delete cascade,
  profile_id          uuid references public.profiles(id) on delete cascade,
  attempt_id          uuid not null references public.attempts(id) on delete cascade,
  parent_decision     text not null default 'unreviewed' check (parent_decision in ('unreviewed','approved','needsPractice')),
  parent_example_path text,
  reviewed_by         uuid,
  reviewed_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  unique (attempt_id)
);

-- 通知トリガ（セッション完了時に作成。pending_count = 採点待ち件数）
create table if not exists public.review_requests (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  profile_id    uuid references public.profiles(id) on delete cascade,
  session_id    uuid not null,
  pending_count int  not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- SRS（Leitner）定着状態。SRSScheduler と一致。
create table if not exists public.srs_cards (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references public.households(id) on delete cascade,
  profile_id       uuid references public.profiles(id) on delete cascade,
  word_id          uuid not null references public.words(id) on delete cascade,
  box              int  not null default 1 check (box between 1 and 5),
  last_reviewed_at timestamptz,
  due_at           timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (profile_id, word_id)
);

-- 学校テスト
create table if not exists public.school_tests (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid references public.profiles(id) on delete cascade,
  step_id      uuid,
  test_date    date,
  score        int  not null default 0,
  total        int  not null default 1,
  note         text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create table if not exists public.school_test_items (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  profile_id     uuid references public.profiles(id) on delete cascade,
  school_test_id uuid not null references public.school_tests(id) on delete cascade,
  word_id        uuid,
  expected_word  text not null default '',
  result         text not null default 'correct' check (result in ('correct','missed')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- 復習持ち越し
create table if not exists public.review_queue_items (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid references public.profiles(id) on delete cascade,
  word_id      uuid not null references public.words(id) on delete cascade,
  source_type  text not null default 'app_test',
  source_id    uuid,
  status       text not null default 'open' check (status in ('open','assigned','cleared','dismissed')),
  reason       text not null default 'missed',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- 英検/試験ゴール（出題逆算）
create table if not exists public.goals (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid references public.profiles(id) on delete cascade,
  kind         text not null default 'eiken' check (kind in ('eiken','exam')),
  target_grade text,
  target_date  date,
  daily_goal   int not null default 10,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- 報酬・キャラ・設定（per profile）
create table if not exists public.reward_wallets (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  coins        int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (profile_id)
);
create table if not exists public.character_unlocks (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  character_id text not null,
  unlocked_at  timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (profile_id, character_id)
);
create table if not exists public.child_settings (
  id                  uuid primary key default gen_random_uuid(),
  household_id        uuid not null references public.households(id) on delete cascade,
  profile_id          uuid not null references public.profiles(id) on delete cascade,
  app_language        text not null default 'japanese',
  test_prompt_mode    text not null default 'audioOnly',
  speech_rate         real not null default 0.42,
  seconds_per_word    int  not null default 30,
  practice_repetitions int not null default 3,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  unique (profile_id)
);

-- 索引（policy列）
create index if not exists idx_steps_hh        on public.steps(household_id);
create index if not exists idx_words_hh         on public.words(household_id);
create index if not exists idx_swm_hh           on public.step_word_memberships(household_id);
create index if not exists idx_attempts_hh      on public.attempts(household_id);
create index if not exists idx_attempts_session on public.attempts(session_id);
create index if not exists idx_reviews_hh       on public.reviews(household_id);
create index if not exists idx_revreq_hh        on public.review_requests(household_id);
create index if not exists idx_srs_hh           on public.srs_cards(household_id);
create index if not exists idx_srs_due          on public.srs_cards(profile_id, due_at);
create index if not exists idx_stests_hh        on public.school_tests(household_id);
create index if not exists idx_stitems_hh       on public.school_test_items(household_id);
create index if not exists idx_rqi_hh           on public.review_queue_items(household_id);
create index if not exists idx_goals_hh         on public.goals(household_id);
create index if not exists idx_wallets_hh       on public.reward_wallets(household_id);
create index if not exists idx_unlocks_hh       on public.character_unlocks(household_id);
create index if not exists idx_csettings_hh     on public.child_settings(household_id);

-- ================================ RLS ========================================
alter table public.steps                 enable row level security;
alter table public.words                 enable row level security;
alter table public.step_word_memberships enable row level security;
alter table public.attempts              enable row level security;
alter table public.reviews               enable row level security;
alter table public.review_requests       enable row level security;
alter table public.srs_cards             enable row level security;
alter table public.school_tests          enable row level security;
alter table public.school_test_items     enable row level security;
alter table public.review_queue_items    enable row level security;
alter table public.goals                 enable row level security;
alter table public.reward_wallets        enable row level security;
alter table public.character_unlocks     enable row level security;
alter table public.child_settings        enable row level security;

-- 標準ポリシー（has_access：親=全プロファイル / 端末=自分のプロファイル）
create policy steps_access on public.steps for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy words_access on public.words for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy swm_access on public.step_word_memberships for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy revreq_access on public.review_requests for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy srs_access on public.srs_cards for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy stests_access on public.school_tests for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy stitems_access on public.school_test_items for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy rqi_access on public.review_queue_items for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy goals_access on public.goals for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy wallets_access on public.reward_wallets for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy unlocks_access on public.character_unlocks for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));
create policy csettings_access on public.child_settings for all
  using (app.has_access(household_id, profile_id)) with check (app.has_access(household_id, profile_id));

-- 特例1: attempts は append-only（SELECT + INSERT のみ。UPDATE/DELETE ポリシー無し＝拒否）
create policy attempts_select on public.attempts for select
  using (app.has_access(household_id, profile_id));
create policy attempts_insert on public.attempts for insert
  with check (app.has_access(household_id, profile_id));

-- 特例2: reviews は閲覧=has_access、採点(書込み)=親のみ
create policy reviews_select on public.reviews for select
  using (app.has_access(household_id, profile_id));
create policy reviews_parent_write on public.reviews for insert
  with check (app.is_household_member(household_id));
create policy reviews_parent_update on public.reviews for update
  using (app.is_household_member(household_id)) with check (app.is_household_member(household_id));
