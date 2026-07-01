---
name: kotoba-sentence-add
description: ことばパズルの問題のもと `sentence_bank.json` に英文を「ルールを守って」安全に増やす手順。学年の壁(NGSL band)・文法の天井(CEFR-J)・トークン数・重複・子ども不適切語を SentenceBankBuilder で機械検査してから同梱する。手で json を直接いじらず必ず CLI を通す。「文を増やす」「sentence_bank に追加」「例文を足す」「問題のもとを増やす」「Tanakaから文を抽出」等で使用。
user-invocable: true
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, mcp__codex__codex
---

# 文を増やす（kotoba-sentence-add）

ことばパズル（並べ替え/あなうめ/リスニング穴埋め）の**問題のもとになる英文**を増やす作業を、毎回同じルールで安全にやる手順書。

> **まず `content-catalog` スキルを読む**（倉庫の地図・在庫件数）。`sentence_bank.json` は倉庫2。**手で json を直接編集しない**——必ず下の CLI を通す（機械検査＋決定論で差分が安定する設計）。

## 大方針（必ず守る）

- **源＝生成（Tanaka ではない）・年齢別**：例文/問題は子の**現在の年齢（学年）に合わせて生成**する（Tanaka抽出は大人題材なので却下＝休眠）。**確定仕様＝`docs/age-tiered-generation-spec-2026-06-29.md`（確定版・要熟読）**。関連メモ [[age-tiered-content-generation]] / [[content-schema-v2-architecture]]。
  - ✅ **スキーマv2の“入れ物”は実装済み（フェーズ①・PR#110）。ただし下記CLI手順はそのまま使える**：authoring 正本 `scripts/person_templates.authoring.json` は**まだ v1 配列**で、`sentence-bank-build` が v1 を直読みして **`sourceID`（安定ID・英文を直しても不変）を自動付与**する（出力 `sentence_bank.json` の47件は付与済み）。`genre`(useful/humor/story) は任意（未指定＝useful）。authoring を v2 envelope `{schema:2,records:[…]}`＋`kind`/canonical sourceID 形式へ移すのは**任意の次フェーズ**で、移す時はこの手順を改訂する。詳細は [[content-schema-v2-architecture]]。
  - ⚠ **確定仕様の要点（必須⇔プールのアプリ配線はフェーズ③で未実装）**：
    - 「ステップ」＝既存 `WordStep`（親/子が登録した単語のまとまり）。**必須(コア)＝そのステップの登録語そのもの／プール＝生成例文**。
    - **生成の2役**：フレーム（`I like ___` 等・語を綴り変えず載せる“乗り物”・**最優先で充実**）と 完成文（ユーモア/物語/日常＝プール露出専用・乗り物にしない）。
    - **必須は登録語の exact 綴りを書かせる**（apple の必須で apples を出さない／必須フレームは綴り不変の型に限る／最後は直接スペルに落とす）。並べ替え・選んで穴うめは必須に使わない。
    - tier(band/文法/漢字)は**生成文・周辺語・和訳・プール**に効かせる（親登録語そのものは tier 例外）。ユーモアはプール限定10%。
- **3つの壁を機械が見張る**：①学年の壁＝文中の**見える内容語すべて**が `targetBand` 以下（文から取り出した語で判定）。②文法の天井＝`grammarCeiling` を超える文法は却下。③**漢字の壁（新規）**＝和訳 `ja` の漢字を**1学年前まで**に制限（`KanjiLevelGate.isWithin(ja, maxGrade:)`／入門はひらがな主体）。超過漢字があればひらがな化して再生成。
- **欠落は警告のみ・却下しない**：`level` 表に無いやさしい語（apple/soccer 等）は、人手の厳選文なら**著者宣言 gradeBand を信頼**して採用（警告は出す）。良い人手データを機械が壊さない（②③の決定）。
- **id は文から決定論 UUIDv5**：同じ文を再生成しても**git 差分ゼロ**。だから何度でも安全に作り直せる。
- **却下が1件でもあると `--write` しない**：部分的な中途半端な同梱物を作らない。却下を全部直してから書き出す。
- **作る人＝agy / レビューする人＝私(Claude Code)**：このプロジェクトの確立した型に従う。候補文は **agy で量産**し、**私(Claude Code)が必ず目視レビュー**してから機械検査・書き出しに進む。大きい/不安な変更のときだけ任意で codex にも独立レビューを回す（CLAUDE.md「レビューを通すこと」準拠）。
- **書き出し＝リポジトリ変更なので作業はブランチ/ワークツリーで**（`main` 直接禁止）。スキル本体(`.claude/`)の編集は main で可。

## 道具（③で構築済み）

