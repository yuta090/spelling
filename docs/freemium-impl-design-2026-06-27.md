# フリーミアム実装設計（確定版 2026-06-27）

[monetization-spec-2026-06-27.md](./monetization-spec-2026-06-27.md) の課金モデルを実装に落とす設計。
codex(Architect) の批判レビューを反映済み。関連: [HANDOFF-2026-06-26.md](./HANDOFF-2026-06-26.md)（StoreKit2/entitlements TODO）, [supabase-sync-design.md](./supabase-sync-design.md)。

## 0. 設計原則（プロジェクト規約に準拠）

- **純粋ロジックは `SpellingSyncCore`（SwiftPM）に置き、`swift test` でTDD**（カバレッジ80%+）。`CoinRewards.swift` が手本（純粋 `enum` ＋ `Calendar` 注入）。
- アプリ本体（`AppModel`・StoreKit・UI）は**薄く保つ**。I/O とロジックを分離。
- **段階的に実装**（後述フェーズ1/2）。未実装のサーバ機能のために今から作り込まない（pragmatic minimalism）。
- 子に価格・「有料」を見せない。**課金UIは必ず親ゲート（`ParentGateView`）の奥**。

## 1. 全体像：2種類のゲート ×（純粋ロジック / I/O）

| ゲート | 何を守る | 判定の置き場所 | フェーズ |
|---|---|---|---|
| **コンテンツゲート** | レベル生成（Grade1+/NGSL）のロック | **ローカル**（クライアント完結） | フェーズ1 |
| **機能ゲート** | 採点・レポート・同期（サーバ上で動く） | **サーバ権威**（Supabase で世帯権利を検証） | フェーズ2 |
| **学習リズム（10語/日）** | 課金とは無関係の教育的スロットリング | ローカル純粋ロジック | フェーズ1 |

> 重要：コンテンツゲートはクライアント判定で十分（単語は専有物でなく、改造リスクは無視可）。サーバ機能はクライアントの bool を信用できないので、フェーズ2でサーバ側検証必須。

## 2. フェーズ1（v1）— ローカルで完結する範囲

### 2.1 1日10語の新規導入（学習リズム / 課金と無関係）

**設計判断（codex D1 APPROVE＋修正）：**
- **「登録の制限」ではなく「練習への“新規導入”の制限」**。親は学校の50語リストを一括登録できる。登録超過はブロックしない。**未練習の語が1日に練習へ入る数を最大10**に絞り、残りはキューに待たせる。
- カウントは attempt 履歴からの導出に頼らない（`SpellingAttempt` は**テキストキー**で、練習とテストが別系統＝弱い）。代わりに **単語が初めて練習セッションに入った時刻 `firstIntroducedAt: Date?` を `SpellingWord` に永続スタンプ**し、`isDateInToday` で数える（冪等・クラッシュ安全・二重計上なし）。
- free / paid に**同一適用**。

**新規 純粋モジュール `SpellingSyncCore/NewWordBudget.swift`（TDD）：**
```swift
public enum NewWordBudget {
    public static let dailyLimit = 10
    /// 今日まだ導入できる新規語の残り枠
    public static func remainingSlots(introducedToday: Int, dailyLimit: Int = dailyLimit) -> Int {
        max(0, dailyLimit - introducedToday)
    }
    /// 今日の練習に新規導入する語を選ぶ（未練習の候補から残り枠ぶん）
    public static func selectNewWords<W>(candidates: [W], introducedToday: Int,
                                         dailyLimit: Int = dailyLimit) -> ArraySlice<W> {
        candidates.prefix(remainingSlots(introducedToday: introducedToday, dailyLimit: dailyLimit))
    }
}
```
- `introducedToday` は AppModel が算出：`words.filter { $0.firstIntroducedAt.map { cal.isDateInToday($0) } ?? false }.count`。
- `firstIntroducedAt` は、未練習語が**実際に当日の練習セッションに組み込まれた瞬間**に一度だけスタンプ（セッションビルダ内）。
- タイムゾーン/日付境界は `Calendar` 注入でテスト（`CoinRewards` と同方針）。
- セッション完了は**コイン報酬で締める**（実装済み資産流用：「きょうのれんしゅう おわり！」）。

**テスト観点（最低）：** 残り枠＝0/部分/満杯、未練習0件、当日跨ぎ、Calendar注入のTZ差、再導入されない（既スタンプ語は数え直さない）。

