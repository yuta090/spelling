# 複数子プロファイル／ユーザー切り替え — 設計

Status: REVIEWED（codex Architect レビュー反映済み・実装未着手）
Date: 2026-07-01
Branch: `feat/multi-child-profiles-20260701-mc7k`
Review: codex Architect = REQUEST CHANGES → 指摘6点を §3.1 / §4 / §5 / §6 / §9 に反映済み（2026-07-01）
関連:
- 意思決定ログ: `docs/multi-user-and-strategy-decisions.md`（**D3 / §5** が本設計の親決定）
- 同期設計: `docs/supabase-sync-design.md` / `Sources/SpellingSyncCore/`（`profileId` 実装済み）
- 課金: `docs/monetization-spec-2026-06-27.md` / `docs/freemium-impl-design-2026-06-27.md`
- UI/UX 方針: `CLAUDE.md`（子=やる人 / 親=管理）

---

## 0. ひとことサマリー

- **やること**：1台の iPad を**兄弟（複数の子）で共有**し、子ども単位でデータ（進捗・コース・SRS・ごほうび・手書き等）を分けて**切り替え**られるようにする。
- **既に確定していること（再掲）**：
  - **D3**：アカウント＝**親1＋子プロファイル複数**＋端末複数、子はログインなし。→ **複数子プロファイルは確定仕様**（サーバ側 `profileId` が全同期DTOに通っている理由）。
  - **§5 / Q3**：価格 **¥580/月・¥4,800/年（家族込み）**。→ **課金は「家族まとめて1本」**が既定。子ごとの別課金ではない（§7で再確認）。
- **現状のギャップ**：**サーバ/同期層は複数プロファイル対応済み**だが、**アプリ本体（ローカル永続化＋UI）は子ども1人固定**。本設計は**このクライアント側ギャップを埋める**もの。
- **設計の核**：永続化の**キー名前空間化**（子ども別キーを `activeProfileID` で prefix、端末/世帯グローバルなキーは素通し）。純ロジックは `SpellingSyncCore` に置き TDD。

---

## 1. 現状（As-Is）

| 層 | 複数子対応 | 実体 |
|---|---|---|
| Supabase / 同期 | ✅ 対応済み | `household（世帯）→ profiles` テーブル、`profileId: UUID` が SyncDTO・`SyncMetadata`・ペアリングコードまで貫通 |
| `SpellingSyncCore` | ✅ 対応済み | LWW/tombstone/移行/SRS が `profileID` を持つ |
| アプリ本体（`AppModel`） | ❌ 単一子固定 | `childName: String` 1人、`activeCourse` 1つ、進捗/復習/SRS/ごほうびが**固定キー1組**（`spellingTrainer.*`） |
| UI | ❌ なし | プロファイル選択・切り替え・管理の画面が存在しない |

`AppModel.init(persistenceStore:)` が固定キー約35個を直接ロードしている（`iPadPrototype/AppModel.swift:472–579`）。**この固定キー群が単一子前提の正体**。

---

## 2. モデル設計（To-Be）

### 2.1 `ChildProfile`（新規・`SpellingSyncCore`）
```
public struct ChildProfile: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID            // ローカル生成。サーバ profiles.id と対応づけ（§6）
    public var displayName: String // 子のニックネーム（旧 childName の移設先）
    public var avatarID: String    // ランチャーの顔＝既存 なかま/アバター資産の ID を流用
    public var colorHex: String    // カード色（見た目言語の再利用）
    public var createdAt: Date
    public var sortIndex: Int      // 並び順（親が並べ替え）
}
```
- **displayName・avatar は「切り替え画面で自分を選べる手掛かり」**。字が読めない子でも顔で選べる（CLAUDE.md「アイコン＋音で伝える」）。

### 2.2 `ProfileRegistry`（新規・純ロジック・`SpellingSyncCore`・TDD対象）
プロファイル一覧と「今アクティブな子」を保持する純データ＋操作。**I/O を持たない**（保存は呼び出し側）。
```
public struct ProfileRegistry: Equatable, Codable, Sendable {
    public private(set) var profiles: [ChildProfile]
    public private(set) var activeProfileID: UUID

    // 純操作（全て新 Registry を返す・決定論）
    func adding(name:avatar:color:now:) -> (ProfileRegistry, ChildProfile)
    func removing(_ id: UUID) -> ProfileRegistry          // 最後の1人は消せない（不変条件）
    func renaming(_ id:to:) -> ProfileRegistry
    func activating(_ id: UUID) -> ProfileRegistry        // 存在しないIDは無視
    func reordering(_ orderedIDs:[UUID]) -> ProfileRegistry
}
```
**不変条件**：`profiles.count >= 1` かつ `activeProfileID ∈ profiles`。テストで固定する。

