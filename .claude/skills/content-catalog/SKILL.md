---
name: content-catalog
description: SpellingTrainer の全コンテンツ（文・問題・ヒント・おとり語・名前テンプレ・単語/訳/例文/学年）が「どこに・どんな形で・何件・どう足すか・どの機械が使うか」をまとめた地図。新しい問題・文・ヒント・おとり・データを作る/探す前に必ず最初に読む（二重実装を防ぐ）。「コンテンツどこ」「もう有る?」「二重実装したくない」「文/問題/ヒント/おとり/テンプレを足したい・探したい」「データの正本はどこ」「在庫を見たい」等で使用。
user-invocable: true
allowed-tools: Read, Bash, Glob, Grep
---

# コンテンツ地図（content-catalog）

SpellingTrainer の**コンテンツ（文・問題・ヒント・おとり語・単語データ等）が全部どこにあるか**の地図。
**新しい問題・文・ヒント・データを作る前に、まずこの地図を見る**。似たものが既に有るのに作り直す「二重実装」を防ぐのが目的。

> ⚠ **着手前にもう一手（地図だけでは並行衝突を防げない）**：複数エージェントが同時に動くので、実装に入る前に **`git branch -a` と `git log --oneline -15 main`** で同種ブランチ/最近の関連マージを確認し、作る予定のファイル/型が **`git ls-tree -r main \| grep <名前>`** で main に既に無いか確認する。実際に「ことばパズル配線(PuzzleContentBuilder)」が別エージェントと二重実装になった事例あり（[[duplicate-implementation-needs-claim]]）。

## 一番大事な前提（これを知らずに作ると二重実装になる）

**「問題」と「ヒント」はデータとして貯めていない。原材料から“その場で機械（ジェネレータ）が組み立てている”。**

- だから「問題の箱」「ヒントの箱」を探しても無い。**ヒントの文言を直したい＝ジェネレータ（コード）を直す**のであって、データ追加ではない。
- 貯めてある“原材料”は下の **4つの倉庫だけ**。新しいコンテンツは原則この4倉庫のどれかに足す（新しい箱を不用意に増やさない）。

---

## 倉庫の地図（貯めてある原材料は4つだけ）