### 2.2 コンテンツゲート（レベル生成のロック）

**設計判断（codex D2 REVISE反映）：**
- 生フィールド `dolch: String?, band: Int?` 判定は脆い → **型付き enum で判定**。
```swift
// SpellingSyncCore/ContentGate.swift
public enum ContentLevel: Equatable, Sendable {
    case dolch(DolchGrade)            // .preK, .k, .g1, .g2, .g3, .noun
    case ngsl(band: Int)             // 1...5
}
public enum DolchGrade: String, Sendable { case preK = "pre-K", k = "K", g1 = "1", g2 = "2", g3 = "3", noun }
public enum ContentGate {
    /// 無料で解放されるレベルか（pre-K と K のみ無料）
    public static func isFree(_ level: ContentLevel) -> Bool {
        switch level {
        case .dolch(.preK), .dolch(.k): return true
        default: return false   // g1/g2/g3/noun, 全NGSLバンドは有料
        }
    }
    public static func isUnlocked(_ level: ContentLevel, isSubscribed: Bool) -> Bool {
        isSubscribed || isFree(level)
    }
}
```
- **`noun` の扱い（確定）：有料約束から外す。** 現UIのレベル選択 `["pre-K","K","1","2","3"]` に noun は無く、ストア掲載の有料約束も「**Grade 1/2/3 ＋ NGSL 全バンド**」に揃える。enum 上は `.noun` をロック側に持つが、UIには露出しない（将来露出するならロックのまま提供できる余地だけ残す）。
- **UI（`WordLevelSetSheet`）：** ロックされたレベルは**隠さず lock バッジ付きで表示**。タップで親ゲート奥のペイウォールへ誘導（＝コンバージョン動線）。`createSet()` の `leveledWords(...)` 呼び出し前に `ContentGate.isUnlocked` で guard。
- **手打ち登録は素通り**（`leveledWords` を通らないので無料・無制限）。外部のNGSLリストを貼る程度の“利便性バイパス”は実害なしとして許容（codex同意）。

### 2.3 権利（entitlement）＝ StoreKit2 ローカル

**設計判断（codex D3：フェーズ分割で対応）：**
- フェーズ1のコンテンツゲートは**ローカルStoreKit2のみ**で判定。サーバ不要。
- 薄い `StoreManager`（アプリ層I/O）が StoreKit を所有：
  - `Transaction.currentEntitlements` から `isSubscribed` を導出。
  - `UserDataStore` にキャッシュ（オフライン起動用）。**キャッシュは取引の失効時刻を超えて保持しない**（「永久 subscribed」禁止／codex指摘）。
  - 起動時に再検証＋ `Transaction.updates` を購読。
  - **Restore（購入の復元）ボタン必須**。
- `AppModel` は `@Published var isSubscribed` を公開（`StoreManager` から反映）。UI はこれを読むだけ。

### 2.4 トライアル表示（codex D5 REVISE反映）

- カスタムのトライアル追跡DBは**作らない**（StoreKit が eligibility を管理）。
- ただし「7日間無料」を**静的表示しない**。`Product.SubscriptionInfo`/eligibility から**対象者にのみ**トライアル文言を出し分け（再課金者には出さない）。**トライアル後の満額更新価格を明記**。
- 実体は App Store Connect の Introductory Offer 設定（コードはレンダリングのみ）。

### 2.5 解約後の挙動（codex D4 APPROVE）

- **巻き戻しなし。** 既に子のリストにある語は、解約後も練習可能（学習中のコンテンツを剥がさない）。
- コンテンツゲートは**生成時のみ**判定（練習時には判定しない）。
- 「1ヶ月課金→全語生成→解約」は理論上可能だが、1日10語導入で約2900語＝**約290日分**に希釈され実害軽微。対策として**「全部生成」一括ボタンは作らない**（現行は1セット5〜30語のまま）。

## 3. フェーズ2 — サーバ機能の権利（採点・レポート・同期）

> 採点・レポート・同期は**まだ未実装**（HANDOFF TODO）。これらを**実装するときに、本節を同時に作る**。今は設計意図の記録のみ。

