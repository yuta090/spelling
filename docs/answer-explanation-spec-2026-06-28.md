# 仕様書：答え合わせ後の説明 共通基盤（AnswerExplanation）

Status: **v2・実装へ渡す版**（2026-06-28、codex Plan Review 反映）。
関連: [learning-loop-design-2026-06-28.md](learning-loop-design-2026-06-28.md)。
依存コード（main 済み）: `Sources/SpellingSyncCore/SentenceExercise.swift`・`GrammarLevel.swift`・`iPadPrototype/WordOrderingView.swift`・`iPadPrototype/Models.swift`(`GradeDecision`)。

## 0. フェーズ分割（重要・codex反映）
**単語側（おぼえかた/かたまり）は `word_chunks.csv` と `MorphemeRow`/`MorphemeHint` を要し、これは別ブランチ `proto/chunk-hint-20260627-db2f` にしか無い。** よって：
- **Phase 1（今すぐ・main だけで完結）＝ 文法クイズの答え合わせ**：`AnswerExplanation` モデル＋`SentenceFeedback`＋共有カード＋`WordOrderingView` 配線。
- **Phase 2（chunk ブランチ合流後）＝ 単語側**：`WordSpellingFeedback`/`WordHelper`/`composeChunkSentence`。同じモデル・同じカードを使う。
- 渡す相手が main で作るなら **Phase 1 だけ着手可**。Phase 2 は chunk ブランチ取り込み後。

## 1. 目的
答え合わせ/間違い後の「説明」を、つづり練習・文法クイズ・今後のクイズで**同じモデル・同じカード**に統一。
今の文法クイズは `explanationJa` と「あとNこ」だけで、**正解の文を見せていない**（`WordOrderingView.swift` の feedback 部）。これを直し、全形式で再利用できる土台にする。
※ 本モデル `AnswerExplanation` ＝ プロダクト規約でいう **「MissExplanation 共通」** と同一物（名称のみ差）。

## 1.5 解説文づくりルール（プロダクト確定規約・最優先）
**大前提：これはテストの採点コメントではなく“ゲームの中のやさしいヒント”。** 「間違えてもOK、もう一回やろう」と思える前向きさが最優先。子に専門用語・級・CEFR・点数は見せない。
共通ルール（文法・つづり両方）：
1. **短く**：body は原則 1〜2文。
2. **やさしい言葉**：「be動詞」「過去形」程度はOK。学者語・難解語はNG。
3. **例で示す**：可能なら超短い例。例語・例文もその学年の語彙内。
4. **1ポイント1メッセージ**：今回のミスに効く一点だけ。枝葉を盛らない。
5. **前向きな言い回し**：「ちがう」より「こうするとできるよ」。責めない。
6. **解説でも学年の壁を守る**：説明文の中で対象学年より難しい語・文法を出さない。
7. **AI生成は必ず `approved=0`**：人が1件ずつ確認してOKした行だけ出す。
8. **ウソを書かない／断定しすぎない**：自信が無いものは書かない・空欄にする。

## 2. 純粋モデル（SpellingSyncCore・新ファイル `AnswerExplanation.swift`）
```swift
/// 答え合わせ後／ヒント表示の共通モデル。UI非依存・I/Oなし・Sendable・Equatable。
public struct AnswerExplanation: Equatable, Sendable {
    public var wasCorrect: Bool?     // nil = 正誤文脈なし（閲覧/タップの純情報）
    public var headline: String?     // 文法名 / "おぼえかた" / nil
    public var correctText: String?  // 正しい文・正しいつづり（答え合わせ後のみ）
    public var meaningJa: String?    // 和訳・意味
    public var detail: String?       // なぜ/どう。**不正解 or on-demand のみ**（正解時は出さない）
    public var chips: [String]       // なかま語・かたまり（呼び出し側が決定論順で渡す。空可）
    public init(wasCorrect: Bool? = nil, headline: String? = nil, correctText: String? = nil,
                meaningJa: String? = nil, detail: String? = nil, chips: [String] = [])
}
```