---

## 3. 永続化の名前空間化（★設計の核心）

### 3.1 方針
`UserDataStore` を**ラップ**する `ProfileScopedStore` を挟み、**子ども別キーだけ** `profiles/<activeProfileID>/<key>` に prefix する。**グローバルキーは素通し**。
- **`AppModel` 内のキー文字列は一切変えない**（`"spellingTrainer.words"` のまま）。prefix はストアが行う → **`AppModel` の変更を最小化**。
- グローバルキーの集合（whitelist）をストアに渡し、それだけ prefix しない。

```
final class ProfileScopedStore: UserDataStore {  // @unchecked Sendable
    let base: UserDataStore
    private let lock = NSLock()
    private var _activeProfileID: UUID            // lock 保護
    let globalKeys: Set<String>     // 下表「グローバル」
    // load/save: globalKeys に含まれれば key をそのまま、含まれなければ "profiles/\(activeProfileID)/\(key)"
}
```
`AppModel` は生成時に**素の store を `ProfileScopedStore` で包んだもの**を受け取る。切り替え時は `activeProfileID` を差し替え、後述の `reloadChildScopedState()` を呼ぶ。

**Swift 6 並行性（★レビュー指摘⑤）**：`UserDataStore` は `Sendable` だが `ProfileScopedStore` は**可変の `activeProfileID`** を持つ。async な同期/テレメトリ経路がストアに触れるためレースになりうる。方針を1つに固定する：
- `_activeProfileID` を **`NSLock` で保護**し `@unchecked Sendable`（採用）。読み書きは常にロック越し。
- 併せて `AppModel` は `@MainActor` 前提（既存踏襲）で、切替は main で直列化。
- **切替の原子性**：`activeProfileID` の差し替えと `reloadChildScopedState()` の間に非同期保存が割り込まないよう、切替中は保存経路を止める（§4 のガードと同一）。

### 3.2 キー分類（`AppModel.swift:472–512` を全件分類）

**子ども別（prefix する）**
| キー | 内容 |
|---|---|
| `words` / `attempts` / `practiceSamples` / `schoolTestResults` | 単語・答案・手書きサンプル・学校テスト結果 |
| `settings` | テスト設定（子ごとに難易度が違う） |
| `selectedCourseID` / `selectedStepIDByCourse` / `selectedWordStepID`(legacy) | コース選択・ステップ位置 |
| `childCanSwitchCourses` / `allowedCourseIDs` / `requiredCompletion` | コース制約（親が子ごとに設定） |
| `rewardCoins.v2` / `rewardCoins`(legacy) | ごほうびコイン残高 |
| `loginStreak` / `lastLoginDay` / `lastPerfectBonusDay` | 継続・ボーナス |
| `puzzleLastPlayedDay` / `puzzlePlaysToday` | パズル日次カウンタ |
| `selectedCharacterID` / `unlockedCharacterIDs` / `selectedBackgroundID` / `unlockedBackgroundIDs` | 見た目のアンロック |
| `homeReviewWordIDs` | ホーム復習 |
| `usageLog` | 利用時間（親「ようす」で子ごとに見る） |
| `grammarReviewStates` / `grammarReviewStep` / `spellingReviewStates` / `spellingReviewStep` / `spellingReviewSeeded` | 復習注入エンジン状態 |
| `hasShownHomeCharacterHint` / `stepUnlockCelebration` | 演出の1回制御 |
| `childName` → `displayName` へ移設 / `selectedGrade` | 名前・学年 |
| `cast` | 例文パーソナライズ（本人＋友達。**未成年実名＝ローカルのみ**を維持） |
| `hasCompletedOnboarding` | **プロファイル別**（新しい子は名前・学年のミニ設定を通す） |