- **サーバ権利ミラー：** 課金端末で StoreKit2 検証 → アプリが Supabase に**世帯(household)スコープで権利を書き込む**（`household_entitlements`：`household_id`, `status`, `expires_at`, `original_transaction_id`）。
  - `original_transaction_id` で**一意化**（多重・なりすまし防止）。定期再検証。
  - 各サーバ機能エンドポイントは**サーバ側で世帯権利を検証**してから実行（クライアントの bool は信用しない）。
- **世帯メンバー（親）= 最大2人（管理者ロール）** を製品意図として定義。
  - 別々のApple IDで同一世帯を共有する2親のケースは、**このミラーで解決**（Apple ファミリー共有では届かない典型）。
  - **「親2人まで」の強制はフェーズ2で実装**（v1では数値を焼き込まない）。
- **子データのプライバシー同意**（Kidsカテゴリ）：Supabase同期前に保護者向け同意を取得。第三者解析/広告は不可（要コンプライアンス）。

## 4. マルチデバイス／ファミリー共有（v1での割り切り）

- **v1のコンテンツ解放は Apple ファミリー共有に乗せる**：サブスクのファミリー共有を App Store Connect で有効化すれば、同一Apple家族（最大6人）の端末はコード追加なしで解放。
- 「同じApple家族の2親」は v1 で自動カバー。「別Apple IDの2親」は**フェーズ2のミラー**で対応。
- ファミリー共有を**謳う場合は ASC で有効化**し、文言を正確に（自動の世帯共有ではない）。

## 5. App Store 審査チェックリスト（Kids ＋ サブスク）

- [ ] 購入・外部リンク等は**保護者ゲートの奥**（配置OK）。
  - 現 `ParentGateView` は2桁＋2桁の加算。Kids向けには**やや弱い可能性**（任意の強化候補：3桁化や手順タスク化）。優先度低だが記録。
- [ ] サブスク画面の**必須記載**：プラン名/期間、含まれる機能、**更新後の満額**、復元/サインイン導線、利用規約、プライバシーポリシー、（トライアル時）トライアル長＋トライアル後価格。
- [ ] **Restore（復元）ボタン**。
- [ ] ストア掲載で**どのレベル/機能がIAPか明示**（スクショ・説明文）。
- [ ] オフラインキャッシュした権利は**失効時刻で失効**。
- [ ] ガチャ的・射幸性のある課金は入れない。

## 6. 実装順（フェーズ1）と規模

1. `SpellingSyncCore`：`NewWordBudget.swift` ＋ `ContentGate.swift`（型付きenum）を**テストファースト**で追加。
2. `SpellingWord` に `firstIntroducedAt: Date?` を追加（Codable後方互換：optional）。永続化（`UserDataStore`）。
3. 練習セッションビルダで `NewWordBudget` を使い、`firstIntroducedAt` をスタンプ。
4. `StoreManager`（StoreKit2）＋ `AppModel.isSubscribed` ＋ キャッシュ/Restore。
5. `WordLevelSetSheet`：ロックレベルの lock 表示 ＋ `ContentGate` guard ＋ ペイウォール導線。
6. ペイウォールUI（親ゲート奥）：eligibilityでトライアル出し分け、満額明記、必須記載一式。

**規模：Medium（1〜2日）**。フェーズ2（サーバ権利ミラー＋世帯2親強制）は別途 **Medium〜Large**、対象サーバ機能の実装とセットで。

## 7. 確定事項サマリ

| 項目 | 確定 |
|---|---|
| 権利アーキ | **段階的（A）**：v1ローカルStoreKit、サーバ権利はフェーズ2 |
| 10語/日 | 登録ではなく**練習への新規導入**を制限。`firstIntroducedAt` 永続スタンプで導出。free/paid共通 |
| コンテンツゲート | 型付き `ContentLevel` enum、無料＝pre-K/K のみ。ロックは**表示**してペイウォール誘導 |
| noun | **有料約束から外す**（UI非露出、enumにロック余地のみ） |
| 権利の出所 | StoreKit2 ローカル（キャッシュは失効時刻まで／Restore必須） |
| トライアル | カスタム追跡なし。eligibilityで出し分け＋満額明記 |
| 解約後 | 巻き戻しなし。生成時のみゲート判定。一括生成ボタンは作らない |
| 世帯の親 | **最大2人（管理者）**。v1はファミリー共有、強制はフェーズ2のミラー |

---

*確定日: 2026-06-27 / レビュー: codex(Architect) 批判レビュー反映済み（D1/D4 APPROVE, D2/D3/D5 REVISE対応）*
