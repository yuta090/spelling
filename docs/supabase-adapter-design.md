# 同期アダプタ設計（iOS ⇄ Supabase）

Status: 設計（実装の指針）
Date: 2026-06-26
土台: `Sources/SpellingSyncCore/`（LWW/tombstone/SRS/Migration・TDD済）＋ Supabaseスキーマ/RLS（0001–0005適用済）
レビュー反映: Architect指摘 #3(LWWガード=0005適用済)/#4(server_changed_atカーソル)/#8(決定論UUID)/#9(Storage)

---

## 1. レイヤー構成
```
SwiftUI Views
  └─ AppModel（既存・@MainActor）
       └─ Repositories（単語/答案/採点/SRS… ドメイン操作）
            ├─ LocalCache（オフラインの真実の源。既存の永続化を流用）
            └─ SyncEngine（差分プル/プッシュ。SpellingSyncCore を利用）
                 └─ SupabaseClient（supabase-swift SDK・anonキー）
```
- **オフラインファースト**：UIは LocalCache を見る。SyncEngine が裏で Supabase と突き合わせる。
- `UserDataStore`（既存のキー→Codable境界）は LocalCache 側に留め、サーバー同期は per-entity の SyncEngine が担う（blobをそのまま同期しない）。

## 2. 認証
- **親**：Supabase Auth（メールのマジックリンク）。初回 `rpc(create_household)`（匿名拒否）でオーナー世帯作成。
- **子**：**匿名サインイン** → 親が発行したコードで**ペアリング**（Edge Function が `devices` に登録）。以後 RLS で自世帯/自プロファイルのみ。

## 3. 同期プロトコル
### プル（取得）
- カーソル＝**`server_changed_at`**（サーバー採番。`updated_at` はクライアント値なので使わない＝#4）。
- 各テーブル：`select * where server_changed_at > :cursor order by server_changed_at, id limit N`（ページング）。
- 取得分を `LastWriteWins.reconcile(local, remote)` でマージ → `live()` でtombstone除外して表示。
- カーソルを取得ページの最大 `server_changed_at` に前進（テーブル毎に保持）。
### プッシュ（送信）
- ローカルの dirty レコードを upsert（PostgREST `upsert` / `on conflict`）。
- **LWWはサーバーの 0005 ガードが保証**（古い `updated_at` は無視・同時刻の復活却下）。クライアントも送信前に `LastWriteWins` で自衛。
- **削除は論理削除のみ**：`deleted_at` を立て `updated_at` を進めて upsert（クライアントのハード削除はRLSで不可＝#2）。

## 4. 識別子（オフライン安全）#8
- 通常レコード：オフライン採番のランダム `UUID`。
- **論理的に一意な行は決定論UUID**で重複生成を防ぐ：
  - `srs_cards` = uuidv5(namespace, profile_id + word_id)
  - `reward_wallets`/`child_settings` = uuidv5(profile_id + 種別)
  - `step_word_memberships` = uuidv5(step_id + word_id)
  - `reviews` = uuidv5(attempt_id)
  → 別端末が同じ論理行を作っても同一IDに収束し、unique制約と整合。

## 5. Edge Functions（service_role・クライアント禁止操作）
| 機能 | 内容 |
|---|---|
| pairing-issue | 親が6桁コード発行（`pairing_codes` に hash 保存・15分・単回） |
| pairing-consume | 子端末がコード消費→`devices` 登録（原子的・期限/消費/レート制限） |
| entitlements-sync | App Store Server Notifications v2 を検証し `entitlements` 更新 |
| review-notify | `review_requests` 追加を受け、親へ **APNs**（確実通知。CloudKitと違いbest-effortでない） |
| storage-sign | 手書きの**署名URL**発行（#9：privateバケット・`households/{hh}/profiles/{pid}/...`・短TTL） |

## 6. ストレージ（手書き）#9
- private バケットのみ。クライアントは直接listしない。
- アップロード/ダウンロードとも Edge 署名URL。パスは `households/{household_id}/profiles/{profile_id}/attempts/{attempt_id}.pkdrawing`。
- DBの `drawing_path` はキー参照（本体はバケット）。

## 7. 残作業（別タスク）
- [ ] **migration 0006**: 複合FK/トリガで `household_id`/`profile_id` の参照整合（#6）。
- [ ] supabase-swift SDK を Xcode に追加（SPM・**要Xcode操作**）。
- [ ] SyncEngine 実装（プル/プッシュ/カーソル保持）＋ 既存 `Migration` で旧ローカルJSON投入。
- [ ] Edge Functions 実装＆デプロイ（**要 supabase login / deploy**）。
- [ ] StoreKit2 課金 → entitlements 反映。
- [ ] 接続情報のアプリ注入（公開可の URL/anonKey を xcconfig 経由）。

## 7.5 決定: ローカル⇄サーバーの橋渡しは「サイドカー同期ストア」方式（2026-06-26）
**背景（モデル差）**: ローカルの `SpellingWord` は単一ユーザー/オフライン前提で、
`household_id`/`profile_id`/`updated_at`/`deleted_at` を持たず、`stepID` は **String**（ステップは実行時に
`makeWordSteps` で導出する派生物で、サーバーの **UUID `step_id`** と一致しない）。一方サーバーの
`words`/`steps` は多人数前提で上記列が必須。よって「pull→merge→push を AppModel に結線」は単純な配線ではなく、
**モデル差を埋める橋渡し**が要る。

**採用方針（サイドカー同期ストア）**: `SpellingWord` 等のUIモデルは触らず、
`id → SyncMetadata（updatedAt/deletedAt/household/profile）` を**別ストア**で保持し、
DTO ⇄ `SyncableRecord` に射影する。巨大なView層（HomeView/ParentDashboard 600KB+）を壊さず、
まず `words` だけ疎通させる。`stepID(String) → step_id(UUID)` は当面**別管理のマップ**で対応し、
論理一意行（srs_cards等）は `DeterministicID.uuidV5` で採番してから push 対象に加える。
（不採用: `SpellingWord` に直接 SyncMetadata を生やす案＝View層全体に波及し高リスク。）

**現在地**: 親メールOTPサインイン/世帯作成の**デバッグ導線**（`SyncSession` + `SyncDebugView`、
DEBUG限定ランチャ）と **active household_id の端末永続化**を実装済み。これでOTP疎通テストが叩ける。
次段でサイドカーストア本体（pull→reconcile→push＋カーソル/high-water永続化）を実装する。

## 8. 純粋ロジックでTDDできる単位（SDK不要）
- カーソル前進＋差分マージ（`reconcile`＋max(server_changed_at)）
- 決定論UUID生成（uuidv5 ヘルパ）
- dirty 抽出（updated_at > 最終同期、または dirty フラグ）
→ これらは `SpellingSyncCore` に足してテストできる。SDK/Edge はその後。