## 3. 表示ルール（カードのレンダリング契約）
| 状態 | correctText | meaningJa | detail | chips |
|---|---|---|---|---|
| `true`（正解）| 出す（「できたね！」）| 出す | **出さない** | 任意 |
| `false`（不正解）| 出す（「せいかいは…」）| 出す | **出す** | 出す |
| `nil`（閲覧/タップ）| 任意 | 出す | on-demand | 出す |
- 正解文は答え合わせ後のみ。子に専門用語なし。やさしい日本語。
- レイアウト大前提：単語/文が主役で大きく、解説・意味は控えめ（寸法は別途デザイン回・実機スクショ）。

## 4. Phase 1 — 文法クイズ用ビルダー（純関数・決定論）
```swift
public enum SentenceFeedback {
    /// 並べ替え等の答え合わせ。submitted は将来の差分表示用に受け取る（v1では未使用でも引数に残す）。
    public static func make(item: SentenceItem, submitted: [String], grade: OrderingGrade) -> AnswerExplanation
}
```
ルール（型は実コードに一致：`SentenceItem.tokens/ja/grammar`、`OrderingGrade.isCorrect`、`GrammarPoint.titleJa/explanationJa`）：
- `wasCorrect = grade.isCorrect`
- `correctText = item.tokens.joined(separator: " ")`（タイル列＝子が並べた対象と一致させる。`item.en` ではなく tokens）
- `meaningJa = item.ja`
- `headline = item.grammar?.titleJa`（**`grammar` は nil 可** → headline/detail も nil でよい＝文法タグ無しの文）
- `detail = grade.isCorrect ? nil : item.grammar?.explanationJa`（既存の手書き固定解説を再利用。生成しない）
- `chips = []`（Phase 1 では空）

### 4.1 `WordOrderingView` 配線（main の既存UIを編集・最小diff・要レビュー）
現状：`check()` で `grade` を立て、不正解時 `explanationCard(grammar)`＋「あとNこ」を表示。**正解文は出していない／置いたタイルは grade 後ロックされ残る**。
最小変更：
1. `check()` 後に `let exp = SentenceFeedback.make(item:submitted:placed.map(\.text), grade:)` を作る。
2. feedback 部の `explanationCard(grammar)` を **`AnswerExplanationCard(exp)` に置換**（正解文・意味・解説を1枚で）。
3. **置いた（間違った）タイル列はそのまま残す**（リセットしない）。その下に「せいかいは … 」として `correctText` を別行で表示。タイルの差分色付け（位置一致で緑/灰）は **任意・v1スコープ外**（やるなら `grade.correctPositions` ではなく submitted vs item.tokens の位置比較で）。
4. 既存の `unknownWordChooser`（しらない ことば→復習登録）は**温存**。
- 別エージェント作業領域のため、変更は上記に限定。`SentenceExercise.swift`/`GrammarLevel.swift` は**触らない**。

## 5. Phase 2 — 単語側ビルダー（chunk ブランチ合流後）
`MorphemeRow` を本仕様で定義（chunk ブランチの `word_chunks.csv` 1行に対応）：
```swift
public struct MorphemeRow: Equatable, Sendable {
    public var word: String
    public var parts: [String]    // split をかたまりに分けた列（順序＝表示順）
    public var senses: [String]   // parts と同数。意味なしは ""（接頭辞 in/re/un 等は ""）
    public var family: String?    // なかまキー（無ければ nil）
    public init(word: String, parts: [String], senses: [String], family: String?)
}
```
意味・なかまは**純粋層では引けない**ので呼び出し側（アプリ）が解決して渡す：
```swift
public enum WordSpellingFeedback {
    /// つづり練習の答え合わせ。meaningJa と relatives は app 層が WordBank/辞書から解決して渡す。
    public static func make(word: String, meaningJa: String?, row: MorphemeRow,
                            relatives: [String], wasCorrect: Bool) -> AnswerExplanation
}
public enum WordHelper {
    /// カード閲覧・タイルタップの純情報（正誤なし）。
    public static func make(word: String, meaningJa: String?, row: MorphemeRow,
                            relatives: [String]) -> AnswerExplanation
}
```
ルール：
- `correctText = word`（正しいつづり）／`meaningJa` は引数そのまま／`headline = "おぼえかた"`。
- `WordSpellingFeedback`：`detail = wasCorrect ? nil : composeChunkSentence(row, relatives)`、`chips = relatives`。
- `WordHelper`：`wasCorrect = nil`、`detail = composeChunkSentence(row, relatives)`、`chips = relatives`。

