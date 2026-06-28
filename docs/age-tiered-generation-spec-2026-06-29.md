# 年齢別コンテンツ生成 仕様（例文も問題も「現在の年齢」に合わせる）

2026-06-29 / SpellingTrainer

## 背景・方針

ことばパズルの例文・問題は **Tanaka 抽出をやめ、AI で生成して子の「現在の年齢（学年）」に合わせる**。

- Tanaka（大人向け例文集）は安全（暴力/性は弾ける）でも **題材が子ども向けでない**（仕事/政治/経済/抽象・大人口調）。NGSL band も難易度にならない（cow/milk=band5）。→ 同梱しない（抽出ツールは休眠で保持）。
- 子の年齢に合わせる軸は **既にある**。新しい段階を作らず再利用する：
  - **語彙の壁** … NGSL band（`SentenceItem.gradeBand` 1–5）
  - **文法の壁** … CEFR-J（`GrammarStage`: intro1=小学校 / intro2=小6〜中1 / basic1=中1 / basic2=中2 / applied=中2〜中3）
  - **漢字の壁（新規）** … 和訳 `ja` の漢字を「習った学年以内（1学年前まで）」に制限（`KanjiLevelGate` / `KyoikuKanji` 現行配当表1,026字）
  - **学年そのもの** … `GradeLevel`（小1〜中3）＋既存ティア `StarterTier`(a/b/c/d)

## 4段階（既存 GradeLevel / StarterTier を再利用）

| 段階 | 学年 | 語彙 band 上限 | 文法 stage 上限 | 漢字 maxGrade（その段階の最年少＝1学年前） | 題材（許可リスト・加算式） |
|---|---|---|---|---|---|
| **a 入門** | 小1-2 | ≤2 | intro1 | **0（ひらがな主体）** | 自分・家族・動物・食べ物・色・数・あいさつ |
| **b** | 小3-4 | ≤3 | intro2 | **2**（小2まで） | ＋学校・遊び・天気・からだ |
| **c** | 小5-6・中1 | ≤4 | basic1 | **4**（小4まで） | ＋しゅみ・予定・気持ち・自然 |
| **d** | 中2-3 | ≤5 | applied | **6**（教育漢字すべて） | ＋社会のやさしい話題・行事 |

- **漢字 maxGrade は段階の「最年少の学年」で決める**（その段階のどの子でも読めるよう最も厳しい側に寄せる）。例: 段階 b（小3-4）は小3基準で `maxGrade(forSchoolGrade: 3)=2` → 漢字は小2まで。`KanjiLevelGate.maxGrade(forSchoolGrade:)` がこの「1学年前」を返す。
- 題材は加算式（上の段階は下の題材も含む）。題材外・大人語は生成プロンプトとレビューで弾く。

## 生成パイプライン（量産→機械検査→レビュー→少量同梱）

1. **生成（源 = agy / LLM、Tanaka ではない）**：段階ごとに、許可題材・band 上限・文法 stage 上限・**和訳はひらがな多め（漢字 maxGrade 以内）** を明示して子ども向け短文を量産。呼び方は `agy-cli-reliable-invocation` メモに従う。
2. **機械検査（Core・既存＋新規）**：
   - 語彙/文法/トークン/安全/重複 … `SentenceBankBuilder`（curated と同一）
   - **漢字 … `KanjiLevelGate.isWithin(ja, maxGrade:)`（新規）**。超過漢字があれば却下（ひらがな化して再生成）。
3. **レビュー（私 = Claude Code）**：題材の適切さ・訳の自然さ・文法タグの正しさをサンプル目視。怪しい行は捨てる/直す。
4. **同梱**：`sentence_bank.json`（gradeBand+grammar を保持）へ決定論マージ。**10k ダンプはしない・少量ずつ**。アプリは子の `GradeLevel` → targetBand/grammarCeiling で出し分け（＝問題も年齢に合う）。

## アプリ連携（要確認・未実装）

- アプリには既に `GradeLevel`（小1〜中3）と `StarterTier`(a/b/c/d) がある。**子の現在の学年から targetBand / grammarCeiling を導く写像**を1つ用意し、`PuzzleContentBuilder` / `SentenceSelection` に渡せば「問題も年齢別」になる。
- `KanjiLevelGate` は生成時の検査だけでなく、将来 UI 側（既存文の表示可否）にも使える。

## データ出典

- 漢字配当表 = 文科省「学年別漢字配当表」現行版（2017告示・2020施行・教育漢字1,026字）。データ源 `fnshr/kyo-kan kyoiku-kanji-2017.csv`、字数 G1=80/G2=160/G3=200/G4=202/G5=193/G6=191 を検証済み（`KanjiLevelGateTests`）。