| 役 | 場所 |
|---|---|
| 判断（純ロジック・TDD） | `Sources/SpellingSyncCore/SentenceBankBuilder.swift` ＋ `SimpleLemmatizer.swift` |
| **漢字の壁（純ロジック・TDD）** | `Sources/SpellingSyncCore/KanjiLevelGate.swift` ＋ `KyoikuKanji.swift`（現行配当表1,026字） |
| 入出力（薄いCLI） | `Sources/SentenceBankBuild/main.swift` → `swift run sentence-bank-build` |
| curated 素（人手厳選文の入口） | `scripts/person_templates.authoring.json`（行 id/grammar/gradeBand/fallbackEn/fallbackJa） |
| 不適切語ブロック | `scripts/sentence_blocklist.txt`（任意・1行1語） |
| 出力（同梱物） | `iPadPrototype/Resources/sentence_bank.json` |

CLI 引数: `--target-band N`(既定5) / `--grammar-ceiling intro1|intro2|basic1|basic2|applied` / `--max-tokens N`(既定10) / `--write`。

---

## 手順A：厳選文を足す（安全・推奨。まずこれ）

1. **在庫確認**（`content-catalog` の点検コマンド）。足したい文が**もう無いか** `grep` で確認。
2. **ブランチ/ワークツリーを切る**（例 `git worktree add ../SpellingTrainer-wt/feat/sentence-add-<日付> -b feat/sentence-add-<日付>`）。名前衝突を `git branch --list` で確認。
3. **素を足す**：`scripts/person_templates.authoring.json` に行を追加。
   - `fallbackEn`（語配列 or 文）/ `fallbackJa`（子ども向け・ふりがな調）/ `grammar`（既存の `GrammarPoint` 文字列）/ `gradeBand`(1〜5)。
   - 文法は子ども不適切な題材を避ける。`gradeBand` は学年の壁。
4. **プレビュー（書き出さない）**：
   ```bash
   swift run sentence-bank-build --target-band 5 --grammar-ceiling applied
   ```
   レポートの **採用/不採用/警告** を読む。**却下が0になるまで素を直す**（学年超過→やさしい語に / 文法超過→`--grammar-ceiling` か文を変更 / トークン数→短く）。警告(level欠落)は中身を見て、必要なら倉庫1に語を足す（要ユーザー承認）。
5. **書き出し**：
   ```bash
   swift run sentence-bank-build --target-band 5 --grammar-ceiling applied --write
   ```
6. **決定論を確認**：もう一度 `--write` して `git diff` が**増えない**こと（同じ入力＝同じ出力）。
7. **ビルド＆テスト**：`swift test`（コア緑）＋アプリビルド確認。
8. **レビュー（私=Claude Code がやる）**：差分（足した文・採用/却下/警告レポート・json差分）を**私が自分でレビュー**する。観点＝学年/文法の壁を実際に満たすか・日本語が子ども向けか・不適切題材が無いか・決定論差分が素直か。問題があれば素を直して 4 に戻る。大きい/不安なら任意で codex にも回す。
9. **コミット〜マージ〜後片付け**は CLAUDE.md の流れで、**1行でユーザー確認してから**実行。

## 手順B：量を出す（候補を量産 → 私がレビュー → 機械検査）

量を増やす作る人は **agy（生成）**。「**agy が段階別に候補を量産 → 私(Claude Code)がレビュー → SentenceBankBuilder＋KanjiLevelGate で機械検査 → `--write`**」。候補生成と機械検査は別物（生成は粗くてよい、壁/天井/漢字/重複の最終判定は必ず Core が機械でやる）。

### B1：agy で**年齢段階別**に候補を量産（メインの道）
- **作る人＝agy**（Google Antigravity CLI）。`docs/age-tiered-generation-spec-2026-06-29.md` の4段階のうち**1段階を指定**し、その段階の **band 上限・文法 stage 上限・題材許可リスト・漢字 maxGrade（＝段階の最年少の1学年前。入門はひらがな主体）** をプロンプトに明示して、子ども向けの安全な英文＋やさしい和訳（漢字 maxGrade 以内）＋文法タグ＋gradeBand を**まとめて生成**させ、`scripts/person_templates.authoring.json` に足せる形（id/grammar/gradeBand/fallbackEn/fallbackJa）で出力させる。
- **agy の確実な呼び方**（非対話・出力取りこぼし対策）はメモ [[agy-cli-reliable-invocation]] に従う：実バイナリ `/Users/takahashiyuuta/.local/bin/agy` ＋ `--dangerously-skip-permissions` を `script -q /dev/null` で pseudo-TTY 包み、出力は scratch から回収。小バッチ・フォアグラウンド推奨。**一度に大量はダメ**（10kダンプの失敗例 [[age-tiered-content-generation]]）。
- **レビューする人＝私(Claude Code)**：agy 産の候補を**私が必ず目視**し、**下の「レビュー チェックリスト（和訳・英文の自然さ）」を全項目チェック**（題材が段階に合うか・大人題材でないか・**英文が不自然/場面不明でないか**・**和訳が直訳調でないか**・**漢字が許可学年以内か**・文法タグの正しさ）。怪しい行は捨てるか直す。**その後**で手順A 4〜9（プレビュー→却下0→`--write`→決定論→test）。漢字超過は `KanjiLevelGate` で機械的に検出 → ひらがな化して戻す。
- **生成プロンプトに自然さガードを明記**：「①子が実際に使う自然な英文だけ（場面不明・不自然な文を作らない）②定型句は定型表現で③和訳は直訳調にせず日本語として自然に・口調と表現を統一」を毎回入れて、**そもそも粗悪候補を作らせない**。

