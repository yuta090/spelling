import Foundation

/// 文づくり（文法練習）の純粋ロジック。
/// 設計: docs/sentence-builder-design-2026-06-27.md
///
/// 着手スコープ: **並べ替え（word ordering）** のみ。他形式は `ExerciseFormat` に型だけ用意し、
/// ジェネレータ/グレーダは後続で足す（同じ `SentenceItem` を素に使い回せる器にする）。

// MARK: - 共通モデル

/// 出題形式のカタログ。今は wordOrdering のみ実装済み、他はプレースホルダ。
public enum ExerciseFormat: String, Sendable, CaseIterable, Codable {
    /// 並べ替え：和訳を見て単語タイルを正しい順に並べる（決定的採点）。
    case wordOrdering
    /// 穴埋め（選択肢から選ぶ／決定的採点）。
    case clozeChoice
    /// 穴埋め（空所を手書き／AI・OCR採点）。
    case clozeHandwriting
    /// 英作文「言いたいことを文に」（全文を手書き／AI VLM採点）。
    case composition
    /// 3択・正誤（クイック確認／決定的採点）。
    case multipleChoice

    /// 採点が端末内で完結する（AIを使わない）形式か。
    public var isDeterministicallyGradable: Bool {
        switch self {
        case .wordOrdering, .clozeChoice, .multipleChoice: return true
        case .clozeHandwriting, .composition: return false
        }
    }
}

/// 文バンクの1文（学年タグ・トークン済み）。出題はここから生成する。
/// `tokens` は正解の語順そのもの（並べ替えの正解列）。
/// `gradeBand` は内容語の最大 NGSL バンド（1...5）＝**語彙の壁**。`contentLemmas` は判定に使った内容語。
/// `grammar` は文の**文法タグ**（1つ）＝**文法の壁**。nil は文法制約なし（暫定文・機能語のみ等）。
public struct SentenceItem: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var en: String
    public var ja: String
    public var tokens: [String]
    public var gradeBand: Int
    public var contentLemmas: [String]
    public var grammar: GrammarPoint?
    /// 安定ID（教材＝authoring 由来）。英文を直して表層 `id`(UUIDv5) が変わっても切れない履歴の鍵。
    /// 任意（既存同梱物には無い → nil）。`Codable` は optional を encodeIfPresent するため nil は出力から省かれる。
    public var sourceID: String?
    /// ジャンル（useful/humor/story）。プールの絞り込み（humor トグル）に使う。
    /// 任意（既存同梱物には無い → nil＝useful 相当に扱う）。nil は出力から省かれる。
    public var genre: Genre?

    public init(
        id: UUID = UUID(),
        en: String,
        ja: String,
        tokens: [String],
        gradeBand: Int,
        contentLemmas: [String] = [],
        grammar: GrammarPoint? = nil,
        sourceID: String? = nil,
        genre: Genre? = nil
    ) {
        self.id = id
        self.en = en
        self.ja = ja
        self.tokens = tokens
        self.gradeBand = gradeBand
        self.contentLemmas = contentLemmas
        self.grammar = grammar
        self.sourceID = sourceID
        self.genre = genre
    }

    /// 並べ替え問題として成立するか（少なくとも2種類の異なるトークンが要る）。
    /// 全同一語・単語1個・空はシャッフルしても正解順から崩せないため不成立。
    public var isScramblable: Bool {
        Set(tokens).count >= 2
    }

    /// この文の文法段階（タグから導出）。タグ無しは nil＝文法の壁にかからない。
    public var grammarStage: GrammarStage? {
        grammar?.stage
    }
}

// MARK: - 出題範囲（学年の壁＝絶対）

/// 出題範囲の判定。**ハード制約**：内容語が対象学年（対象バンド）以内であること。
/// `SentenceItem.gradeBand` はビルド時前処理で「全内容語が leveled かつ band 以内」を保証して付与されている前提。
public enum SentenceSelection {
    /// 対象バンド以内か（`gradeBand <= targetBand`）。
    public static func isEligible(_ item: SentenceItem, targetBand: Int) -> Bool {
        item.gradeBand <= targetBand
    }