**グローバル（端末/世帯・prefix しない）**
| キー | 理由 |
|---|---|
| `cachedEntitlement` | **サブスクは家族＝世帯単位**（§5 家族込み）。全プロファイルで共有 → §7 の核心 |
| `debugUnlockAll` / `debugDisableDailyLimit` | 開発フラグ（端末） |
| `migratedFromSwiftData.v1` | 端末の移行フラグ |
| `sync.activeHouseholdID` | 世帯は端末/アカウント単位 |
| `sync.wordSidecar` / `sync.cursors` | 同期簿記。**Phase 5 で (世帯,プロファイル) 別に見直し**（現状は素通しでも動くが要注記） |
| **新規** `profiles`（Registry） / `activeProfileID` | プロファイル台帳そのもの（端末） |

---

## 4. `AppModel` リファクタ戦略

1. `init` の**ロード本体を抽出** → `private func loadChildScopedState()`。init と「切り替え時」で共用する。
   - グローバル系（entitlement/debug）は `init` に残す。子ども別 @Published 群だけ `loadChildScopedState()` に移す。
2. `activateProfile(_ id: UUID)`（**切替は原子的に**・★レビュー指摘④）：
   - **pending な debounced sync をキャンセル**（切替前の子の同期が新しい子に紐づくのを防ぐ）
   - `isReloadingProfile = true`（ガード ON）
   - `registry = registry.activating(id)` → 保存 / `scopedStore.activeProfileID = id`
   - `loadChildScopedState()` で全 @Published を再ロード（SwiftUI が再描画）
   - `isReloadingProfile = false` の**後で**、修復・seeding・同期要求を**意図的に**実行（例：`ensureSelectedWordStepStillExists()`、`requestSync()`）
   - `AppModel` インスタンスは**作り直さない**（View ツリーが依存するため）。あくまで**中身の入れ替え**。
3. `childName`（★レビュー指摘⑥）：`registry.active.displayName` を**単一の真実（SSOT）**にする。`spellingTrainer.childName` は**移行元としてのみ**参照し、移行後は子スコープの `childName` キーに保存しない。`AppModel.childName` は Registry へブリッジ（改名/追加フローと二重ソースにしない）。

**リスク（★レビュー指摘④の核心）**：`didSet` は保存だけでなく**副作用**も呼ぶ。例：`words.didSet` → `ensureSelectedWordStepStillExists()` ＋ `requestSync()`。再ロード中にこれらが**間違ったプロファイルで**発火しうる。
- **`isReloadingProfile` ガードを「保存」だけでなく全 `didSet` 副作用（派生修復・sync 要求）に張る**。
- **debounced sync は `profileID` をキャプチャ**して発火時に「今のアクティブと一致」を確認（不一致なら破棄）。
- テストで「A→B→A でデータ非混在」「切替中に他児へ sync が飛ばない」を固定する。

---

## 5. マイグレーション（既存単一子 → プロファイル#1）

未リリース（CLAUDE.md）だが**開発中の自分のテストデータは壊さない**。既存の移行実装（SwiftData→file、コイン×10）と同じ**冪等・フラグ管理**の作法に合わせる。

- 初回起動で `spellingTrainer.profiles` が無ければ：
  1. `ChildProfile #1` を生成（`displayName = 既存 childName`、avatar=既定、`id = 新UUID`）。
  2. **既存の子ども別固定キーを `profiles/<id1>/<key>` へコピー**（1回限り・`migratedToProfiles.v1` フラグでガード）。
  3. `activeProfileID = id1`、`profiles=[#1]` を保存。
- グローバルキー（entitlement 等）は**触らない**。
- **★レビュー指摘②：同期バリアが必須**。`AppPersistenceStore.save` は `persistenceQueue.async` で**非同期書き込み**。素直にやると「コピー未完了のまま registry/フラグが立つ」→ 次回ロードで空になる。**書き込み順序を保証する**：
  1. 全コピーを **`persistenceQueue` 上で同期実行**（`persistenceQueue.sync { … }` かバリア）し、書き込み完了を待つ／読み戻し検証する。
  2. **その後で** `profiles` / `activeProfileID` を保存。
  3. **最後に** `migratedToProfiles.v1` フラグを立てる（＝途中失敗なら次回再試行・冪等）。
  - **コピー対象キーは単一の定数配列**（`ChildScopedKeys.all`）にまとめ、**移行・`ProfileScopedStore.globalKeys` の補集合・テスト**で共有（キー分類の二重管理を防ぐ）。
