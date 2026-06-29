import Foundation

/// 必須問題（登録語そのものを綴らせる）の Core ロジック。
///
/// 設計（`docs/age-tiered-generation-spec-2026-06-29.md` §3 必須問題の契約）：
/// - 任意の登録語は必ず1つの必須問題に解決する。最後は `directSpelling`（必ず成立）＝**生成例文が0でも必須は回る**。
/// - 必須フレームは**綴り不変**：はめた答えトークンが登録語の綴りと完全一致（活用/複数/大文字化に頼らない）。
/// - 必須は「綴りを自分で打つ形」だけ。並べ替え・選んで答える形は必須に使わない（プールでのみ使う）。
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

    public init(id: String, tokens: [String], answerSlotIndex: Int,
                ja: String, allowedPOS: [String] = []) {
        self.id = id
        self.tokens = tokens
        self.answerSlotIndex = answerSlotIndex
        self.ja = ja
        self.allowedPOS = allowedPOS
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
    /// 直接スペル（登録語をそのまま打つ）。フォールバックの終端＝必ず成立。
    case directSpelling(word: RegisteredWord)
}

public enum CoreProblemResolver {
    /// 登録語を必ず1つの必須問題へ解決する。
    /// 綴り不変フレームに載せられれば載せ、無理なら直接スペル（終端）に落とす。
    public static func resolve(word: RegisteredWord, frames: [SpellingInvariantFrame]) -> CoreProblem {
        if let frame = frames.first(where: { $0.accepts(word) }) {
            return .spellingInvariantFrame(frame: frame, word: word)
        }
        return .directSpelling(word: word)
    }
}