    /// 対象バンド以内の文だけを残す（順序は保持）。
    public static func eligible(_ items: [SentenceItem], targetBand: Int) -> [SentenceItem] {
        items.filter { isEligible($0, targetBand: targetBand) }
    }
}

// MARK: - 決定的シャッフル（テスト可能・Date/Random 非依存）

/// 種からの決定的シャッフル（SplitMix64 + Fisher–Yates）。
/// `Math.random`/`Date()` を使わずロジックを決定論に保つ（同期コアの方針）。
public enum SeededShuffle {
    /// 与えた配列を種で決定的に並べ替える。
    public static func shuffle<T>(_ items: [T], seed: UInt64) -> [T] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        var a = items
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            a.swapAt(i, j)
        }
        return a
    }
}

// MARK: - 並べ替え（word ordering）

/// 並べ替え1問のタイル。重複語を区別するため安定 `id` を持つ。
public struct OrderingTile: Equatable, Sendable, Codable, Identifiable {
    public var id: Int
    public var text: String
    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// 並べ替え問題（提示＋正解）。
public struct WordOrderingExercise: Equatable, Sendable {
    public var itemID: UUID
    /// 子に見せる和訳プロンプト。
    public var prompt: String
    /// シャッフル済みタイル列。
    public var scrambledTiles: [OrderingTile]
    /// 正解の語順。
    public var answer: [String]
}

/// 並べ替え問題のジェネレータ。
public enum WordOrderingGenerator {
    /// 並べ替え問題を生成する。並べ替え不能（`isScramblable == false`）なら `nil`。
    /// → 出題側（SessionComposer）は scramblable な文だけを word ordering に回す。
    public static func make(from item: SentenceItem, seed: UInt64) -> WordOrderingExercise? {
        // 全同一語・単語1個・空は、どう並べても正解順から崩せないため問題にならない。
        guard item.isScramblable else { return nil }

        // タイルは元の語順に安定 id を振る（重複語も id で区別できる）。
        let tiles = item.tokens.enumerated().map { OrderingTile(id: $0.offset, text: $0.element) }

        // 「最初から正解順」を避ける（並べ替えとして成立させる）。
        // 種を変えながら数回試し、それでも揃う稀なケースは左1回転で崩す。
        // isScramblable な前提なら、左1回転は必ず正解順と異なる並びを与える。
        var shuffled = SeededShuffle.shuffle(tiles, seed: seed)
        var attempt: UInt64 = 1
        while shuffled.map(\.text) == item.tokens, attempt <= 8 {
            shuffled = SeededShuffle.shuffle(tiles, seed: seed &+ attempt)
            attempt += 1
        }
        if shuffled.map(\.text) == item.tokens {
            shuffled = Array(shuffled[1...] + shuffled[..<1])
        }

        return WordOrderingExercise(
            itemID: item.id,
            prompt: item.ja,
            scrambledTiles: shuffled,
            answer: item.tokens
        )
    }
}

/// 並べ替え1問の採点結果。`correctPositions`/`total` で部分点（位置一致数）。
public struct OrderingGrade: Equatable, Sendable {
    public var isCorrect: Bool
    public var correctPositions: Int
    public var total: Int
}

/// 並べ替えの決定的グレーダ（位置一致による部分点つき）。
public enum WordOrderingGrader {
    public static func grade(submitted: [String], answer: [String]) -> OrderingGrade {
        // 余剰トークン（過長な解答）でも満点にならないよう、分母は長い方を採用する。
        let total = max(answer.count, submitted.count)
        let correctPositions = zip(submitted, answer).reduce(into: 0) { acc, pair in
            if pair.0 == pair.1 { acc += 1 }
        }
        let isCorrect = submitted == answer
        return OrderingGrade(isCorrect: isCorrect, correctPositions: correctPositions, total: total)
    }
}