- **★レビュー指摘③：「#1 だけ prefix 無し」は常設にしない**。同期マッピング（§6）が #1 だけ特殊化して破綻源になる。**copy 移行を唯一の正規経路**とする。prefix 無し読取りは「移行が壊れた時の緊急リカバリ（read-only）」としてのみ言及し、実装の fallback にはしない。

---

## 6. 同期（Supabase）との対応

- ローカル `ChildProfile.id`（UUID）⇄ サーバ `profiles.id` を**対応づけ**る。世帯（`activeHouseholdID`）は既存のまま。
- 既に `WordSyncCoordinator` 等が `profileId` を受け渡すので、**「今アクティブなプロファイルの profileId で同期」**に接続する。
- 端末ペアリングは既に `issuePairingCode(householdID:profileID:)` があるので流用（親スマホ側で子を指定して招待）。

**★レビュー指摘①：同期のプロファイル別化をPhase 5に丸ごと先送りするのは危険**。現状の同期状態はグローバル：`WordSyncRunner` の `profileID` 既定が `nil`、`sync.cursors` / `sync.wordSidecar` が世帯単位、`WordSidecarStore.project` の tombstone 判定が**世帯のみで profile 非考慮**。この状態で子Bに切り替えて同期すると、**子Aの単語が「削除された」ように見える**（データ破壊）。対策は次のいずれかを **Phase 2 に前倒し**：
- **(推奨) 最小の profile スコープ化を Phase 2 に入れる**：①同期にアクティブ `profileID` を渡す ②`sync.cursors` / `sync.wordSidecar` のキーを `(householdID, profileID)` でスコープ ③削除/projection を**世帯＋プロファイル**で絞る。
- **(暫定) プロファイルが2人以上になったら同期を hard-disable**（Phase 5 で本対応するまで）。1人だけなら従来通り安全。

いずれにせよ「**複数プロファイル × グローバル同期状態**」を同時に成立させない、が絶対条件。

---

## 7. 課金／エンタイトルメント（「別課金では？」への回答）

**過去の確定（§5/Q3）＝「家族込み1本」**。本設計もこれを踏襲することを推奨する。

- **サブスクは世帯単位**（`cachedEntitlement` はグローバル）。→ **子を増やしても課金は増えない**。子ども向け共有アプリ（1台を兄弟で使う）では、これが**摩擦最小＆コンバート最大**。原価は子1人あたり年¥6前後（§5）なので、家族込みでも利益率はほぼ不変。
- **「子ごとに別課金」は D3/§5 と矛盾**する。技術的には StoreKit で「基本1人＋追加児アドオン購読」も可能だが、
  - 親の**1つの Apple ID 配下**に複数購読 → 権利ミラー／レシート検証が複雑化、
  - Apple ファミリー共有は「各自が別端末/別Apple ID」前提でこのケースに合わない、
  - 購入摩擦が増え離脱要因。
  → **非推奨**。もし将来「大家族から多く取る」なら、別課金ではなく**人数ティア**（例：〜2人 / 〜5人）で表現する（購読1本のまま上位ティアに切替）方が StoreKit も UX も単純。
- ⚠ **本番 StoreKit は Apple Developer 登録待ちでブロック**（D-U-N-S 申請済）。→ **課金は Phase 6（Apple 解除後）**。それまで entitlement はグローバルのまま「家族込み」で扱えば、**プロファイル切り替え機能は Apple 非依存で先に完成できる**。

> 要確認（ユーザー判断）：「家族込み1本」で確定継続か、将来の「人数ティア」を設計に織り込むか。**別課金アドオンは推奨しない**が採否は要決定。

---

## 8. UI 設計（子=やる人 / 親=管理）

### 8.1 切り替え＝子に出してよい（「だれがやる？」ランチャー）
- 起動時 or ホームの一角に **大きなアバターカードのピッカー**（Netflix「誰が見てる？」式）。
- **自分を選ぶのは "やる人" の動作**＝子に出してOK。顔＋名前＋タップ音、字が読めなくても選べる。
- 既存の**なかま/アバター資産・角丸カード・バウンス**を再利用（新しい見た目言語を増やさない）。
- プロファイルが1人だけの間は**ピッカーを出さない**（1画面1動作を崩さない。段階的開示）。

