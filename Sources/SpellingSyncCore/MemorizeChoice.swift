import Foundation

/// おぼえる練習（手書きの前・タップで選ぶ）1問を組む純ロジック。
///
/// 位置づけ（required-first フロー）：
/// - 必須のクリアは**手書き満点テスト**のまま。これはその前段＝“覚えるため”の認識練習で、
///   正しい綴りを選ばせる（多肢選択そのものはクリア条件にしない）。
/// - 品詞が分かり英文フレームに載る語は **文＋空所＋4択**（`I like ___.` 等）で出す。
///   載らない語（品詞不明・対応フレーム無し）は **意味＋綴り4択（文なし）** にフォールバック。
/// - おとりは `SpellingDistractorGenerator`（似た綴り／かたちちがい／微妙なミス）。
///   選択肢は決定論シャッフル（`seed`）。正解の綴りは不変（フレームに載せても変えない）。
public struct MemorizeChoiceProblem: Equatable, Sendable {
    /// 正解（登録語の綴り・exact）。
    public var answer: String
    /// 選択肢（正解＋おとり・決定論シャッフル済み・ユニーク）。
    public var options: [String]
    /// 英文フレーム提示（nil＝意味のみ＝文なし）。
    public var frame: FramePresentation?

    public init(answer: String, options: [String], frame: FramePresentation?) {
        self.answer = answer
        self.options = options
        self.frame = frame
    }

    /// 英文フレームの提示情報。空所は埋めず `slotToken` のまま見せ、子が綴りを選ぶ。
    public struct FramePresentation: Equatable, Sendable {
        /// 表示トークン列（空所位置は `StarterSpellingFrames.slotToken`）。
        public var displayTokens: [String]
        /// 空所（答え）の位置。
        public var blankIndex: Int
        /// 和訳テンプレ（語の意味が入る位置は `slotToken`）。UI で gloss を差し込む想定。
        public var ja: String

        public init(displayTokens: [String], blankIndex: Int, ja: String) {
            self.displayTokens = displayTokens
            self.blankIndex = blankIndex
            self.ja = ja
        }
    }

    public var isFramed: Bool { frame != nil }

    /// 選んだ綴りが正解か（決定的）。
    public func isCorrect(_ selected: String) -> Bool { selected == answer }
}

public enum MemorizeChoiceBuilder {

    /// 登録語1つから「おぼえる練習」の1問を組む（常に成立＝nil を返さない）。
    /// - frames: 載せる候補フレーム（既定＝スターターセット）。
    /// - optionCount: 選択肢の最大数（正解込み・最低2を目指すがおとりが無ければ少なくなる）。
    /// - seed: 選択肢シャッフルの種（同じ入力＋同じ seed → 同じ出力）。
    public static func make(word: RegisteredWord,
                            frames: [SpellingInvariantFrame] = StarterSpellingFrames.all,
                            optionCount: Int = 4,
                            seed: UInt64) -> MemorizeChoiceProblem {
        // おとり（正解は除外済み・ユニーク）。フレーム有無に関わらず選択肢は同じ。
        let cap = max(2, optionCount)
        let distractors = SpellingDistractorGenerator
            .make(for: word.text, partOfSpeech: word.partOfSpeech, limit: cap - 1)
            .map { $0.text }

        var options = [word.text]
        for d in distractors where options.count < cap && !options.contains(d) {
            options.append(d)
        }
        options = SeededShuffle.shuffle(options, seed: seed)

        // 英文フレームに載るか（品詞が合う語のみ）。音リスニングは使わない＝allowWordListening:false。
        let problem = CoreProblemResolver.resolve(word: word, frames: frames, allowWordListening: false)
        if case let .spellingInvariantFrame(frame, _) = problem {
            let presentation = MemorizeChoiceProblem.FramePresentation(
                displayTokens: frame.tokens,          // 空所は slotToken のまま（埋めない）
                blankIndex: frame.answerSlotIndex,
                ja: frame.ja
            )
            return MemorizeChoiceProblem(answer: word.text, options: options, frame: presentation)
        }
        // 載らない（品詞不明・対応フレーム無し）→ 意味＋4択。
        return MemorizeChoiceProblem(answer: word.text, options: options, frame: nil)
    }
}
