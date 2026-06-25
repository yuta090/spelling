# マルチユーザー＆プロダクト戦略 — 意思決定ログ

Status: 生きたメモ（随時更新）
Date: 2026-06-25
目的: 「マルチユーザー対応」と、その過程で出たプロダクト戦略の**決定・保留・未決・根拠**を一箇所に保存する。
関連ドキュメント:
- 技術設計（CloudKit）: `multi-user-cloudkit-sync-design.md`
- 旧案（supersededed）: `parent-web-cloud-design.md`
- CKShare 検証手順: `cloudkit-ckshare-spike-runbook.md` / `spike/CloudKitSpike.swift`
- ユーザー作業（iCloud有効化）: `あなたの作業-iCloud有効化.md`
- 英検級マッピング＆親メニュー: `eiken-level-mapping.md`
- LPコピー: `lp-copy-draft.md`
- 定着エンジン(SRS)設計: `srs-retention-design.md`
- 同期コア実装（TDD済み）: `Sources/SpellingSyncCore/`（PR #13）

---

## 0. ひとことサマリー
- **やりたいこと**：複数端末でのデータ共有（旅行用iPad＋自宅iPad＋親iPhone）、親が子の答案を**遠隔で採点**（通知）、親がスマホで**単語登録**。
- **技術方針（2026-06-26 更新）**：**Supabase 主役**（Postgres + Auth + RLS）＋ **Cloudflare R2**（手書き保存・転送無料）＋ **StoreKit**（App内課金）。ネイティブ親iPhoneアプリ。
  - 当初 CloudKit + CKShare に確定したが、**無料Apple開発者では使えず**、かつ**有料配布を決定**したことで再評価 → **Supabaseに転換**（§1 D11/D12、経緯は §9）。
- **戦略の収束点**：ターゲット＝**英検先取りの教育熱心な家庭**、売り＝**「テストで覚える（検索練習）×手書き×親に可視化」**。

---

## 1. 決定事項（CONFIRMED）

| # | 決定 | 根拠 |
|---|---|---|
| D1 | ~~CloudKit路線~~ → **Supabase 主役**（Postgres+Auth+RLS）＋ R2＋StoreKit に**転換**（2026-06-26） | 有料配布決定＋目玉機能(遠隔採点+確実通知)がCloudKitの弱点＋Android視野＋1系統運用。詳細 D12 |
| D2 | 親は **ネイティブiPhoneアプリ**（同一アプリの親モード） | 既存に親ゲート/ダッシュボードあり（将来Web/Androidも視野） |
| D3 | アカウント＝**親1＋子プロファイル複数＋端末複数、子はログインなし** | 子PII最小化（Supabaseでは端末は匿名/デバイス認証＋RLSで世帯隔離） |
| D4 | 親子は**別アカウント**前提 → **Supabase Auth＋RLS**で世帯隔離・端末ペアリング | 実際の家庭構成（旧: 別Apple ID→CKShare） |
| D5 | 最低OS **iOS 16** | 既存 ios16-downport 方針（CloudKit固有の制約は失効） |
| D6 | データは **append-only ＋ 親採点は別レコード**（`Attempt`不変／`Review`分離）。競合は後勝ち | Architect訂正。Supabaseでも同設計（衝突面を小さく） |
| D7 | **旧 Supabase+親Web 設計書を“現行版の土台”に格上げ**（supersede解除）。スキーマ/RLS/ペアリングを流用し英検・SRS・採点に合わせ更新 | D1転換に伴う |
| D8 | **ターゲット主軸＝英検先取りの教育熱心な家庭**（私立小/受験/先取り公立/中1へ拡張） | 公立小に英単語小テスト文化が無い等の市場リサーチ |
| D9 | **ポジショニング＝「テストで覚える(検索練習)×手書き×親に可視化」＋英検ゴール** | 認知科学の裏付け＋学校種に依存しない共通ゴール |
| D10 | レベル（Dolch/NGSL）は**英検級ラベル**として親のセット生成に使う。**子には級・点数を見せない** | CLAUDE.md 非ラベリング方針と一致 |
| D11 | **有料化・本気で配布する**（Apple Developer Program 加入） | 収益化方針。配布にはどのみち必要 |
| D12 | **ハイブリッドではなく Supabase 主役**（CloudKitは不採用） | ①課金で結局サーバー必要 ②目玉=別アカウント遠隔採点+確実プッシュ＝CloudKitの最弱点 ③Android/Web視野 ④個人開発は1系統が運用安全。手書きはR2(転送無料)で原価ほぼ0 |

