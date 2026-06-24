# マルチユーザー／マルチデバイス同期 設計（CloudKit 路線）

Status: 設計確定。実装は段階的に着手。
Date: 2026-06-25
決定者: ユーザー（路線・親UIともに本人決定）
レビュー: Codex Architect（advisory, 2026-06-25）反映済み

> **既存の `docs/parent-web-cloud-design.md`（2026-06-07, Supabase + 親Web 案）は本書で supersede（置き換え）された。**
> あちらは「親Webアプリ＋Supabase」を前提にした別路線。本プロジェクトは下記の理由で **CloudKit + ネイティブ親iPhoneアプリ** を選択した。Supabase案は将来 Android/世界展開を本格化する際の参照資料として残置する。

---

## 0. 決定事項（このセッションで確定）

| 項目 | 決定 | 理由 |
|---|---|---|
| バックエンド | **CloudKit**（`NSPersistentCloudKitContainer` + CKShare） | 運用ゼロ・低コストが最優先。子どもデータを自社サーバーに持たない（COPPA/APPI上の利点） |
| 同期エンジン | `NSPersistentCloudKitContainer`（Core Data + CloudKit） | iOS 16 ターゲットのため `CKSyncEngine`（iOS 17+）は不可。ローカル Core Data ストアがオフラインキャッシュを兼ねる |
| 親の体験 | **ネイティブ iPhone アプリ**（既存アプリの親モードを iPhone で利用） | CloudKit と相性が良い。既存に親ゲート/`ParentDashboardView` がある |
| 最低OS | **iOS 16** | 既存 `feat/ios16-downport` 方針を維持 |
| アカウント | 親アカウント1 ＋ 子プロファイル複数 ＋ 端末複数。**子はアプリログインなし** | 子のPIIを最小化 |
| 親子の関係 | **別Apple ID** 前提 → CloudKit **共有DB（CKShare）** を使用 | 親iPhoneと子iPadは別アカウント |
| Android | 「いつかやるかも」止まり | 今フルバックエンドは建てない。ドメイン境界だけ薄く用意し将来の差し替え余地を残す |

Architect 総合評価: **sound-with-changes**。設計の骨格は妥当。ただし「CKShareの導入はユーザー操作を伴うペアリングであり透過同期ではない」「プッシュは best-effort」「競合は record 単位 LWW（field 単位ではない）」を正しく設計に織り込むこと。**実装着手前に 2 つの実 Apple ID を使った CKShare 検証スパイクで前提を実証する**こと。

---

## 1. アーキテクチャ全体像

```
┌──────────────── 子の iPad（doer） ────────────────┐
│ SwiftUI 子UI / PencilKit / OCR / 即時フィードバック │
│ Core Data（ローカル＝オフラインキャッシュ）          │
│   ↕ NSPersistentCloudKitContainer（.shared store）  │
└───────────────────────────┬─────────────────────────┘
                            │  CloudKit（参加者＝子の shared DB）
                  ┌─────────┴──────────┐
                  │  CloudKit 共有ゾーン │  ← 親が所有、CKShare で子を招待
                  │  household zone     │
                  └─────────┬──────────┘
                            │  CloudKit（所有者＝親の private DB）
┌───────────────────────────┴─────────────────────────┐
│ SwiftUI 親モード（管理）/ 採点 / 単語登録 / 記録      │
│ Core Data（ローカル）                                │
│   ↕ NSPersistentCloudKitContainer（.private store）  │
└──────────────── 親の iPhone（manager） ──────────────┘

※ wordbank.sqlite は読み取り専用の同梱参照データ。同期対象外。据え置き。
```

ポイント（Architect 訂正反映）:
- **所有者（親）から見ると共有ゾーンは private DB、参加者（子）から見ると shared DB** に現れる。`NSPersistentCloudKitContainer` の private/shared ストア分割として扱い、自前 CKZone を手動管理する発想にしない。
- 子プロファイルは「アプリ上の概念」。CloudKit アクセス自体には **子端末側にも iCloud サインインが必要**（「子はログインなし」＝アプリアカウントを作らない、の意味）。

---

## 2. アカウント / 世帯 / ペアリング設計

### 2.1 ロールモデル
- **親アカウント = 世帯（household）のオーナー**。CLAUDE.md の「管理する人」と一致。
- **子 = プロファイル**（アプリログインなし）。表示名・学年（任意）・言語・現在ステップ・報酬状態のみ。
- 端末は複数（旅行用iPad・自宅iPad・親iPhone）。

