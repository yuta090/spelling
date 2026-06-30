import SwiftUI
import SpellingSyncCore

/// おぼえる練習（手書きテストの前・タップで選ぶ）。
///
/// 位置づけ（required-first フロー）：
/// - これは“覚えるため”の認識練習。**クリア条件ではない**（間違えても再挑戦でき、
///   最後まで進んだら `onDone` で手書きテストへ）。必須のクリアは手書き満点のまま。
/// - 品詞が分かる語は英文フレーム（`I like ___.` 等）＋空所＋4択。分からない語は
///   意味（和訳）＋綴り4択（文なし）にフォールバック。判定ロジックは Core
///   `MemorizeChoiceBuilder`（決定論）。おとりは `SpellingDistractorGenerator`。
struct MemorizeChoiceView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var speech = SpeechPlayer()

    let words: [SpellingWord]
    let onDone: () -> Void

    @State private var index = 0
    @State private var solved = false
    @State private var wrongPick: String?
    @State private var didFinish = false   // onDone は1回だけ（遅延 advance と「とばす」の競合対策）

    private var current: SpellingWord? {
        words.indices.contains(index) ? words[index] : nil
    }

    var body: some View {
        ZStack {
            PuzzleTheme.bg.ignoresSafeArea()
            if let word = current {
                content(for: word, problem: problem(for: word, at: index))
                    .id(index)   // 語が変わったら状態を作り直す
            } else {
                Color.clear.onAppear(perform: finish)
            }
        }
    }

    // MARK: - 1問の中身

    @ViewBuilder
    private func content(for word: SpellingWord, problem: MemorizeChoiceProblem) -> some View {
        let gloss = WordBank.shared.japanese(for: word.text).map(primaryGloss) ?? word.text

        VStack(spacing: 26) {
            topBar

            Spacer(minLength: 0)

            // 提示（英文フレーム or 意味のみ）
            promptArea(problem: problem, gloss: gloss)

            // きく
            Button {
                speech.speak(word.text, language: "en-US")
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(PuzzleTheme.accent)
                    .padding(18)
                    .background(Circle().fill(PuzzleTheme.hintFill))
                    .overlay(Circle().stroke(PuzzleTheme.tileStroke, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .tapFeedback(bounce: true)

            if solved {
                PuzzleVerdictLabel(isCorrect: true)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("どれが ただしい つづり？")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // 選択肢（2列）
            optionsGrid(problem: problem, word: word)
                .allowsHitTesting(!solved)
                .opacity(solved ? 0.5 : 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: solved)
    }

    // MARK: - 提示エリア

    @ViewBuilder
    private func promptArea(problem: MemorizeChoiceProblem, gloss: String) -> some View {
        if let frame = problem.frame {
            VStack(spacing: 14) {
                sentenceLine(frame: frame, answer: problem.answer)
                Text(frame.ja.replacingOccurrences(of: StarterSpellingFrames.slotToken, with: gloss))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PuzzleTheme.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 10) {
                Text("「\(gloss)」")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(PuzzleTheme.ink)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// 英文を1行で。空所は箱（未正解）か、正解の綴り（正解後）で見せる。
    @ViewBuilder
    private func sentenceLine(frame: MemorizeChoiceProblem.FramePresentation, answer: String) -> some View {
        PuzzleFlowLayout(spacing: 8) {
            ForEach(Array(frame.displayTokens.enumerated()), id: \.offset) { i, token in
                if i == frame.blankIndex {
                    if solved {
                        Text(answer)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(PuzzleTheme.correct)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(PuzzleTheme.hintFill)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PuzzleTheme.slotStroke, lineWidth: 2))
                            .frame(width: 74, height: 38)
                    }
                } else {
                    Text(token)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PuzzleTheme.ink)
                }
            }
        }
    }

    // MARK: - 選択肢

    @ViewBuilder
    private func optionsGrid(problem: MemorizeChoiceProblem, word: SpellingWord) -> some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(problem.options, id: \.self) { opt in
                PuzzleOptionButton(text: opt) { pick(opt, problem: problem, word: word) }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(PuzzleTheme.retry, lineWidth: wrongPick == opt ? 3 : 0)
                    )
            }
        }
    }

    private func pick(_ opt: String, problem: MemorizeChoiceProblem, word: SpellingWord) {
        guard !solved, !didFinish else { return }
        if problem.isCorrect(opt) {
            solved = true
            wrongPick = nil
            let solvedAt = index
            speech.speak(word.text, language: "en-US")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // この語の正解で予約された分だけ進める（「とばす」等で先へ進んでいたら無視）。
                guard !didFinish, solved, index == solvedAt else { return }
                advance()
            }
        } else {
            wrongPick = opt
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func advance() {
        guard !didFinish else { return }
        wrongPick = nil
        solved = false
        if index + 1 >= words.count {
            finish()
        } else {
            index += 1
        }
    }

    /// 手書きへ進む（onDone）を**1回だけ**呼ぶ。遅延 advance と「とばす」の競合を防ぐ。
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onDone()
    }

    // MARK: - 進捗

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(words.indices, id: \.self) { i in
                    Capsule()
                        .fill(i < index ? PuzzleTheme.accent : (i == index ? PuzzleTheme.tileStroke : PuzzleTheme.slotStroke.opacity(0.4)))
                        .frame(height: 6)
                }
            }
            // 「とばす」＝手書きへ進む（おぼえる練習はクリア条件ではない）。
            Button(action: finish) {
                HStack(spacing: 4) {
                    Text("とばす")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 問題生成

    private func problem(for word: SpellingWord, at index: Int) -> MemorizeChoiceProblem {
        let pos = WordBank.shared.partOfSpeech(for: word.text)
        let registered = RegisteredWord(stableID: word.id.uuidString, text: word.text, partOfSpeech: pos)
        return MemorizeChoiceBuilder.make(word: registered, seed: seed(for: word))
    }

    /// 語ごとに安定したシャッフル種（UUID から決める＝同じ語は毎回同じ並び）。
    private func seed(for word: SpellingWord) -> UInt64 {
        var hash: UInt64 = 1469598103934665603   // FNV-1a
        for byte in word.id.uuidString.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return hash
    }

    /// 和訳の先頭の見出し1つ（"赤," や "猫,ネコ" → "赤" / "猫"）。子に短く見せる。
    private func primaryGloss(_ ja: String) -> String {
        let head = ja.split(whereSeparator: { $0 == "," || $0 == "、" || $0 == "；" || $0 == ";" }).first
        let s = head.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ja
        return s.isEmpty ? ja : s
    }
}

/// 必須練習のコンテナ：おぼえる練習（手書きの前）→ 手書きテスト（`SpellingSessionView`）。
///
/// - 新規開始時のみ「おぼえる練習」を先に出す。**途中再開（resumeState あり）は手書きへ直行**
///   （覚え直しを毎回強制しない）。
/// - 必須のクリア条件は手書き満点のまま（おぼえる練習はクリアに数えない）。手書き側の
///   コールバック（進捗保存・完了・テストへ・やり直し・閉じる）はそのまま `SpellingSessionView` へ委譲。
struct PracticeFlowView: View {
    let resumeState: PracticeSessionResumeState?
    let onPracticeProgressChange: (PracticeSessionResumeState?) -> Void
    let onPracticeCompleted: () -> Void
    let onPracticeStartTest: () -> Void
    let onPracticeRetryWords: ([String]) -> Void
    let onRequestClose: (() -> Void)?

    /// セッション開始時の語リストを**固定**する（memorize 中に親が同期で再計算しても、
    /// 出題リストが入れ替わったり空になったりしないよう、SpellingSessionView と同じくスナップショット）。
    @State private var words: [SpellingWord]
    @State private var phase: Phase

    private enum Phase { case memorize, write }

    init(words: [SpellingWord],
         resumeState: PracticeSessionResumeState?,
         onPracticeProgressChange: @escaping (PracticeSessionResumeState?) -> Void,
         onPracticeCompleted: @escaping () -> Void,
         onPracticeStartTest: @escaping () -> Void,
         onPracticeRetryWords: @escaping ([String]) -> Void,
         onRequestClose: (() -> Void)?) {
        _words = State(initialValue: words)
        self.resumeState = resumeState
        self.onPracticeProgressChange = onPracticeProgressChange
        self.onPracticeCompleted = onPracticeCompleted
        self.onPracticeStartTest = onPracticeStartTest
        self.onPracticeRetryWords = onPracticeRetryWords
        self.onRequestClose = onRequestClose
        _phase = State(initialValue: resumeState == nil ? .memorize : .write)
    }

    var body: some View {
        switch phase {
        case .memorize:
            MemorizeChoiceView(words: words) {
                withAnimation { phase = .write }
            }
        case .write:
            SpellingSessionView(
                mode: .practice,
                words: words,
                resumeState: resumeState,
                onPracticeProgressChange: onPracticeProgressChange,
                onPracticeCompleted: onPracticeCompleted,
                onPracticeStartTest: onPracticeStartTest,
                onPracticeRetryWords: onPracticeRetryWords,
                onRequestClose: onRequestClose
            )
        }
    }
}
