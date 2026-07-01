-- =============================================================================
-- 0010 words: 保管ステップ／コース紐付けメタの同期列（Ph4）
--
-- 背景: ローカルの SpellingWord は stepID を **String**（実行時に導出する派生 ID。例
--   "2026-06-26-AB12CD34" で端末ごとにランダム接尾辞）で持ち、サーバーの UUID step_id とは一致しない
--   （§7.5）。学校テスト語をコースの階段途中へ「表示だけ」差し込む紐付け
--   （linkedCourseID / linkedBeforeStepID）も、これまで端末ローカルに留まり多端末へ伝搬しなかった。
--
-- 方針: UUID step_id へ写すのではなく、ローカル String をそのまま往復させる text 列を追加する。
--   - storage_step_id      … 保管ステップ（どの登録バッチに属するか）の String を保持。
--   - linked_course_id     … 表示先コース（合成 grade/eiken/dolch）の ID（Course.id）。
--   - linked_before_step_id… そのコースのどの合成ステップ手前に差し込むか（CourseStep.stepID）。
--   いずれも nil 可（紐付け無し）。既存 words_access ポリシー（household 単位 for all）が新列も覆う。
--   フィルタは pull 後にクライアント側で合成するため、追加インデックスは不要。
-- =============================================================================

alter table public.words
  add column if not exists storage_step_id       text,
  add column if not exists linked_course_id      text,
  add column if not exists linked_before_step_id text;