### 2.2 共有（CKShare）= ペアリングフロー（透過同期ではない）
別Apple IDのため、`UICloudSharingController` 等でゾーンを共有する**明示的なペアリング**が必要:

1. 親が「世帯」を作成（親の private DB に household ゾーン相当が生成される）。
2. 親が「子のiPadをつなぐ」→ 共有リンク/招待を発行。
3. **子のiPadは iCloud サインイン済み・オンライン・アプリ導入済み**で招待を受諾。
4. 受諾後、子iPadは共有ストア（`.shared`）の参加者として読み書き。
5. 既存のローカルデータは初回同期でアップロード（→ 第7章 移行）。

**注意（Architect指摘）**: これはプロダクト上の「ペアリング/オンボーディング体験」であり、UIで状態（iCloud未サインイン・招待未受諾・同期待ち）を明示する必要がある。透過的に勝手に繋がるものではない。

### 2.3 権限の限界（重要）
**CKShare の権限は共有単位であって、エンティティ単位ではない。** 子に書き込み権を与えると、CloudKit レベルでは親の単語/設定への書き込みも技術的には防げない。

- **MVP**: 役割の強制は**アプリUI層**で行う（子は採点・単語編集UIを持たない）。子が非敵対的である前提なら許容。
- **強整合が要るなら（将来）**: ゾーン/共有を分割（親管理の単語・設定は子に read-only、子の答案は子が write、親採点は親が write）。複雑度は大きく上がるため MVP では採らない。

---

## 3. データモデル（Core Data + CloudKit 制約準拠）

### 3.1 CloudKit-backed Core Data の鉄則（Architect訂正）
- すべての属性は **optional もしくはデフォルト値必須**。
- **unique 制約を真実の源にしない**（CloudKit はユニーク制約を持てない）。一意性は**ドメインロジックで担保**。
- **必須リレーションシップを作らない**。関連は **UUID のスカラ外部キー ＋ optional な Core Data リレーション** で表現。
- 配列フィールド（現 `WordStep.words[]`）は使わず **join エンティティ** にする。

### 3.2 競合モデル（Architect訂正）
`NSPersistentCloudKitContainer` の競合解決は **record（行）単位の last-writer-wins**。**field 単位マージではない**。したがって「同じ行を親と子が別フィールドで編集」を避ける設計にする:

- **`Attempt`（子の答案）は immutable**（書いたら不変・append-only）。
- **親の採点は別レコード `Review`**（`attemptID` で関連）。
- 子のセッション完了通知トリガは別レコード **`ReviewRequest`**（後述）。
- → 親と子が同一行を奪い合わないので record 単位 LWW で安全。

### 3.3 エンティティ一覧

共通フィールド（全エンティティに付与）: `id: UUID`（アプリ生成・端末横断一意）, `householdID: UUID`, `createdAt`, `updatedAt`, `deletedAt`（tombstone・論理削除）, `deviceID`（任意）。

| エンティティ | 主フィールド | 備考 |
|---|---|---|
| `Household` | id, ownerName?, createdAt | 親=オーナー |
| `Profile`（子） | id, householdID, displayName, appLanguage, activeStepID?, archivedAt? | ログインなし |
| `Word` | id, householdID, profileID, stepID, text(正規化), promptText, source(parent/child), displayOrder | 一意性=profile+step+正規化text をドメインで担保 |
| `Step` | id, householdID, profileID, number, title, registeredDate, isChildStep, sortOrder, archivedAt? | `words[]` 配列は廃止 |
| `StepWordMembership` | id, stepID, wordID, sortIndex | **配列の代替 join**（Architect指摘） |
| `Attempt`（immutable） | id, householdID, profileID, sessionID, stepID, wordID?, expectedWord(スナップ), mode, recognizedText, ocrConfidence?, autoDecision, drawingAsset, submittedAt | 子の答案。書いたら不変 |
| `Review`（親採点・別行） | id, householdID, profileID, attemptID, parentDecision(unreviewed/approved/needsPractice), parentExampleAsset?, reviewedAt, reviewedBy | Attempt と分離 |
| `ReviewRequest`（通知トリガ） | id, householdID, profileID, sessionID, pendingCount, createdAt | セッション完了時に1行作成 → 親の通知計算に使う |
| `SchoolTest` | id, householdID, profileID, stepID, testDate, score, total, note? | 同 child+step+date は upsert |
| `SchoolTestItem` | id, schoolTestID, wordID, expectedWord, result(correct/missed) | |
| `ReviewQueueItem` | id, householdID, profileID, wordID, sourceType, sourceID, status, reason | 復習持ち越し |
| `RewardWallet` | id, profileID, coins, updatedAt | |
| `CharacterUnlock` | id, profileID, characterID, unlockedAt | |
| `ChildSettings` | id, profileID, appLanguage, testPromptMode, speechRate, secondsPerWord, ... | 旧 TestSettings |