### 5.1 `composeChunkSentence`（決定論・AI不使用）
入力 `row` と `relatives`（**呼び出し側で CSV 出現順に整列・最大3件にcap 済み**）から短文を組む：
- 意味付きかたまりが1つ以上あるとき：「**{chunk} は『{sense}』**。{relatives を「/」で連結} にも 出てくるよ」。
  （意味付き複数なら最初の1つを使う。並びは parts 順＝決定論）
- 意味なし（接尾辞 ment 等）のみ：「**{parts を「・」連結}** の かたまり。**{family}** は {relatives} にも 出てくるよ」。
- `relatives` が空：なかま節を省く（「{chunk} は『{sense}』。」だけ／family節なし）。
- `family == nil` かつ意味なし：`detail = nil`（出すものが無ければ非表示）。
- `Set` 反復・サンプリング・乱数は禁止。全て引数順で決定。

### 5.2 つづり正誤 → wasCorrect 写像（app 層で行い Bool を渡す）
実アプリの `GradeDecision`（`Models.swift`）：`autoCorrect / autoIncorrect / needsReview / rewrite / timeExpired`。
- `autoCorrect` → `true`
- `autoIncorrect` / `timeExpired` → `false`
- `needsReview` / `rewrite` → `false`（助けを出す側に倒す）
純粋層は `Bool` を受け取るだけ。写像はアプリ側の責務。

## 6. 共有カードUI（新ファイル `iPadPrototype/AnswerExplanationCard.swift`）
- 入力 `AnswerExplanation` 1つ。§3 の表に従う。`detail==nil` の節は描画しない。
- つづり練習・`WordOrderingView`・今後のクイズが同じカードを使う。
- **新規 .swift はXcode個別管理**：`SpellingTrainer.xcodeproj/project.pbxproj` の app sources に登録が必要（PBXFileReference＋PBXBuildFile＋group＋Sources phase）。同期グループではない。

## 7. ファイル / テスト一覧（cold start 用）
新規：
- `Sources/SpellingSyncCore/AnswerExplanation.swift`（モデル＋Phase1 `SentenceFeedback`。Phase2で `MorphemeRow`/`WordSpellingFeedback`/`WordHelper`/`composeChunkSentence` 追記）
- `Tests/SpellingSyncCoreTests/AnswerExplanationTests.swift`
- `iPadPrototype/AnswerExplanationCard.swift`（＋pbxproj登録）
編集：
- `iPadPrototype/WordOrderingView.swift`（§4.1 の最小diffのみ）
テスト（TDD・`swift test` 緑・決定論）：
1. `SentenceFeedback`：正解→detail=nil・correctText=tokens連結・meaningJa=item.ja。
2. 不正解→detail=explanationJa・headline=titleJa。
3. `grammar==nil` の不正解→headline=nil・detail=nil・correctText は出る。
4. Phase2 `WordSpellingFeedback`：正解→detail=nil／不正解→detail=テンプレ・chips=relatives。
5. `composeChunkSentence`：意味あり（spect=みる）／意味なし（ment）で文型出し分け・relatives空で壊れない・family=nil意味なしでnil。
6. エッジ：tokens空・1語・relatives空・row.parts と senses 数不一致は呼び出し前提として弾く（または安全に nil）。
- 公開APIは `public`＋`public init`。

## 8. スコープ外（将来）
`WordUsageLinker.eligibleSentences`（単語→文の先触れ）、`minimumLearnerStage`（GrammarStage 流用ゲート）、SRS `(word, skill)`、タイル差分の色付け、デザイン最終寸法、AI生成、小学生表示。
これらは**継ぎ目だけ意識**し本仕様では実装しない。
