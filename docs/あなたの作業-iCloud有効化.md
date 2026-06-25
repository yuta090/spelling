# あなたがやる作業（これだけ）

iCloud 同期を動かすために、**あなたにしか出来ない作業はこれ1つだけ**です。
（Apple ID とあなたの Mac の Xcode が必要なため。私＝CLI では押せません）

所要：1〜2分。今すぐでなくてOK。

---

## Xcode で「iCloud」をONにする（3クリック）

1. Xcode で `SpellingTrainer.xcodeproj` を開く。
2. 左の青いプロジェクトアイコン → ターゲット **SpellingTrainer** → 上のタブ **Signing & Capabilities**。
3. 左上の **＋ Capability** ボタンを押す → 一覧から **iCloud** をダブルクリック。
4. 出てきた iCloud 欄で：
   - **Services** の **CloudKit** にチェック。
   - **Containers** の ＋ で `iCloud.com.yuta090.SpellingTrainer` を作って選択。
5. もう一度 **＋ Capability** → **Background Modes** → **Remote notifications** にチェック。
6. もう一度 **＋ Capability** → **Push Notifications**。

> 途中で「Fix Issue」や署名の確認が出たら、あなたの開発チーム（既定で設定済み）を選んでそのまま進めてください。Xcode が自動で設定を整えます。

---

## 終わったら

この作業が終わったら、私に「**iCloud ONにした**」と教えてください。
そのあと、**実際に iCloud に保存・同期するコードは私が全部書きます**（Core Data + CloudKit ストア）。
最後に、あなたが実機2台（親iPhone＋子iPad）で動作確認する手順は
`docs/cloudkit-ckshare-spike-runbook.md` にまとめてあります。

---

## いまの状態（念のため）

- アプリは**まだ iCloud 保存ではありません**。これまで通りローカル保存で普通に使えます。
- このスイッチを入れても、まだ iCloud には保存されません（保存コードはこれから私が書きます）。
- つまり「**入れても壊れない・困らない**」ので、気軽に試して大丈夫です。
