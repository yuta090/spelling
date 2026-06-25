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
- **技術方針**：CloudKit（`NSPersistentCloudKitContainer` + CKShare）＋ネイティブ親iPhoneアプリ。に**確定**したが…
- **現在の最大のブロッカー**：開発アカウントが**無料**のため CloudKit/Push が使えない。→ **同期は保留**。Apple有料加入 or Supabase 切替を検討中。
- **戦略の収束点**：ターゲット＝**英検先取りの教育熱心な家庭**、売り＝**「テストで覚える（検索練習）×手書き×親に可視化」**。

---

## 1. 決定事項（CONFIRMED）

| # | 決定 | 根拠 |
|---|---|---|
| D1 | マルチユーザーは **CloudKit路線**（NSPersistentCloudKitContainer + CKShare） | 運用ゼロ・子データ非保持を最優先。Architectレビュー sound-with-changes |
| D2 | 親は **ネイティブiPhoneアプリ**（同一アプリの親モード） | CloudKitと相性。既存に親ゲート/ダッシュボードあり |
| D3 | アカウント＝**親1＋子プロファイル複数＋端末複数、子はログインなし** | 子PII最小化 |
| D4 | 親子は**別Apple ID**前提 → CKShare（共有DB）使用 | 実際の家庭構成 |
| D5 | 最低OS **iOS 16**（CKSyncEngine不可→NSPersistentCloudKitContainer） | 既存 ios16-downport 方針 |
| D6 | 競合は **record単位 last-write-wins**。`Attempt`(不変)と`Review`(親採点)を分離 | Architect訂正（field単位マージではない） |
| D7 | 旧 Supabase+親Web 案は **supersede**（参照用に残置） | 今回の優先軸が運用ゼロ・データ非保持に変化 |
| D8 | **ターゲット主軸＝英検先取りの教育熱心な家庭**（私立小/受験/先取り公立/中1へ拡張） | 公立小に英単語小テスト文化が無い等の市場リサーチ |
| D9 | **ポジショニング＝「テストで覚える(検索練習)×手書き×親に可視化」＋英検ゴール** | 認知科学の裏付け＋学校種に依存しない共通ゴール |
| D10 | レベル（Dolch/NGSL）は**英検級ラベル**として親のセット生成に使う。**子には級・点数を見せない** | CLAUDE.md 非ラベリング方針と一致 |

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

## 3. 保留（ON HOLD）

| # | 事項 | 理由 | 再開条件 |
|---|---|---|---|
| H1 | iCloud同期の実装（Core Data+CloudKitストア） | **無料Apple開発者アカウントでは CloudKit/Push 不可**（Capabilityに出ない） | 方針決定（下記 Q1）後 |
| H2 | CKShare実機スパイク | 実2 Apple ID＋実機＋有料アカウントが要る | 同上 |

---

## 4. 未決の問い（OPEN QUESTIONS）

- **Q1（最重要）**: **Apple Developer Program（年¥15,000）に加入してCloudKitで進める**か、**Supabaseに切替**えるか、**当面ローカルのまま**か。
  - 判断軸：「このアプリを本気で使う/配布する気があるか」。あるなら有料はどのみち必要→CloudKitが最も運用が楽。
  - `UserDataStore`境界のおかげで、後からどちらにも低コストで進める。
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
4. （Q1決定後）同期の実装 or Supabase切替。
5. 継続ループ（streak/デイリー目標）＋親レポート＋通知。

---

## 8. 重要な前提・ガードレール
- 子ども側：1画面1動作・大きいタップ・**級/点数を見せない**・ふりがな・ごほうび。
- 親側：管理コンソール（情報密度OK）。新メニュー＝**ゴール/単語/みてあげる/きろく/設定**。
- データ：`wordbank.sqlite` は読み取り専用・同期対象外。子の機微データ（手書き）は最小権限で扱う。
- 作業はワークツリー `feat/cloudkit-sync-20260625`。`main` 直接編集しない（CLAUDE.md）。
