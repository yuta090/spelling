# ことばパズル（文法練習 / sentence-builder）仕様 — 集約版 2026-06-28

Status: **実装中**（並べ替え・穴埋め選択・混合・単語リスニング・リスニング穴埋めは動作／手書き穴埋め以降は計画）。
このドキュメントは機能全体の**正本（index）**。詳細は各サブ仕様にリンク。後から AI / 人が参照する前提で「決定事項」と「実装状況」を正確に残す。

関連サブ仕様:
[sentence-builder-design-2026-06-27.md](sentence-builder-design-2026-06-27.md)（全体設計）/
[exercise-formats-and-distractors-2026-06-28.md](exercise-formats-and-distractors-2026-06-28.md)（形式・おとり研究）/
[grammar-level-cefrj-2026-06-28.md](grammar-level-cefrj-2026-06-28.md)（文法の学年壁=CEFR-J）/
[personalized-sentences-spec-2026-06-28.md](personalized-sentences-spec-2026-06-28.md)・[personalized-sentences-authoring-2026-06-28.md](personalized-sentences-authoring-2026-06-28.md)（名前入り例文）/
[answer-explanation-spec-2026-06-28.md](answer-explanation-spec-2026-06-28.md)（答え合わせ解説）/
[learning-loop-design-2026-06-28.md](learning-loop-design-2026-06-28.md)（学習ループ）/
[confusables-sound-authoring-DRAFT-2026-06-28.md](confusables-sound-authoring-DRAFT-2026-06-28.md)（リスニングおとり辞書）

---

## 0. 名称（決定 2026-06-28）
- **子ども向け表示名 = 「ことばパズル」**（🧩）。代替候補「ことばあそび」。
- **親（管理）側 = 「文法」表記でよい**（二枚看板）。
- 理由: 2人ユーザーの軸で、子には専門用語(「文法」)・テスト用語(「クイズ」)を出さない。「パズル＝遊び」でタイル並べ操作に合い、複数形式が混ざっても効く“傘”の名前。
- **現状は本番UI未配線**（DEBUG ランチャ/デモのみ。MixedSessionView 等の見出しは暫定「れんしゅう」）。本番UI化のときにこの名前を使う。

## 1. 最重要原則：テストではなく「ゲーム」
- **「間違えてOK・何度でもやってみよう」**が体験の軸。文法を楽しく覚えるゲームで、採点テストではない。
- 不正解は前向きな言葉（「ナイス チャレンジ！／あと◯こ！」）。**点数・正答率・「採点」などテスト用語の見せ方は避ける**。
- リトライ無制限・低ストレス・即フィードバック。間違い＝学びのきっかけ（**解説＝おぼえかた**を出す）。
- 子向けは文法用語ゼロ・大きいタイル・ドラッグ・即発音/バウンス・キャラ反応。

## 2. 決定事項（ユーザー確認済み）
1. **形式はシステムが自動ミックス**（子に選ばせない＝1画面1動作）。
2. **学年の壁は二軸**：
   - **語彙の壁（NGSL バンド）**：出題文の内容語はすべて対象学年バンド以内（絶対）。範囲内なら未習語が混じってよい。
   - **文法の壁（CEFR-J）**：対象学年以下で習う文法を上限。上限内なら本人未習の文法が出てもOK＝クイズ感覚。学年超えは出さない。
3. **未習語タップ→復習**：わからない語は**回答後に子が自分で選んで**マーカー→ child ソース語として SRS box1 に登録→以後いつものスペル練習に「ふくしゅう」として再出題。
4. **不正解時に「かいせつ」**：その文法ポイント＋答え合わせ説明を表示（クイズ→解説で定着）。
5. **音声は「子が並べた文」を読む**：「きいてみる」は正解文でなく**いま並べた文**を読み上げ（答えが漏れず耳でセルフチェック）。設置は完成文の真下。
6. **文データは2系統**：(a) 厳選（curated・主） + (b) Tanaka Corpus（従・子ども適切な短文のみ）。
7. **例文は名前入りに対応**：親が友達/本人を登録（Cast）→ 役スロットテンプレで例文に名前が登場（本人は呼びかけ専用）。