### 3.4 手書きデータ
- `PKDrawing.dataRepresentation()` は数KB〜数十KB。**CKAsset（Core Data の external binary + CloudKit asset）** として保存しレコードを軽く保つ。
- 親の手本（`parentExampleAsset`）も同様に asset。
- **暗号化（Architect推奨）**: 手書き・テキスト等の機微フィールドは可能なら encrypted values で保存。ただし**述語検索や通知判定に使うフィールドは暗号化しない**（暗号化フィールドはクエリ不可）。`pendingCount` 等は平文。

---

## 4. 通知設計（最重要かつ最弱点）

要件: 「子が描き終わったら親iPhoneに通知 → 親が採点」。

**現実（Architect指摘）**: `NSPersistentCloudKitContainer` は**同期エンジンであって業務イベントのプッシュ機構ではない**。「`Attempt.state == needsReview` のときだけ親に通知」のような述語レベル制御はできない。サイレントプッシュは best-effort（遅延・スロットリング・強制終了後は届かない・通知許可に依存）。

**採用方針**:
1. 子がセッション完了時に **immutable な `ReviewRequest`** を1行作成（`pendingCount` 入り）。
2. 親端末は CloudKit のリモート変更で起床 → Core Data に import → **永続履歴（persistent history）を検査**して未採点件数を計算。
3. 親アプリが**ローカル通知**を発火（「採点まちが N件」）。
4. UI 側にも「採点まち」バッジを常設し、プッシュが取りこぼされても親が気づける導線にする（プッシュ単独に依存しない）。

**サブスクリプション購読のDBスコープ（Architect訂正）**: 可能な限り Core Data に任せる。手動 `CKSubscription` を足す場合、**親所有ゾーンは親の private DB**、子側ビューは**子の shared DB** に登録する。

**割り切り**: 「確実に即バイブで親に届く」を厳格要件にするなら CloudKit だけでは不足し、APNs を打つサーバーが要る（＝運用ゼロを破る）。本設計は **best-effort 通知 ＋ UI バッジ** で要件を満たす方針。ここはスパイクで体感を確認して受容可否を判断する。

---

## 5. オフラインファースト / 同期

- 子iPadは Wi-Fi 不安定前提。**完全オフライン動作可**、後で同期。
- ローカル Core Data ストアが真実の源（UI はこれを見る）。CloudKit は結果整合で後から反映。
- セッション・答案は **append-only**。親採点は別 `Review` 行で更新。単語/ステップの親編集はオーナー側を優先。
- 子のローカル未同期答案がある単語を親が後から編集しても、`Attempt.expectedWord` はスナップショットを保持し、`wordID` は nullable に倒せるので破綻しない。
- 同期状態（pending/uploading/synced/failed）は基本子に見せない。親/設定の診断にのみ表示。

---

## 6. 抽象化レイヤー（将来 Android の余地・ただし作り込みすぎない）

Architect 指摘: リポジトリ抽象化は今の `@MainActor AppModel` 神オブジェクトの解きほぐしには有効だが、**Android移行を安くする魔法ではない**（Android は新認証・認可・プッシュ・移行・プライバシー・競合意味論を伴う）。Android 確定までフルの「backend-swappable フレームワーク」は作らない。

**今やる薄い境界だけ**:
- ドメイン向けの**狭いストア境界**（`PracticeDataStore` / `SyncStatusService` 程度。エンティティ毎の repository 乱立はしない）。
- **安定 UUID**（オフライン生成）。
- **DTO マッピング**（ドメイン ⇄ 永続化）。
- **export/import の seam**（将来の移行で効く）。