### 8.2 管理＝親ゲートの奥
- **追加・削除・改名・並べ替え・アバター変更**＝管理動作 → **親ゲートの奥**（保護者メニューに「こども（プロファイル）」を新設）。
- 削除は破壊的＝確認ダイアログ＋「最後の1人は消せない」。
- レベル/級/点数は従来どおり**子に出さない**。

---

## 9. フェーズ分割（＝実装ロードマップ）

| Phase | 内容 | Apple依存 | テスト |
|---|---|---|---|
| **1** | `ChildProfile` / `ProfileRegistry`（純ロジック）＋ キー prefix 関数＋ `ChildScopedKeys.all` 定数 | 不要 | `SpellingSyncCore` swift test（TDD・100%狙い）|
| **2** | `ProfileScopedStore`（ラッパ・NSLock）＋ `AppModel` 配線（`loadChildScopedState`/原子的 `activateProfile`＋ reload ガード）＋ **同期バリア付き移行**＋ **同期の最小 profile スコープ化 or >1人時 hard-disable（★指摘①）** | 不要 | Core：移行の冪等・切替往復でデータ非混在・切替中に他児へ sync が飛ばない |
| **3** | 子向けランチャー（切り替えUI）＋ 1人時は非表示 | 不要 | 手動/結合（アプリにXCTest無）|
| **4** | 親ゲートのプロファイル管理（追加/削除/改名/並べ替え/アバター）| 不要 | 純ロジックは Registry テストで担保 |
| **5** | 同期のプロファイル別化を本対応（cursor/sidecar 完全分離・tombstone を世帯＋profile 化）| 不要（サーバは既存）| Core：カーソル/サイドカー分離 |
| **6** | 課金（家族込み継続 or 人数ティア）StoreKit | **要Apple** | — |

**Phase 1–5 は Apple 非依存で完成可能**。まず 1→2 を TDD で通し（**同期の安全化を Phase 2 に含める**のが肝）、3 で体験を確認、4 で管理、5 で同期を本対応、の順。
**工数見積（codex Architect）**：Phase 1 = Short（1–4h）／Phase 2 = **Medium（1–2日）**（`AppModel` init・多数の `didSet` 経路・移行・同期ガードに触れるため。同期スコープ化を含めると Medium 上限）。

### Phase 2 実装状況（2026-07-02・codex Code Reviewer = APPROVE）
**実装済み（behavior-preserving。単一子データは `profiles/<id>/` へ移るだけで挙動不変）**:
- Core `ProfileScopedStore`（`ProfileScopedRawStore` 越しにキー名前空間化・NSLock）＋ `ProfileStoreMigration.loadOrBootstrap`（初回=単一子→#1 を冪等・バリアコピー、**全コピー着地を検証してから台帳マーカー保存**＝書込失敗時は次回起動で再試行）。台帳存在自体が移行済みマーカー（別 bool フラグ無し）。
- アプリ配線: `AppModel.init` が生 store を包む／`ProfileScopedUserDataStore` アダプタ（JSON glue）／`AppPersistenceStore`・`InMemoryUserDataStore` が `ProfileScopedRawStore` 準拠。**既存の `persistenceStore.save/load` 81箇所はキー不変のまま自動スコープ化**（churn ゼロ）。
- 同期安全化: `isSyncSafeForActiveProfile`（`profiles.count <= 1`）で `syncNow`/`requestSync` をガード（>1人時 hard-disable＝設計指摘①の暫定）。Phase 2 は常に1人なので休眠。
- DEBUG キー分類明示: `aiJudgments`=子スコープ / `debugAIJudgeOnTest`=グローバル（子36/global11）。
- テスト: Core 15 本追加（名前空間化・A→B→A 非混在・グローバル共有・移行冪等/バリア順/着地検証）。**全 893 green**＋`xcodebuild` BUILD SUCCEEDED。

**意図的に Phase 2 では未対応（延期）**:
- **切替UI・`activateProfile`/`loadChildScopedState` 抽出 → Phase 3**（init 再ロードの並べ替えは呼び出す UI と一緒に入れる方が安全。今は切替経路が無い）。
- **進行中 sync の drain/cancel → Phase 3**（Code Reviewer 指摘③。Phase 2 は `profiles.count` が不変なので不要。プロファイル生成/切替を足す時に「>1 になる前に in-flight sync をキャンセル/待機」を入れる）。
- **`childName` → `ChildProfile.displayName` の単一 SSOT 化 → Phase 3/4**（改名/ランチャー UI が出る時。今は移行時に displayName を childName から一度シードし、childName は子スコープキーとして継続）。
- 同期のプロファイル別本対応（cursor/sidecar/tombstone）→ Phase 5。