| # | 倉庫 | パス | 中身 | 足し方（道具） | 正本ドキュメント |
|---|---|---|---|---|---|
| 1 | **単語データ** | `iPadPrototype/Resources/wordbank.sqlite`（読取専用・同梱） | `gloss`=英→和訳 / `examples`=英日例文(Tanaka, 子ども不適切除外済) / `level`=単語→Dolch学年+NGSL難易度band | 開発時のみ手で編集（ユーザー承認時）。`gray`/`math` 等の欠落語は手で追加した実績あり | CLAUDE.md「同梱データ」 |
| 2 | **ことばパズルの問題のもと（文）** | `iPadPrototype/Resources/sentence_bank.json` | 厳選文（en/ja/tokens/grammar/gradeBand/**id**＝表層UUIDv5/**sourceID**＝安定ID・任意の**genre**=useful/humor/story）。並べ替え・あなうめ・リスニング穴埋めの**素** | **`kotoba-sentence-add` スキル**（`sentence-bank-build` CLI で機械検査して追加。CLI が sourceID を自動付与） | `docs/kotoba-puzzle-spec-2026-06-28.md` |
| 3 | **名前入れテンプレ（例文に友達/本人を登場）** | `iPadPrototype/Resources/person_templates.authoring.json`<br>＋著者用原本 `scripts/person_templates.authoring.json` | 役スロット付きテンプレ文（fallbackEn/Ja/grammar/gradeBand）。`sentence-bank-build` の curated 素もここ | 原本(scripts側)に行を足す → `sentence-bank-build` | `docs/personalized-sentences-spec-2026-06-28.md` / `docs/personalized-sentences-authoring-2026-06-28.md` |
| 4 | **音が似たおとり語** | `iPadPrototype/Resources/confusables_sound.build.csv`<br>＋著者用原本 `scripts/confusables_sound_draft.csv` | 見出し語→音が似た語2〜4個。リスニング系の**ひっかけ選択肢**の素 | 原本(draft)に行を足す → `swift run confusables-build --write`（`ConfusablesValidator` が機械検査） | `docs/confusables-sound-authoring-DRAFT-2026-06-28.md` |

> 倉庫2/4は **「機械検査して同梱物を書き出す」道具がある**（人手の良データを壊さない＝欠落は警告のみ）。**手で json/csv を直接いじらない**。必ず CLI を通す（決定論で差分ゼロになるよう設計済み）。

---

## 生成の地図（問題・ヒントは“貯めず作る”：直したい時はここ＝コード）

ことばパズルは1メニューから複数形式をランダム出題する。形式ごとに「出題を組み立てる機械(Generator)」「採点する機械(Grader)」がコアにある。

| 出題形式 (`PuzzleFormat`) | 子ども向け名 | 組み立てる機械（コア） | 使う原材料 | 状態 |
|---|---|---|---|---|
| `wordOrdering` | ぶんづくり（並べ替え） | `Sources/SpellingSyncCore/SentenceExercise.swift` | 倉庫2,3 | ✅遊べる |
| `clozeChoice` | あなうめ（選ぶ） | `ClozeChoice.swift` | 倉庫2,3 | ✅遊べる |
| `listeningCloze` | きいて あなうめ | `ListeningCloze.swift`（おとり選択は `ClozeChoiceGenerator` 委譲） | 倉庫2,4 | ✅遊べる |
| `wordListening` | おとを きいて えらぶ | `WordListening.swift` | 倉庫4 | ✅遊べる |
| `clozeHandwriting` | 手書き穴埋め | （未実装） | 倉庫2 | ❌未・AI/OCR採点待ち(⑤) |
| `composition` | 英作文 | （未実装） | 倉庫2 | ❌未・AI VLM採点待ち(⑤) |

- **出題プールの組み立て**: `Sources/SpellingSyncCore/PuzzleContentBuilder.swift`（コア・決定論）。同梱の文バンク(`SentenceBankBundle`=倉庫2)＋音類似おとり(`ConfusablesBundle`=倉庫4)から、ぶんづくり/あなうめ/きいてあなうめ/単語リスニングの各プールを作る。あなうめのおとり＝**同じか下の学年の内容語**（上位学年語は出さない）。アプリ側 `PuzzleSessionView.PuzzleContent` はこれを呼ぶだけ＝**ここに新しいデモ文をハードコードしない**（二重実装になる）。文を増やすのは倉庫2へ（`kotoba-sentence-add`）。
- **形式の一覧と遊べる/未の切替**: `Sources/SpellingSyncCore/PuzzleFormat.swift`（`isPlayable` を true にするとプールに入る）。
- **ヒント／答え合わせ説明（おぼえかた）**: `Sources/SpellingSyncCore/AnswerExplanation.swift`（`SentenceFeedback.make` が **文法タグから自動生成**）＋ アプリ表示 `iPadPrototype/AnswerExplanationCard.swift`。**文言を変えたい＝ここを直す**（データ追加ではない）。
- **新しい“出題形式”を足したい**時は別スキル **`kotoba-puzzle-format`**（コア＝Generator/Grader、UI＝PuzzleKit）。
- **年齢別の生成（例文も問題も子の現在の学年に合わせる）**: **確定仕様＝`docs/age-tiered-generation-spec-2026-06-29.md`（確定版）**。源は **AI生成（Tanakaではない）**。壁＝語彙band(ゆるい上限)＋文法stage＋**漢字** `Sources/SpellingSyncCore/KanjiLevelGate.swift`＋`KyoikuKanji.swift`（和訳 `ja` の漢字を1学年前まで／現行配当表1,026字）。文を足す手順は `kotoba-sentence-add`。関連 [[age-tiered-content-generation]] / [[content-schema-v2-architecture]]。
  - ✅ **スキーマv2の“入れ物”＝実装済み（フェーズ①完了・PR#110）／アプリ配線＝未（フェーズ③）**。骨子：「ステップ」＝既存 `WordStep`（登録語のまとまり）。**必須=登録語そのもの（綴りを書かせる・最後は直接スペルに必ず落ちる）／プール=生成例文（フレーム=乗り物 と 完成文=露出）**。満点で必須→ランダム自動切替。ヒント/ユーモアは親設定。実装着手前に [[content-schema-v2-architecture]] を読む。
    - **①で出来た“入れ物”（Coreの純ロジック・倉庫地図はそのまま使える）**：
      - `SentenceItem` に `sourceID`（安定ID）と `genre` を追加。`sentence_bank.json` の47件は **sourceID 付与済み**（git差分は sourceID 追加のみ・表層UUIDは不変）。
      - `Sources/SpellingSyncCore/ContentSchemaV2.swift` … `AuthoringSource.decode` が **v1ルート配列**と**v2 envelope `{schema:2,records:[…]}`** を先頭バイトで判別（dual-decode）。v2レコードは `kind: plain\|personTemplate\|frameTemplate` ＋ canonical `sourceID` 必須。**※ authoring 正本 `scripts/person_templates.authoring.json` はまだ v1 配列**（CLIも今は v1 直読み＋sourceID 自動導出）。v2 envelope へ移すのは任意の次フェーズ。
      - `ContentPolicy.swift`（band/文法/漢字/genre/i+1 でプールを絞る純関数・**親登録語は tier 例外**）／`CoreProblem.swift`（`CoreProblemResolver`＝綴り不変フレーム→直接スペル終端）／`RequiredCompletion.swift`（stepID＋登録語集合の signature で完了管理・語が変われば自動で未完了に戻る）／`ContentIDResolver.swift`（表層ID alias 1ホップ）。
      - **未配線（③でやる）**：アプリは sourceID/genre/必須⇔プール切替/ContentPolicy をまだ使っていない。`PuzzleContentBuilder`・出題UIは v1 のまま。

---

## 「足したい物 → 行き先」早見表

| 足したい/直したい | 行き先 | 使うもの |
|---|---|---|
| 問題に使う**英文**を増やす | 倉庫2 `sentence_bank.json` | **`kotoba-sentence-add` スキル** |
| 例文に**友達/本人の名前**を出すテンプレ | 倉庫3 person_templates | 原本に行追加→`sentence-bank-build` |
| リスニングの**ひっかけ（音が似た語）** | 倉庫4 confusables | 原本(draft)に行追加→`confusables-build --write` |
| 単語の**訳・学年band**の欠落を補う | 倉庫1 wordbank（手編集・要承認） | sqlite 直編集 |
| **ヒント/答え合わせの文言**を変える | コード `AnswerExplanation.swift` | `kotoba-puzzle-format` 参考 |
| **新しい出題形式**そのもの | コア＋PuzzleKit | **`kotoba-puzzle-format` スキル** |

---

## 在庫点検（今の件数を見る）

作る前に「もう何件あるか」を見る。リポジトリ直下から:

```bash
# 倉庫1: 単語データ
for t in gloss examples level; do printf "%s: " "$t"; \
  /usr/bin/sqlite3 iPadPrototype/Resources/wordbank.sqlite "SELECT count(*) FROM $t"; done

# 倉庫2: 問題のもと（文）の件数と学年band分布
/usr/bin/python3 -c "import json;d=json.load(open('iPadPrototype/Resources/sentence_bank.json'));\
from collections import Counter;print('文:',len(d));print('band分布:',dict(sorted(Counter(x['gradeBand'] for x in d).items())))"

# 倉庫4: おとり語
tail -n +2 iPadPrototype/Resources/confusables_sound.build.csv | grep -c . | xargs echo "おとり見出し語:"
```

特定の英文/単語が**もう有るか**を確かめる（二重作成の最終チェック）:

```bash
grep -i "探したい英文の一部" iPadPrototype/Resources/sentence_bank.json
/usr/bin/sqlite3 iPadPrototype/Resources/wordbank.sqlite "SELECT word,band FROM level WHERE word='apple'"
```

---

## 正本ドキュメント（迷ったら原典）

- ことばパズル全体 index: `docs/kotoba-puzzle-spec-2026-06-28.md`
- 出題形式とおとり: `docs/exercise-formats-and-distractors-2026-06-28.md`
- 学年の壁(NGSL) / 文法の壁(CEFR-J): `docs/grammar-level-cefrj-2026-06-28.md`
- 名前入れ例文: `docs/personalized-sentences-spec-2026-06-28.md`
- 設計の核(Core=判断 / CLI=入出力 / 文バンク): `docs/sentence-builder-design-2026-06-27.md`

> このスキルは `.claude/`（git管理外）。コンテンツの場所・件数・道具が変わったら**この地図も更新する**（地図が古いと二重実装が戻ってくる）。
