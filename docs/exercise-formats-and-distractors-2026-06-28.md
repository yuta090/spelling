# 設問フォーマット＆選択肢（おとり）設計 — 2026-06-28

Status: 企画まとめ（実装前のリファレンス）。Duolingo リサーチ＋distractor 研究反映。
関連: [sentence-builder-design-2026-06-27.md](sentence-builder-design-2026-06-27.md)（文づくり全体）／[grammar-level-cefrj-2026-06-28.md](grammar-level-cefrj-2026-06-28.md)（学年の壁）／[answer-explanation-spec-2026-06-28.md](answer-explanation-spec-2026-06-28.md)（答え合わせ説明）

## 0. 原則
- **複数フォーマットで飽きさせない**（Duolingo 流）。同じ `SentenceItem` を形式違いで出し、**SessionComposer が自動で混ぜる**（子に形式は選ばせない＝1画面1動作）。
- **テストでなくゲーム**：間違えてOK・何度でも。答え合わせ後は正解文＋意味、不正解時はヒント（[answer-explanation-spec](answer-explanation-spec-2026-06-28.md)）。
- 既存資産を最大再利用：`SentenceItem`(en/ja/tokens/grammar/band) ／ `AnswerExplanation` ／ 未習語チューザー ／ 学年の壁（語彙=NGSL・文法=CEFR-J）。

## 0.5 間違えたクイズは何度も戻ってくる（SRSで自然に復習）【決定 2026-06-28】
- **間違えたクイズ（文・設問）は“1回正解で卒業しない”**。`SRSScheduler`（Leitner box1–5）に乗せ、**誤答→box1／正答→box+1**、**box5＋間隔超えで初めて mastered**（既存ロジック流用）。
- **他のステップ／別セッションをまたいで再出題**：間隔（0→1→3→7→16日）で自然に再登場。**別のクイズをやっている最中にも、復習期日の来た“間違えた文”が混ざって出る**（`SessionComposer` が due な復習項目を差し込む）。
- **キー＝文（`SentenceItem`）単位**で誤答履歴を追う。再出題の**形式は変えてよい**（並べ替えで間違えた文を、次は穴埋めで＝多角的復習）。
- 単語側の `(word, skill: spelling|usage)` と並ぶ概念。SRSは1エンジン、状態は項目ごとに分離（[learning-loop-design](learning-loop-design-2026-06-28.md) 参照）。
- ねらい：**やり直し＝ゲームの自然な一部**。「間違えたものほど何度も会う→いつの間にか覚えてる」を体験にする。

## 1. 設問タイプ・カタログ
| タイプ | 鍛える力 | 入力 | Duolingo 相当 | 必要な“候補/おとり” | 状態 |
|---|---|---|---|---|---|
| 並べ替え | 語順・文法 | タップ | Arrange the words | なし | ✅実装済 |
| 並べ替え＋おとり語 | 語順（難） | タップ | Word bank 翻訳 | 同レベルの余分な語 | wordbank自動 |
| 穴埋め・選択（読む） | 文法/語彙・文脈 | タップ | Complete the translation | 語形変化＋同レベル語 | 自動 |
| リスニング穴埋め | 聞き取り＋語彙 | 聞く→タップ | What do you hear? | 音が近い語（minimal pair） | ★要データ |
| 意味選択（英⇄和） | 語彙・意味 | タップ | Mark the correct meaning / Tap the pairs | 別の訳語・類義 | gloss＋★ |
| 単語リスニング（音→つづり） | 聞き分け・音韻 | 聞く→タップ | What do you hear?(語) | minimal pair | ★要データ |
| 穴埋め・手書き | 産出＋つづり | 手書き | （Duolingoに無い＝強み） | なし（AI/OCR） | 強み |
| ディクテーション（聞いて文を書く） | 聞く＋書く＋つづり | 手書き | Type what you hear | なし（AI採点） | ★独自性高 |
| 英作文（言いたい事を文に） | 産出（最強） | 手書き | 開放翻訳 | なし（AI採点） | 強み |

> **手書き系（穴埋め手書き・ディクテーション・英作文）は Duolingo に無いうちの強み**。リスニング×手書きの「ディクテーション」は目玉候補。

## 2. リスニング設計（決定済み）
- **設問中は空所を無音**（公共の場・電車でも安心。答えが音でバレない）。
- **回答後に正しい文を音声**で聞ける（`AnswerExplanation.correctText` ＋既存「きいてみる」）。
- **クイズ開始前に「リスニングする？」を選べる**（セッション設定。音を出せない場面に対応）。