### Phase 3 実装状況（2026-07-02・codex Code Reviewer = APPROVE）
**配線のみ（正式なランチャー/親管理 UI は Phase 3後半/4。切替の見え方＝2人目を作る導線が無いと不可視のため、まず土台配線を先行）**:
- **init のロード本体を `loadChildScopedState()` へ抽出**し init/切替で共用。子スコープ @Published に宣言時デフォルトを与えて二相初期化（init はグローバル系＝entitlement/debug を直接ロード→ `loadChildScopedState()` → 派生修復/シードの順）。
- **`isReloadingProfile` ガード**を子スコープ全 didSet に張り、再ロード中は保存・派生修復・同期要求を止める（移行の明示 `save` は didSet 外なので継続＝新スコープの初期値は永続化される）。**新プロファイルの既定語は明示 save して `word.id` を安定化**（レビュー指摘・Critical。UUID が毎回変わるとステップ署名/クリア/復習が壊れる）。
- **`activateProfile(_:)`**（原子的・作り直さない）: 保留 sync キャンセル → ガード ON → 台帳 `activating`＋`persistRegistry`＋`scoped.setActiveProfileID` → `loadChildScopedState` → ガード OFF 後に修復/シード/`requestSync`。フォールバック/同一/未知IDは no-op。`focusedPracticeWordIDs` は切替でクリア。
- **`childName` → `profileRegistry.activeProfile.displayName` の SSOT 化**（computed。`$` バインディング未使用を確認済＝View 非破壊。書込は `renaming`＋`persistRegistry`）。旧 `childName` キーは廃止。
- **同期の交差汚染を完全クローズ**（設計指摘①の Phase 3 分・6ラウンドのレビューで詰め）: `isSyncSafeForActiveProfile`（`profiles.count<=1`）を **唯一の安全不変条件**として `syncWords` 入口・`applyMergedWords`・`WordSyncCoordinator.runOneCycle` の3境界（開始/pull後/push後）で確認。さらに **`syncCycleDepth` カウンタ**で「サイクル進行中は人数を増やせない」を保証（in-flight push が2人以上でサーバ到達する窓を消す。Bool だと重複 `syncWords` の defer で早期クリアされるためカウンタ）。プロファイル別 cursor/sidecar/tombstone の本対応は Phase 5。
- DEBUG 限定の切替導線（親デバッグ節に人数表示＋切替ボタン＋`debugAddTestProfile`）。手動確認用。
- 検証: `xcodebuild` BUILD SUCCEEDED＋Core 893 green（Core ロジック不変・app 本体は XCTest 無のためビルド＋レビュー＋手動）。

**Phase 3 でも未対応（延期）**: 正式な子ランチャー（顔ピッカー・Netflix式）＋親ゲート管理（追加/改名/削除/並べ替え/アバター）→ Phase 3後半/4。同期のプロファイル別本対応 → Phase 5。課金 → Phase 6（Apple）。

---

## 10. テスト観点（Core・TDD）
- `ProfileRegistry`：add/remove/rename/activate/reorder の不変条件（最低1人・active∈profiles・決定論順序）。
- キー prefix：グローバル whitelist は素通し、それ以外は `profiles/<id>/` が付く。
- 移行：既存キー→#1 スコープへコピーが**冪等**（2回流しても二重化しない）、フラグ未達時は再試行。
- 切替往復：A→B→A で A のデータが保たれ B と混ざらない（`ProfileScopedStore` + フェイク `UserDataStore`）。

## 11. 未決 / 要確認
1. **課金モデル**：家族込み1本で確定継続か、人数ティアを設計に織り込むか（§7）。**別課金アドオンは非推奨**。
2. 切り替えの**露出場所**：起動時ピッカー固定か、ホームからの明示切替か（§8.1）。
3. **同時ログイン親スマホ**との突き合わせ（Phase 5 で詰める）。
4. `cast`（本人実名）は**プロファイル別・ローカルのみ**を維持で良いか（未成年PII方針）。
</content>
</invoke>
