import Foundation

/// 必須問題（登録語そのものを綴らせる）の Core ロジック。
///
/// 設計（`docs/age-tiered-generation-spec-2026-06-29.md` §3 必須問題の契約）：
/// - 任意の登録語は必ず1つの必須問題に解決する。最後は `directSpelling`（必ず成立）＝**生成例文が0でも必須は回る**。
/// - 必須フレームは**綴り不変**：はめた答えトークンが登録語の綴りと完全一致（活用/複数/大文字化に頼らない）。
/// - ラダー＝フレーム→単語リスニング→直接スペル（§3.1）。並べ替えは必須に使わない。
///   単語リスニングは選択式なので、§3.3「綴りを自分で出す形」を厳格運用するなら `allowWordListening: false` で飛ばせる。
/// - アプリの `SpellingWord` を Core に持ち込まない（`RegisteredWord` で受ける）。

// MARK: - 登録語の Core スナップショット

/// 必須問題が要る登録語の最小表現。`stableID` はアプリ側で安定化して渡す前提
/// （アプリの単語IDが未安定なら、署名/完了状態の前に安定化する＝別タスク）。
public struct RegisteredWord: Equatable, Sendable {
    public var stableID: String
    /// 答えの綴り（exact）。必須はこの文字列そのものを打たせる。
    public var text: String
    /// 品詞（任意）。フレームの `allowedPOS` と突き合わせて「無理にはめない」判定に使う。
    public var partOfSpeech: String?

    public init(stableID: String, text: String, partOfSpeech: String? = nil) {
        self.stableID = stableID
        self.text = text
        self.partOfSpeech = partOfSpeech
    }
}

// MARK: - 綴り不変フレーム（乗り物）

/// 登録語を綴り変えずに載せる“乗り物”フレーム。答えスロットの位置を**明示**で持つ
/// （描画後のテキストを後から走査して答えを推測しない＝壊れにくい）。
public struct SpellingInvariantFrame: Equatable, Sendable {
    public var id: String
    /// 語順トークン。`answerSlotIndex` の位置に登録語の綴りをそのまま差し込む。
    public var tokens: [String]
    /// 答え（登録語）が入るトークン位置。
    public var answerSlotIndex: Int
    public var ja: String
    /// このスロットに載せてよい品詞（空＝制約なし）。
    public var allowedPOS: [String]
    /// フレーム自身（＝生成物）の語彙band。tier 制約の判定に使う（任意・nil＝制約なし）。
    /// 登録語は tier 例外なので**ここには含めない**（スロットを除いた“乗り物”側の band）。
    public var gradeBand: Int?
    /// フレーム自身の文法タグ。tier 天井の判定に使う（任意・nil＝制約なし）。
    public var grammar: GrammarPoint?

    public init(id: String, tokens: [String], answerSlotIndex: Int,
                ja: String, allowedPOS: [String] = [],
                gradeBand: Int? = nil, grammar: GrammarPoint? = nil) {
        self.id = id
        self.tokens = tokens
        self.answerSlotIndex = answerSlotIndex
        self.ja = ja
        self.allowedPOS = allowedPOS
        self.gradeBand = gradeBand
        self.grammar = grammar
    }

    /// スロット位置がトークン範囲内か（壊れたフレームを必須に使わない）。
    public var isWellFormed: Bool {
        tokens.indices.contains(answerSlotIndex)
    }

    /// 登録語をスロットへ**そのまま**差し込む（綴り不変＝変換を一切しない）。
    /// 返り値の `tokens[answerIndex]` は常に `word.text` と完全一致する。
    /// 壊れたフレーム（スロット範囲外）でも**クラッシュさせない**＝元トークンをそのまま返す（防御）。
    public func filled(with word: RegisteredWord) -> (tokens: [String], answerIndex: Int) {
        guard isWellFormed else { return (tokens, answerSlotIndex) }
        var t = tokens
        t[answerSlotIndex] = word.text
        return (t, answerSlotIndex)
    }

    /// この語をこのフレームに載せてよいか（品詞が合うか）。
    func accepts(_ word: RegisteredWord) -> Bool {
        guard isWellFormed else { return false }
        guard !allowedPOS.isEmpty else { return true }      // 制約なし＝載せてよい
        guard let pos = word.partOfSpeech else { return false } // 制約あるのに品詞不明＝無理にはめない
        return allowedPOS.contains(pos)
    }
}

// MARK: - 必須問題

/// 解決した必須問題。`directSpelling` は終端（常に成立）。
public enum CoreProblem: Equatable, Sendable {
    /// 綴り不変フレームに載せて、答えスロットを打たせる。
    case spellingInvariantFrame(frame: SpellingInvariantFrame, word: RegisteredWord)
    /// 単語リスニング（音→綴り選択）。中央 rung：綴り不変フレームに載らないが、
    /// 音の似たおとりがある語に使う（§3.1）。答えは登録語の綴りそのもの。
    case wordListening(word: RegisteredWord, distractors: [String])
    /// 直接スペル（登録語をそのまま打つ）。フォールバックの終端＝必ず成立。
    case directSpelling(word: RegisteredWord)
}

public enum CoreProblemResolver {
    /// 登録語を必ず1つの必須問題へ解決する（§3.1 のラダー）：
    /// 1. **綴り不変フレーム**に載せられれば載せる（tier 制約は `policy` 指定時のみフレームに効く・登録語は例外）。
    /// 2. 載らなくても**音の似たおとり**があれば**単語リスニング**（`allowWordListening` で無効化可）。
    /// 3. それも無ければ**直接スペル**（終端・必ず成立）。
    ///
    /// `allowWordListening` の既定は true（§3.1 のラダー通り）。§3.3「必須は綴りを自分で出す形」を
    /// 厳格運用したいアプリは false を渡せば、選択式の単語リスニングを飛ばして直接スペルへ落とせる。
    public static func resolve(word: RegisteredWord,
                               frames: [SpellingInvariantFrame],
                               confusables: [ConfusableEntry] = [],
                               policy: ContentPolicy? = nil,
                               allowWordListening: Bool = true) -> CoreProblem {
        // 1. 綴り不変フレーム（品詞が合う・壊れていない・tier 制約内）。
        if let frame = frames.first(where: { $0.accepts(word) && frameAdmissible($0, under: policy) }) {
            return .spellingInvariantFrame(frame: frame, word: word)
        }
        // 2. 単語リスニング（承認済みおとりがある語のみ）。
        if allowWordListening {
            let distractors = ConfusablesSound.distractors(for: word.text, in: confusables)
            if !distractors.isEmpty {
                return .wordListening(word: word, distractors: distractors)
            }
        }
        // 3. 直接スペル（終端）。
        return .directSpelling(word: word)
    }

    /// フレーム（＝生成物）が子の tier 制約内か。`policy` 無しなら常に可（後方互換）。
    /// 文法天井・語彙band・和訳の漢字を、フレーム自身の宣言で判定する（§3.5＝生成文/和訳に効く）。
    /// 登録語は tier 例外なので**フレーム側の band/grammar には含めない**（呼び出し側の責務）。
    private static func frameAdmissible(_ frame: SpellingInvariantFrame,
                                        under policy: ContentPolicy?) -> Bool {
        guard let policy else { return true }
        if let g = frame.grammar, g.stage > policy.grammarCeiling { return false }
        if let b = frame.gradeBand, b > policy.targetBand { return false }
        // 和訳の漢字も tier 内に（既存プール絞り込みと同じ KanjiLevelGate）。
        guard KanjiLevelGate.isWithin(frame.ja, maxGrade: policy.maxKanjiGrade) else { return false }
        return true
    }
}