> **Tanaka 抽出（旧 B2）は休眠**：`TanakaExtractor`＋`tanaka-extract-build` CLI は残っているが、Tanaka は大人向け例文集なので**子ども同梱には使わない**（題材が仕事/政治/抽象・band が難易度にならない）。子ども向けは上の **B1 生成** が正。詳細 [[age-tiered-content-generation]]。

---

## レビュー チェックリスト（和訳・英文の自然さ）★必ず全項目を確認

> **これが品質の生命線**。機械検査（band/文法/漢字/重複）は通っても「**不自然な英文・直訳調の和訳**」は素通りする。アプリの根幹品質に直結するので、**生成後のレビューで1件ずつ下記を確認**し、引っかかったら直す（または捨てる）。**迷ったら声に出して読んで違和感を確かめる**。量が多い/自信が無いときは codex に「和訳ナチュラルネス観点で」並走レビューを依頼。
> 実例の指摘＝[[age-tiered-content-generation]]（「よい おともだち」「I am sorry now」「うさぎが とんでいる(=fly)」等）。

### A. 英文そのものの自然さ（生成段階で弾く・和訳以前の問題）
- **子が実際に使う場面が想像できる文か**。文法が正しくても「言わない文」を作らない。
  - ✗ `I am sorry now` / `Help your good friend` / `Sora has two long legs` / `Thank you, good bird`（場面不明・不自然）。
- 形容詞の乗せ方が不自然（`good friend`/`good bird` のような英語側の違和感）も**英文ごと**直す。和訳だけ直してもダメ。
- → **生成プロンプトに「不自然・場面不明の英文を作らない／定型句は定型表現で」を明記**して、そもそも作らせない。

### B. 和訳の自然さ（直訳調をなくす）
1. **直訳の禁止**：英語の語順・冠詞・所有格をそのまま日本語にしない。呼びかけ `my friend` を機械的に「わたしの おともだち」にしない。
2. **形容詞＋名詞**：`good/nice` 等をそのまま「よい/いい」にしない。日本語で自然な修飾に（`good friend`→「なかよしの／だいじな おともだち」、`good bird`→ただ「ことりさん」）。
3. **定型句は定型訳**：`No thank you`→「いいえ けっこうです」／`You're welcome`→「どういたしまして」／`Have a nice day`→「よい いちにちを」。直訳しない。
4. **表現の統一**：同じ英語表現は全文で同じ訳に（`No thank you` の訳がバラつかない）。
5. **多義語の誤訳**：`jump`=はねる を「とぶ(fly)」と訳さない等。**動物の動作は特に注意**（はねる/とぶ/およぐ/あるく）。
6. **指示詞**：`These/Those` を「これら/それら」と硬く訳さない（子は使わない）。文脈で「これ、〜だよ」等。
7. **語尾の統一**：です・ます と だ・よ を混ぜない。子向けは親しみやすい口調で統一。
8. **子ども口調・ふりがな調**：硬い書き言葉でなく話し言葉・やさしい言い回し。漢字は段階の上限内（[[KanjiLevelGate]]）。

---

## つまずきポイント

- **「park が消えた / red が band2 で弾かれた」系**＝壁は文中の見える語で判定。著者が思っている語と、機械が文から取り出す語がズレると却下/別判定になる。レポートの理由（`overTargetBand`/`unleveledContentWord`）を見て、**素の文かbandを直す**。
- **却下0なのに書き出されない**＝`--write` 付け忘れ、またはリポジトリ直下以外から実行（相対パスが外れる）。
- **差分が毎回ぶれる**＝出力は決定論のはず。ぶれたら入力（素 json）が実行ごとに変わっていないか確認。

> このスキルは `.claude/`（git管理外）。CLI 引数やパスが変わったら**この手順も更新する**。関連: `content-catalog`（倉庫地図）/ `kotoba-puzzle-format`（形式追加）。