## 3. 出題形式カタログ ＆ 実装状況
共通の素は `SentenceItem(en, ja, tokens[], gradeBand, contentLemmas[], grammar?)`。どの形式もここから生成。

| 形式 | 内容 | 入力 | 採点 | 実装状況 |
|---|---|---|---|---|
| **並べ替え** | 和訳→単語タイルを正しい順に | tap/drag | 決定的 | ✅ 本物コンテンツ(名前入り34テンプレ)で動作。`WordOrderingView` |
| **穴埋め(選択)** | 文に空所・選択肢から | tap | 決定的 | ✅ Core＋デモ。`ClozeChoiceView` |
| **混合セッション** | 形式を自動ミックス・直前回避 | — | — | ✅ `SessionComposer` ＋ `MixedSessionView` |
| **単語リスニング** | 音を聞いて正しい綴りを選ぶ | tap | 決定的 | ✅ Core＋試遊画面。スピーカーで何度でも再生・クイズ前に音ON/OFFゲート。`WordListeningView` |
| **リスニング穴埋め** | 文の空所・**設問中は無音→回答後に音**・公共用にON/OFF | tap | 決定的 | ✅ Core＋試遊画面。音の近いおとり(confusables)で空所を作る。`ListeningClozeGenerator`／`ListeningClozeView` |
| 穴埋め(手書き) | 空所に語を手書き | handwrite | AI/OCR | ⬜ 計画 |
| 英作文 | 和訳→全文を手書き | handwrite | AI VLM | ⬜ 計画 |

> リスニングの設計詳細: 設問中の空所は**無音**、音は**回答後**に再生。クイズ開始前に「リスニングする?」**ON/OFF を選べる**（電車内など公共の場対応）。おとりは confusables_sound（音の近さ）を使う。

## 4. データソース
| データ | 置き場所 | 状態 | 用途 |
|---|---|---|---|
| 名前入り例文テンプレ | `iPadPrototype/Resources/person_templates.authoring.json`（34件・承認済） | ✅ 同梱・配線済 | 並べ替え等の本物コンテンツ |
| リスニングおとり辞書（原本） | `scripts/confusables_sound_draft.csv`（40行・`approved=1`） | ✅ main にあり | ビルドツールの入力 |
| リスニングおとり辞書（同梱） | `iPadPrototype/Resources/confusables_sound.build.csv`（検証済み40行） | ✅ 同梱・両リスニング画面が読込 | 単語/リスニング穴埋めのおとり |
| 文バンク `sentence_bank` | 同梱 sqlite（学年タグ・トークン済み・前処理生成） | ⬜ 未生成 | curated＋Tanaka を学年タグ付けして引く |
| `wordbank.sqlite` | `iPadPrototype/Resources/`（読取専用） | ✅ | gloss/examples/level（NGSLバンド・Dolch） |

おとり辞書の運用: AI生成は必ず `approved=0`、人が音の近さを承認した行を `approved=1`。同梱は `approved=1` のみ。ビルド/検証は `swift run confusables-build [--write]`（原本CSV＋wordbank→検証→同梱CSV）。**ハード規則**（承認済み・見出し語と別・重複なし・個数2〜4・正規化・CSV安全・見出し語の二重登録なし）違反は却下し書き出さない。**wordbank 実在/band** は警告のみ（自動削除しない＝gloss欠落で良データを壊さない）。

## 5. コードの置き場所（プロジェクト規約：純ロジックは Core・アプリは薄く）