---

## 2. 実装済み（DONE・PR #13, branch `feat/cloudkit-sync-20260625`）
- `UserDataStore` 境界プロトコル（永続化を抽象化。挙動不変・完全後方互換）。
- `SpellingSyncCore`（SwiftPM・**TDD・カバレッジ100%**。同期コア28テスト＋SRS 13テスト＝計41テスト）
  - `SyncMetadata`（UUID/household/profile/updatedAt/**tombstone**）
  - `LastWriteWins`（record単位・順序非依存・削除優先・id決定論タイブレーク）
  - `ReviewProgress.pendingCount`（採点待ち＝通知トリガ算出）
  - `Migration`（旧JSON→正準レコード、後方互換。**id二重採番バグ発見・修正**）
  - `SRSScheduler`（Leitner方式の定着エンジン。13テスト。commit `12a2430`）
- 設計書・CKShare検証ランブック・英検マッピング・LPコピー（docs/）。
- ※**アプリ本体はまだローカル保存のまま**（同期は未接続・iCloud未使用・費用未発生）。

---

## 3. 不採用（ARCHIVED・旧CloudKit路線）

| # | 事項 | 結末 |
|---|---|---|
| H1 | iCloud同期（Core Data+CloudKitストア） | **不採用**（D12）。CloudKit検証ランブック/雛形は参照用に残置 |
| H2 | CKShare実機スパイク | **不要**（CloudKit不採用） |

---

## 4. 未決の問い（OPEN QUESTIONS）

- **Q1（解決済 2026-06-26）**: → **Supabase主役＋Apple Developer Program加入で本気配布**に決定（D1/D11/D12）。`UserDataStore`境界のおかげで既存コア（SpellingSyncCore）は再利用、変わるのはストアのアダプタ1枚。
- **Q2**: ターゲットの主軸は「英検先取り×教育熱心家庭」で確定。**中1直撃まで広げる際のUIトーン**（幼さの調整）をどうするか。
- **Q3**: 料金 ¥580/月・¥4,800/年（家族込み）＋7日無料、で出すか。出した後に±¥100でテスト。
- **Q4**: 英検級マッピングを「頻度プロキシ」のまま運用するか、将来「英検公式リスト準拠」に精緻化するか。

---

## 5. コスト＆価格の結論（参考・別議論の保存）
- **保存コストの主役は手書き(PKDrawing, 数KB〜数十KB)**。テキストは誤差。
- **1人あたり保存コスト ≈ 年¥6前後**（ヘビーでも¥70程度）。
- **何千〜1万人規模**でも安く組めば**月¥3,000〜5,000**（最安: CloudKit≈¥0／クロスプラットフォーム最安: Supabase＋Cloudflare R2[転送無料]）。
- **価格相場**（スペリング特化の競合）：$3.99〜4.99/月・年¥4,500前後・家族込み。
- **推奨価格**：¥580/月 or ¥4,800/年（家族込み）＋7日無料。**同期/遠隔採点/レポートを有料の壁**に置く＝原価ほぼ0で高利益。
- 採算：有料が**月十数人**で固定費回収。限界利益率≈99%。価格は原価でなく価値・相場で決めてよい。

---

## 6. 強み／弱み（保存）
**差別化（強い順）**：①手書き×OCR自動採点×なぞり書き ②学校小テスト/英検への密着 ③親採点ワークフロー(doer/manager分離) ④日本の子ども特化ローカライズ。

**不足（影響順）**：①継続の仕組み（streak/デイリー目標なし）②間隔反復(SRS)なし③親レポート/通知が薄い④同期/遠隔採点が未実装（現状ローカルのみ＝機種変でデータ消失リスク）⑤発音認識なし⑥オンボーディングの磨き込み。
→ **最優先で埋める3つ**：継続ループ／親レポート＋通知／SRS。いずれも原価ほぼ0で、そのまま課金根拠になる。

---

## 7. ロードマップ上の次手（順序）
1. ✅ #1 英検級マッピング＋親メニュー再定義（`eiken-level-mapping.md`）
2. ✅ #2 LPコピー骨子（`lp-copy-draft.md`）
3. ✅ #3 **定着エンジン(SRS)設計＋実装**（`srs-retention-design.md` / `SRSScheduler` Leitner方式・TDD13テスト, commit `12a2430`）。残：今日の出題生成のアプリ本体組み込み・英検ゴール逆算UI。
4. **【現在地】Supabase 主役で同期を構築**（ブランチ `feat/supabase-sync-20260626`）:
   1. 旧 `parent-web-cloud-design.md` を**現行スキーマ設計に格上げ・更新**（英検セット/SRS box/検索練習テスト/親メニュー/R2/StoreKit を反映）。
   2. Supabase スキーマ＋**RLS**（世帯隔離・端末ペアリング）。
   3. `UserDataStore` 境界の **Supabase アダプタ**実装（`SpellingSyncCore` のLWW/tombstone/SRSを活用）。
   4. 確実通知（child finish→APNs/FCM）・StoreKit課金・R2手書き保存。
5. 継続ループ（streak/デイリー目標）＋親レポート＋通知。

---

## 8. 重要な前提・ガードレール
- 子ども側：1画面1動作・大きいタップ・**級/点数を見せない**・ふりがな・ごほうび。
- 親側：管理コンソール（情報密度OK）。新メニュー＝**ゴール/単語/みてあげる/きろく/設定**。
- データ：`wordbank.sqlite` は読み取り専用・同期対象外。子の機微データ（手書き）は最小権限で扱う。**Supabaseでは子のPIIを最小化＋RLSで世帯隔離、手書きはR2の世帯/子スコープ・署名URL**。
- 作業はワークツリー `feat/supabase-sync-20260626`。`main` 直接編集しない（CLAUDE.md）。

---

## 9. 経緯：CloudKit → Supabase 転換（2026-06-26）
1. 当初は運用ゼロ・子データ非保持を最優先し **CloudKit + CKShare** に確定（D1旧）。
2. 実機で **無料Apple開発者アカウントでは iCloud/CloudKit/Push が使えない**ことが判明（Capability一覧に出ない）。
3. 検討の結果ユーザーが **有料化・本気で配布**を決定（D11）。CloudKitが使える状態に。
4. しかし「**別アカウント間の遠隔採点＋確実な通知**」という**課金の目玉が CloudKit の最弱点**（CKShareの煩雑さ・プッシュ best-effort）。加えて課金で**結局バックエンドが必要**（レシート検証/Server Notifications）、**Android/Web も視野**。
5. → 二重同期の「悪いハイブリッド」を避け、**Supabase 主役（+R2+StoreKit）の1系統**に決定（D12）。CloudKitは「子データを自社に置かない」を売りにする場合のみの代替として保留せず不採用。
6. 既存の `SpellingSyncCore`（LWW/tombstone/移行/採点待ち/SRS）と `UserDataStore` 境界は**バックエンド非依存**で再利用可。旧Supabase設計書（スキーマ/RLS/ペアリング）が土台になる。
