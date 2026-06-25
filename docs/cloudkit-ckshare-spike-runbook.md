# CKShare 検証スパイク ランブック

Status: 実機検証手順（あなたの操作が必要）
Date: 2026-06-25
関連: `docs/multi-user-cloudkit-sync-design.md`（Step 1・2）
参照コード: `docs/spike/CloudKitSpike.swift`（ビルド対象外の雛形）

## なぜ最初にこれをやるのか

Architect レビューの最重要指摘：**別 Apple ID 間の CKShare 共有がこの設計で最も嵌まりやすい部分**。
データモデル再設計や Core Data 移行に本腰を入れる**前に**、ここが実機で本当に成立するかを最小コストで実証する。
ここで詰まったら、薄い `UserDataStore` 境界のおかげで Supabase 案へ低コストで旋回できる（保険）。

**このスパイクは使い捨て**。本実装ではなく「前提の実証」が目的。別ブランチ（例: `spike/ckshare-YYYYMMDD`）で行い、結果を記録したら破棄してよい。

## 前提（用意するもの）

- **2 つの Apple ID**（親役・子役）。テスト用サンドボックスでよい。
- **実機 2 台**：親 iPhone（iOS 16+）＋ 子 iPad（iOS 16+）。**シミュレータ不可**（CloudKit/共有は実機が必要）。
- 両端末とも **iCloud にサインイン済み**・オンライン。
- Xcode の署名チーム（`DEVELOPMENT_TEAM = 34WGLQNY3N`）で両端末にインストールできること。
- ⚠️ 「子はログインなし」はアプリ内アカウントを作らない意味。**CloudKit アクセス自体には子端末の iCloud サインインが必要**。

## A. Xcode の capability 設定（GUI・一度きり）

ターゲット `SpellingTrainer` → Signing & Capabilities：

1. **+ Capability → iCloud**
   - Services: **CloudKit** にチェック。
   - Containers: `iCloud.com.yuta090.SpellingTrainer` を新規作成して選択。
2. **+ Capability → Background Modes**
   - **Remote notifications** にチェック（サイレントプッシュで変更受信）。
3. **+ Capability → Push Notifications**（CKSubscription のため）。

これで `SpellingTrainer.entitlements` に概ね以下が入る：

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.com.yuta090.SpellingTrainer</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>aps-environment</key>
<string>development</string>
```

`Info.plist` の `UIBackgroundModes` に `remote-notification` が入ることも確認。

## B. 参照コードの貼り付け

`docs/spike/CloudKitSpike.swift` の内容を、スパイク用ブランチでアプリに取り込む（要 Xcode で Sources に追加）。要点：

- `NSPersistentCloudKitContainer` に **private と shared の 2 ストア記述**を設定（iOS 15+）。
- `Household` エンティティ（最小：`id`, `title`）と `Attempt` 最小エンティティを Core Data モデルに追加。
- 親で `Household` を作成 → `container.share(_:to:)` で `CKShare` 生成 → `UICloudSharingController` で招待。
- 子で共有招待を受諾（`windowScene(_:userDidAcceptCloudKitShareWith:)` → `acceptShareInvitations`）。

## C. テスト手順（2 台で実施）

### C-1. 共有の確立
1. 親 iPhone：アプリ起動 → 「世帯を作成」→ `Household` 1件生成。
2. 親：「子の iPad をつなぐ」→ `UICloudSharingController` で **read-write** 招待を発行（メッセージ/AirDrop で子へ）。
3. 子 iPad：招待リンクを開く → 受諾。
4. **観察**：親では `Household` が **private DB** に、子では **shared DB** に現れること（参照コードがどちらのストアに入ったかをログ出力）。

### C-2. 子→親（答案アップ＆通知）
5. 子：`Attempt`（`needsReview` 相当）を 1件作成。
6. **観察**：数十秒〜数分で親端末に同期される（共有ゾーン経由）。
7. 親：バックグラウンドで受信→`ReviewRequest`/件数を計算しローカル通知が出るか（D 参照）。

### C-3. 親→子（採点の反映）
8. 親：別レコード `Review`（`approved`）を作成（**Attempt は不変・別行で採点**＝設計どおり）。
9. **観察**：子端末に `Review` が同期される。

### C-4. オフライン
10. 子：機内モードで `Attempt` を作成 → 後でオンラインに戻す。
11. **観察**：復帰後に同期されること（ローカル Core Data だけで UI が完結していること）。

### C-5. 取り消し・異常系
12. 親：共有を取り消す（participant 削除）。**観察**：子がアクセス不能になること。
13. 子端末を iCloud サインアウト。**観察**：アプリがクラッシュせず、状態（未サインイン）を表示できること。

## D. 通知スパイク（Architect Step 2）

`NSPersistentCloudKitContainer` は**業務イベントのプッシュ機構ではない**点を体感で確認する：

1. 親端末でリモート変更通知（`NSPersistentStoreRemoteChange`）を購読。
2. import 後に「未採点 = `requiresParentReview && unreviewed`」件数を計算（`SpellingSyncCore.ReviewProgress.pendingCount` がそのまま使える）。
3. 件数 > 0 でローカル通知を発火。
4. **観察ポイント**：通知の遅延・取りこぼし・アプリ強制終了後の挙動。best-effort で実用に耐えるか判断する。

## E. 合否基準（記録すること）

| # | 確認項目 | 結果 | メモ |
|---|---|---|---|
| 1 | 別 Apple ID 間で共有招待を受諾できる | ☐ | |
| 2 | owner=private / participant=shared に正しく入る | ☐ | |
| 3 | 子→親へ Attempt が同期される（時間も記録） | ☐ | 反映まで __ 秒 |
| 4 | 親→子へ Review が同期される | ☐ | |
| 5 | オフライン作成→復帰で同期される | ☐ | |
| 6 | 共有取消で子がアクセス不能になる | ☐ | |
| 7 | サイレントプッシュ→ローカル通知が出る | ☐ | 遅延 __ 秒 |
| 8 | 強制終了後でも通知が届くか | ☐ | best-effort 体感 |

## F. 判断ゲート

- **1〜6 がすべて ◯ で、7・8 が許容範囲** → 設計どおり Step 3-7（データモデル再設計・Core Data 移行）へ進む。
- **共有(1,2,6)が想定以上に難航** → CloudKit 路線を再考。`UserDataStore` 境界経由で **Supabase 案**（`docs/parent-web-cloud-design.md`）へ旋回。
- **通知(7,8)が実用に耐えない** → 当面は「UI バッジ中心＋通知は補助」で割り切るか、将来 APNs を打つ最小サーバーを別途検討（運用ゼロは一部後退）。