### SpellingSyncCore（純粋・TDD・`swift test`）
| ファイル | 役割 |
|---|---|
| `SentenceExercise.swift` | `SentenceItem` / `ExerciseFormat` / 並べ替え生成＆採点 / `SeededShuffle` / 出題範囲選択 |
| `GrammarLevel.swift` | `GrammarStage` / `GrammarPoint`(24) / CEFR-J マップ / `GrammarGate` |
| `ClozeChoice.swift` | 穴埋め選択 生成＆採点 |
| `SessionComposer.swift` | 形式ミックス・直前同形式回避の決定論セッション列 |
| `PersonalizedSentences.swift` | Cast / 役スロットテンプレ / `SentencePersonalizer.resolve`（名前流し込み・文頭大文字化） |
| `PersonalizedSessionBuilder.swift` | 名前入りテンプレ→セッション組み立て |
| `AnswerExplanation.swift` | 答え合わせ説明（正解・意味・文法解説チップ） |
| `ConfusablesSound.swift` | リスニングおとり辞書 パース＋検索（承認済みのみ）※本リスニングブランチ |
| `ConfusablesValidator.swift` | おとり辞書のビルド検証（ハード規則=却下／実在・band=警告／再パース可能CSVへ serialize）＋ CLI `Sources/ConfusablesBuild` |
| `WordListening.swift` | 単語リスニング 生成＆採点 ※本リスニングブランチ |
| `ListeningCloze.swift` | リスニング穴埋め 生成（音類似おとりで空所選択→`ClozeChoiceGenerator` に委譲・おとり0なら次候補/nil） |
| `ReviewQueue.swift` ほか | 間違い注入の復習エンジン（全活動共通） |

### アプリ（iPadPrototype・薄く＝提示と入力のみ）
| ファイル | 役割 |
|---|---|
| `WordOrderingView.swift` | 並べ替えプレイ画面（答えカード・音声・未習語マーカー配線済） |
| `ClozeChoiceView.swift` | 穴埋め選択 デモ |
| `ListeningClozeView.swift` | リスニング穴埋め デモ（設問は無音・回答後に完成文を読む・音ON/OFFゲートは“やわらかい”=OFFでも遊べる） |
| `ConfusablesBundle.swift` | 同梱 `confusables_sound.build.csv` を読み `ConfusableEntry` 群へ（両リスニング画面のおとり供給・一度だけキャッシュ） |
| `MixedSessionView.swift` | 混合セッション デモ |
| `RealContentSession.swift` | 34テンプレ→デモCastで resolve→並べ替えで再生（本物コンテンツ試遊） |
| `AnswerExplanationCard.swift` | 答え合わせカードUI |
| `SpeechPlayer.swift` | TTS（AVSpeechSynthesizer） |

> いずれも現状 DEBUG ランチャ（`SpellingTrainerApp.swift` の overlay）から開く試遊画面。本番導線・ホーム配置は未実装。

## 6. 決定論（Core 共通規約）
`Date()` / 乱数 / `String.hashValue` を使わない。`seed` から再現可能（`SeededShuffle`＝SplitMix64＋Fisher-Yates、`DeterministicHash`＝FNV-1a）。テスト容易・同期安全のため。

## 7. 次の実装ステップ
1. ✅ 単語リスニング：Core＋試遊画面（音声・音ON/OFFゲート）完了（`WordListeningView`、DEBUGインラインデータ）。残り＝本物データへの差し替え（下記3）と、その時に「承認おとり0語はスキップ」処理を入れる。
2. ✅ リスニング穴埋め：`ListeningCloze`（音類似おとりで空所選択→`ClozeChoiceGenerator`）＋ `ListeningClozeView`（設問は無音／回答後に完成文を読む／音ON/OFFゲートは OFF でも遊べる“やわらかい”版）。DEBUGインラインデータ。残り＝下記3の本物データ差し替え時に、トークンの正規化（`sea.` のような句読点付きは現状ヒットしない＝`sentence_bank` は語のみトークン化を保証 or 検索側で正規化）を確認する。
3. ✅ confusables_sound のビルド/検証ツール（`ConfusablesValidator`＝Core/TDD・`confusables-build`＝薄いCLI）→ 同梱 `confusables_sound.build.csv` 生成・`WordListeningView`／`ListeningClozeView` を `ConfusablesBundle` 経由の同梱データに差し替え済。残課題：band 不明語（level未収録の易しい語）は警告のまま運用、必要時に level 整備。
4. 文バンク前処理（curated＋Tanaka 学年タグ付け）→ `sentence_bank` 生成。
5. 本番UI化（「ことばパズル」ホーム導線・親側の文法/範囲設定）。
6. 産出形式（穴埋め手書き・英作文）を AI 採点へ接続。