---

## 7. 既存ローカルデータからの移行

現状: `SpellingWord` / `SpellingAttempt` / `PracticeSample` / `SchoolTestResult` / `TestSettings` / 選択ステップ / コイン・キャラ解放 / homeReviewWordIDs を JSON 保存（`AppPersistenceStore`）。

移行（一度きり・冪等・バックアップ取得）:
1. Household / Profile を作成（未作成時）。
2. 日付グループのローカルステップ → `Step`、`SpellingWord` → `Word` ＋ `StepWordMembership`。
3. 各 `sessionID` → セッション概念へ。`SpellingAttempt` → `Attempt`(mode=appTest) ＋（採点済みなら）`Review`。
4. `PracticeSample` → `Attempt`(mode=practice/review)。
5. 手書きデータ → CKAsset 化。
6. `SchoolTestResult` → `SchoolTest` ＋ `SchoolTestItem`。
7. `homeReviewWordIDs` → `ReviewQueueItem`。
8. 報酬 → `RewardWallet` ＋ `CharacterUnlock`。
9. ローカル UUID は可能な限りそのまま CloudKit UUID に踏襲。
10. `wordbank.sqlite` は触らない。

旧 JSON はバックアップとして残し、移行成功フラグが立つまで削除しない。

---

## 8. 実装ロードマップ（Architect推奨順・工数タグ付き）

> 工数: Quick(<1h) / Short(1-4h) / Medium(1-2d) / Large(3d+)

1. **CKShare 検証スパイク** — **Medium**（※実2 Apple ID・親iPhone・子iPad・iOS16 実機が必要＝ユーザー操作を伴う）
   - 共有作成 → 招待受諾 → 所有者private/参加者shared の確認 → 子オフライン答案 → 後続同期 → 共有取消 → iCloud未サインイン時の挙動。
2. **通知スパイク** — **Short/Medium**
   - 使い捨て `ReviewRequest` で、親端末がリモート変更を import → ローカル通知発火を確認。best-effort の体感を判断。
3. **データモデル再設計** — **Medium**
   - `Household/Profile/Word/Step/StepWordMembership/Attempt(immutable)/Review/ReviewRequest/...`、tombstone・UUID・optional/デフォルト・optional リレーション。
4. **永続化境界の導入** — **Short**
   - 狭い `PracticeDataStore`/`SyncStatusService`。エンティティ毎 repository 乱立は避ける。
5. **JSON → Core Data 移行** — **Medium**
   - 冪等・バックアップ・UUID 付与・検証。`wordbank.sqlite` 不変。
6. **共有オンボーディングUX** — **Medium/Large**
   - 親が世帯作成→子招待→子受諾。アカウント/共有/同期状態の可視化。
7. **競合・オフライン試験マトリクス** — **Large**
   - 親採点 vs 子同期の同時、重複UUID、削除単語、古い端末、共有取消、quota/account エラー、通知遅延。

---

## 9. 段階リリースの考え方
- **Step 3-5（土台）は単一端末でも価値があり、CloudKit を有効化しなくても壊れない**（ローカル Core Data 化＋境界＋移行）。ここを先に固めるのが no-regret。
- CloudKit 同期・CKShare・通知（Step 1,2,6,7）は実機2台＋2 Apple ID の検証とセット。
- もし CKShare がスパイクで想定以上に難航したら、薄い境界のおかげで Supabase 案（`parent-web-cloud-design.md`）へ低コスト旋回できる（保険）。

---

## 10. 未決事項（設計承認をブロックしない）
- 親アプリを「同一バイナリの親モード」にするか、ターゲット分離するか（推奨: 同一アプリの親モード）。
- 暗号化の対象フィールド範囲（手書き/認識テキストは暗号化、`pendingCount` 等の判定用は平文）。
- 通知が best-effort で実運用に耐えるか（スパイクで判断。不足なら将来 APNs サーバーを別途検討）。
- 複数子・複数親メンバーの共有粒度（MVP は単一共有、将来ゾーン分割）。

## 11. 参考
- Apple: Building apps that share data through CloudKit and Core Data（WWDC）
- Apple: Using Core Data with CloudKit / NSPersistentCloudKitContainer sharing（iOS 15+）
- 旧路線参照: `docs/parent-web-cloud-design.md`（Supabase + 親Web 案・supersededed）