## 3. 選択肢（タイル／おとり）の設計
### 3.1 chunk タイル＝難易度レバー（Duolingo 流）
- タイルは**単語**とは限らず**複数語のかたまり**（"is eating" / "to the store"）で出せる。
- **初級＝かたまりタイル**（負荷↓・コロケーション学習）→ **上級＝単語＋おとり**（難）。
- 注意：この「かたまり（句）」は **おぼえかたヒントの綴り chunk とは別物**。ただし**同じ「かたまり」見た目言語**で統一する。

### 3.2 良いおとりの原則（distractor 研究）
出典: [Automatic distractor generation (PMC/Springer)](https://telrp.springeropen.com/articles/10.1186/s41039-018-0082-z) ／ [Plausible Distractors via Student Choice (arXiv 2501.13125)](https://arxiv.org/abs/2501.13125)
- **答えに合わせる**：同**品詞**・近い**長さ**・近い**難易度/頻度**（浮くと即バレ）。
- **もっともらしい＝“学習者がよくする間違い”**を使う（ランダム語より効く）。
- **❌禁止**：**反意語**（対だと正解がバレる）／**答えの類義語**（第2の正解になる）／**答えに似すぎ**（判別不能）。
- **熟達度で“近さ”を変える**：**初級（=本アプリの子）は「音・つづりが近い語」が最も効く**。意味の近さ（near-synonym）は上級向け＆第2正解化に注意。
- **人の承認が必須**（自動生成でも検証→人OK）。

### 3.3 おとり種類カタログ（答え＝`like` の例）
| 種別 | 例 | 効く設問 | 入手 |
|---|---|---|---|
| 語形変化（morphological） | likes / liked / liking | 文法穴埋め | **自動生成** |
| つづりが近い（orthographic） | bike / lime | 読む穴埋め（初級◎） | **自動**（編集距離）＋承認 |
| 音が近い（phonetic, minimal pair） | lake / light | リスニング | ★`confusables_sound`（agy量産） |
| 同レベルの無関係語 | apple / run | 易しいおとり | wordbank **自動** |
| 意味が近い（semantic, 類義） | love / enjoy | 上級・意味選択（注意） | ★`confusables_meaning`（agy量産・慎重） |

## 4. データ計画
**自動生成で賄える（量産不要）**：語形変化（規則）・つづり近似（編集距離）・同レベル無関係語（wordbank band 抽出）。
**量産が要るのは2本だけ**（既存「おぼえかた辞書」と同じ承認フロー）：
- `confusables_sound.csv`：`word, sounds_like(|), approved, source`（音が近い・minimal pair）。
- `confusables_meaning.csv`：`word, similar_meaning(|), approved, source`（意味が近い・**上級用・第2正解化に注意**）。
- ルール：候補は**実在語（wordbank内）・対象学年内**。**AI=approved 0**、人が承認。機械検証（実在・band・反意/類義の除外）＋人の最終判断。

## 5. おとり生成器（純ロジック・TDD・将来）
`DistractorBuilder.make(answer, pool, kind, seed) -> [String]`（決定論）：
- 入力：正解語、候補プール（語形変化＝規則生成／同band＝wordbank／confusables＝辞書）、種別、seed。
- フィルタ：同品詞・近い長さ・反意/類義/答え重複を除外・正解は必ず1つ。
- 出力：正解＋N個のおとりを**決定論シャッフル**（`SeededShuffle` 流用）。`Set`反復・乱数禁止。
- 採点：`ChoiceGrader.grade(selected, answer)`（決定的）。

## 6. 推奨ビルド順
1. **穴埋め・選択（読む）**：データ不要で即・並べ替えと混ぜて変化。
2. **`confusables_sound` を agy で量産**（並行・承認フロー）。
3. **リスニング穴埋め**（無音空所・回答後に音声・開始前ON/OFF）。
4. **ディクテーション**（独自の目玉）。
5. （上級）意味選択＋`confusables_meaning`。

## 7. 出典
- Duolingo 設問タイプ: https://duolingo.fandom.com/wiki/Exercise ／ https://blog.duolingo.com/covering-all-the-bases-duolingos-approach-to-writing-skills/
- おとり研究: https://telrp.springeropen.com/articles/10.1186/s41039-018-0082-z ／ https://arxiv.org/abs/2501.13125
