import SwiftUI
import SpellingSyncCore

// ことばパズル：1つのメニューから複数形式をランダム出題する統一セッション。
// 形式の並び（飽きさせない=連続同形式なし）は SpellingSyncCore の PuzzleFormatScheduler に委譲。
// 各形式の出題生成・採点は既存の Generator/Grader を再利用し、見た目は PuzzleKit で共通化する。
// 設計: docs/kotoba-puzzle-spec-2026-06-28.md
//
// v1 のコンテンツは各試遊画面にあったデモ文/語を1つのプールに統合したもの。
// 本物の文バンク/パーソナライズ例文への接続は次フェーズ（PuzzleContent を差し替えるだけ）。

// MARK: - 出題コンテンツ（v1: デモプール）

/// 文ベース形式（ぶんづくり・あなうめ・きいてあなうめ）に使う1文。
struct PuzzleSentenceSample {
    let item: SentenceItem
    /// 穴埋めの空所位置（あなうめ系で使用）。
    let blankIndex: Int
    /// あなうめ（選択）のおとり。きいてあなうめは confusables から供給するので未使用。
    let distractors: [String]
}

enum PuzzleContent {
    /// 文ベース形式（ぶんづくり・あなうめ）のプール。並べ替え可能で、穴埋め位置とおとりを持つ。
    static func sentences() -> [PuzzleSentenceSample] {
        func s(_ en: String, _ ja: String, blank: Int, _ distractors: [String], _ g: GrammarPoint) -> PuzzleSentenceSample {
            PuzzleSentenceSample(
                item: SentenceItem(en: en, ja: ja,
                                   tokens: en.split(separator: " ").map(String.init),
                                   gradeBand: 1, grammar: g),
                blankIndex: blank,
                distractors: distractors)
        }
        return [
            s("I like apples", "わたしは りんごが すき", blank: 1, ["likes", "liked", "want"], .presentSimple),
            s("She is happy", "かのじょは うれしい", blank: 1, ["am", "are", "be"], .beVerb),
            s("We played soccer", "サッカーを した", blank: 1, ["play", "plays", "playing"], .pastSimple),
            s("He can swim", "かれは およげる", blank: 1, ["is", "does", "will"], .canModal),
            s("We go to school", "がっこうへ いく", blank: 1, ["goes", "went", "going"], .presentSimple),
            s("This bag is bigger", "この かばんは もっと 大きい", blank: 3, ["big", "biggest", "more"], .comparativeEr)
        ]
    }

    /// きいてあなうめ専用のプール。**空所語は音の近いおとりが登録済みの語**にする
    /// （未登録だと ListeningClozeGenerator が nil を返し出題できないため）。おとりは confusables から供給。
    static func listeningSentences() -> [PuzzleSentenceSample] {
        func s(_ en: String, _ ja: String, blank: Int) -> PuzzleSentenceSample {
            PuzzleSentenceSample(
                item: SentenceItem(en: en, ja: ja,
                                   tokens: en.split(separator: " ").map(String.init),
                                   gradeBand: 1),
                blankIndex: blank,
                distractors: [])
        }
        return [
            s("I can see the sea", "うみが みえる", blank: 4),
            s("I eat rice", "ごはんを たべる", blank: 2),
            s("Turn right here", "ここで みぎに まがる", blank: 1),
            s("Take a bath", "おふろに はいる", blank: 2),
            s("Go back home", "おうちに かえる", blank: 1)
        ]
    }

    /// 単語リスニングで読み上げる語（おとりは ConfusablesBundle が供給）。
    static let words = ["right", "rice", "berry", "base", "sea", "back", "bath"]
}

// MARK: - セッション本体

struct PuzzleSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()

    private let sentences: [PuzzleSentenceSample]
    private let listeningSentences: [PuzzleSentenceSample]
    private let words: [String]
    private let entries: [ConfusableEntry]
    private let length: Int

    /// 音を出すか（冒頭ゲートで決める）。nil = 未選択。
    @State private var soundOn: Bool?
    @State private var stepIndex = 0
    @State private var finished = false
    /// このセッションの並び・出題を決めるシード。毎回ちがう並びにするため起動時に乱数で決める
    /// （`seed` を明示注入すればテスト/プレビューで決定論にできる）。「もういちど」で振り直す。
    @State private var sessionSeed: UInt64

    init(sentences: [PuzzleSentenceSample] = PuzzleContent.sentences(),
         listeningSentences: [PuzzleSentenceSample] = PuzzleContent.listeningSentences(),
         words: [String] = PuzzleContent.words,
         entries: [ConfusableEntry] = ConfusablesBundle.entries,
         length: Int = 12,
         seed: UInt64? = nil) {
        self.sentences = sentences
        self.listeningSentences = listeningSentences
        self.words = words
        self.entries = entries
        self.length = length
        _sessionSeed = State(initialValue: seed ?? UInt64.random(in: .min ... .max))
    }

    /// 音設定に応じた出題プール（おとなしなら音必須の形式を外す）。
    /// さらに、その形式に出せるコンテンツが無ければプールから外す（空出題で詰まらせない）。
    private var pool: [PuzzleFormat] {
        var all = PuzzleFormat.playablePool
        if soundOn != true { all = all.filter { !$0.requiresAudio } }
        return all.filter { hasContent(for: $0) }
    }

    /// その形式に出せる v1 コンテンツがあるか。
    private func hasContent(for format: PuzzleFormat) -> Bool {
        switch format {
        case .wordOrdering, .clozeChoice: return !sentences.isEmpty
        case .listeningCloze: return !listeningSentences.isEmpty
        case .wordListening: return !words.isEmpty
        case .clozeHandwriting, .composition: return false
        }
    }

    private var schedule: [PuzzleFormat] {
        PuzzleFormatScheduler.schedule(pool: pool, length: length, seed: sessionSeed)
    }

    var body: some View {
        NavigationStack {
            Group {
                if soundOn == nil {
                    PuzzleSoundGate { soundOn = $0 }
                } else if schedule.isEmpty {
                    EmptyStateView("もんだいが ありません", systemImage: "questionmark")
                } else if finished {
                    completion
                } else if schedule.indices.contains(stepIndex) {
                    play
                } else {
                    EmptyStateView("セッションを よういできません", systemImage: "questionmark")
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(PuzzleTheme.bg.ignoresSafeArea())
            .navigationTitle("ことばパズル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
        .onDisappear { speech.stop() }
    }

    private var play: some View {
        let format = schedule[stepIndex]
        return VStack(spacing: 16) {
            progressBar
            PuzzleStepView(
                format: format,
                sentence: sentenceSample(for: format),
                word: words.isEmpty ? "" : words[stepIndex % words.count],
                entries: entries,
                soundOn: soundOn ?? false,
                stepNumber: stepIndex,
                speech: speech,
                onAdvance: advance
            )
            .id(stepIndex)   // ステップごとに状態をリセット
        }
    }

    /// 形式に応じた文サンプルを返す（きいてあなうめは confusable 語を空所にした専用プール）。
    /// 当該プールが空なら nil（StepView 側で安全に「とばす」表示にする）。
    private func sentenceSample(for format: PuzzleFormat) -> PuzzleSentenceSample? {
        let pool = (format == .listeningCloze) ? listeningSentences : sentences
        guard !pool.isEmpty else { return nil }
        return pool[stepIndex % pool.count]
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(schedule.indices, id: \.self) { i in
                Circle()
                    .fill(i == stepIndex ? PuzzleTheme.accent : PuzzleTheme.slotStroke.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            Spacer()
            Text("\(stepIndex + 1) / \(schedule.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func advance() {
        guard !schedule.isEmpty else { return }
        if stepIndex + 1 >= schedule.count {
            finished = true
        } else {
            stepIndex += 1
        }
    }

    private var completion: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "party.popper.fill")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(PuzzleTheme.accent)
            Text("クリア！")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
            VStack(spacing: 12) {
                PuzzlePrimaryButton(title: "もういちど", tint: PuzzleTheme.accent) {
                    // 新しいシードで並び・出題を振り直す。
                    sessionSeed = UInt64.random(in: .min ... .max)
                    stepIndex = 0
                    finished = false
                }
                PuzzlePrimaryButton(title: "おわる", tint: PuzzleTheme.ink.opacity(0.7)) {
                    dismiss()
                }
            }
            .frame(maxWidth: 360)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 1ステップ（形式で出し分け・自前の状態）

private struct PuzzleStepView: View {
    let format: PuzzleFormat
    let sentence: PuzzleSentenceSample?
    let word: String
    let entries: [ConfusableEntry]
    let soundOn: Bool
    let stepNumber: Int
    @ObservedObject var speech: SpeechPlayer
    let onAdvance: () -> Void

    // 並べ替え用
    @State private var placed: [OrderingTile] = []
    @State private var tray: [OrderingTile] = []
    // 選択系用
    @State private var selected: String?
    // 共通
    @State private var answered = false
    @State private var isCorrect = false

    private var seed: UInt64 {
        UInt64(truncatingIfNeeded: stepNumber) &* 0x9E37_79B9 &+ format.seedSalt
    }

    var body: some View {
        VStack(spacing: 18) {
            PuzzleFormatBadge(title: format.childTitle)
            content
            Spacer(minLength: 0)
            if answered { feedback } else { actions }
        }
        .onAppear(perform: setup)
    }

    // MARK: 形式ごとの出題ボディ

    @ViewBuilder private var content: some View {
        switch format {
        case .wordOrdering:
            if orderingExercise != nil { ordering } else { skipFallback }
        case .clozeChoice, .listeningCloze:
            if clozeExercise != nil { cloze } else { skipFallback }
        case .wordListening:
            if listeningExercise != nil { listening } else { skipFallback }
        case .clozeHandwriting, .composition:
            // プール外（未実装）。万一来ても落とさない。
            skipFallback
        }
    }

    /// 出題を用意できない（コンテンツ不足/未実装）ときに詰まらせず「つぎへ」進める。
    private var skipFallback: some View {
        VStack(spacing: 16) {
            EmptyStateView("この もんだいは おやすみ", systemImage: "hourglass")
            PuzzlePrimaryButton(title: "つぎへ", tint: PuzzleTheme.accent) { onAdvance() }
                .frame(maxWidth: 320)
        }
    }

    // ぶんづくり（並べ替え）
    private var orderingExercise: WordOrderingExercise? {
        guard let sentence else { return nil }
        return WordOrderingGenerator.make(from: sentence.item, seed: seed)
    }

    @ViewBuilder private var ordering: some View {
        promptJa
        PuzzleFlowLayout(spacing: 8) {
            ForEach(placed) { tile in orderingTile(tile, fromTray: false) }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(PuzzleTheme.slotStroke, style: .init(lineWidth: 2, dash: [7, 6]))))
        PuzzleFlowLayout(spacing: 8) {
            ForEach(tray) { tile in orderingTile(tile, fromTray: true) }
        }
    }

    private func orderingTile(_ tile: OrderingTile, fromTray: Bool) -> some View {
        Button {
            guard !answered else { return }
            PuzzleTheme.haptic()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                if fromTray, let i = tray.firstIndex(of: tile) { tray.remove(at: i); placed.append(tile) }
                else if let i = placed.firstIndex(of: tile) { placed.remove(at: i); tray.append(tile) }
            }
        } label: {
            Text(tile.text)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(PuzzleTheme.tileFill))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(PuzzleTheme.tileStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }

    // あなうめ / きいてあなうめ（選択）
    private var clozeExercise: ClozeChoiceExercise? {
        guard let sentence else { return nil }
        switch format {
        case .listeningCloze:
            return ListeningClozeGenerator.make(from: sentence.item, confusables: entries,
                                                blankIndex: sentence.blankIndex, optionCount: 4, seed: seed)
        default:
            return ClozeChoiceGenerator.make(from: sentence.item, distractors: sentence.distractors,
                                             blankIndex: sentence.blankIndex, optionCount: 4, seed: seed)
        }
    }

    @ViewBuilder private var cloze: some View {
        if let ex = clozeExercise {
            promptJa
            Text(clozeSentence(ex, filled: answered ? ex.answer : nil))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
            if !answered {
                VStack(spacing: 10) {
                    ForEach(ex.options, id: \.self) { option in
                        PuzzleOptionButton(text: option) { gradeCloze(ex, selected: option) }
                    }
                }
            }
        }
    }

    private func clozeSentence(_ ex: ClozeChoiceExercise, filled: String?) -> String {
        ex.displayTokens.enumerated().map { i, t in i == ex.blankIndex ? (filled ?? "＿＿＿") : t }
            .joined(separator: " ")
    }

    private func gradeCloze(_ ex: ClozeChoiceExercise, selected option: String) {
        guard !answered else { return }   // 連打で二重採点しない
        selected = option
        isCorrect = ClozeChoiceGrader.grade(selected: option, answer: ex.answer).isCorrect
        answered = true
        // きいてあなうめは答え合わせの「あと」に英語を読む（設問中は無音）。
        if format == .listeningCloze, soundOn { speech.speak(ex.displayTokens.joined(separator: " "), language: "en-US") }
    }

    // おとを きいて えらぶ（単語リスニング）
    private var listeningExercise: WordListeningExercise? {
        let distractors = ConfusablesSound.distractors(for: word, in: entries)
        return WordListeningGenerator.make(word: word, distractors: distractors, optionCount: 4, seed: seed)
    }

    @ViewBuilder private var listening: some View {
        if let ex = listeningExercise {
            VStack(spacing: 10) {
                Text("おとを きいて、ただしい かきかたを えらぼう")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    PuzzleTheme.haptic()
                    speech.speak(word, language: "en-US")
                } label: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 130, height: 130)
                        .background(Circle().fill(PuzzleTheme.accent))
                }
                .buttonStyle(.plain)
                .tapFeedback(bounce: true)
                .accessibilityLabel("もういちど きく")
            }
            if answered {
                Text(ex.answer)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(isCorrect ? PuzzleTheme.correct : PuzzleTheme.ink)
            } else {
                VStack(spacing: 10) {
                    ForEach(ex.options, id: \.self) { option in
                        PuzzleOptionButton(text: option) {
                            guard !answered else { return }   // 連打で二重採点しない
                            selected = option
                            isCorrect = WordListeningGrader.grade(selected: option, answer: ex.answer).isCorrect
                            answered = true
                        }
                    }
                }
            }
        }
    }

    // MARK: 共通 プロンプト/アクション/フィードバック

    private var promptJa: some View {
        Text(sentence?.item.ja ?? "")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(PuzzleTheme.ink)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private var actions: some View {
        // 並べ替えだけ「できた！」確定ボタンが要る。選択系はタップで即確定。
        if format == .wordOrdering, orderingExercise != nil {
            let ready = tray.isEmpty && !placed.isEmpty
            PuzzlePrimaryButton(title: "できた！", tint: ready ? PuzzleTheme.accent : .gray.opacity(0.4)) {
                guard ready, let ex = orderingExercise else { return }
                isCorrect = WordOrderingGrader.grade(submitted: placed.map(\.text), answer: ex.answer).isCorrect
                answered = true
            }
            .disabled(!ready)
        }
    }

    @ViewBuilder private var feedback: some View {
        VStack(spacing: 12) {
            PuzzleVerdictLabel(isCorrect: isCorrect)
            if !isCorrect, let selected, let answer = correctAnswerText {
                Text("えらんだの：\(selected) ／ せいかいは：\(answer)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if canListenBack {
                PuzzleListenButton(title: format == .wordListening ? "もういちど きく" : "きいてみる") {
                    listenBack()
                }
            }
            PuzzlePrimaryButton(title: isCorrect ? "つぎへ" : "もういちど",
                                tint: isCorrect ? PuzzleTheme.accent : PuzzleTheme.retry) {
                if isCorrect { onAdvance() } else { setup() }   // もういちど＝同ステップを組み直す
            }
        }
    }

    /// 選択系のみ「えらんだの／せいかい」を出す（並べ替えは語の集合なので出さない）。
    private var correctAnswerText: String? {
        switch format {
        case .clozeChoice, .listeningCloze: return clozeExercise?.answer
        case .wordListening: return listeningExercise?.answer
        default: return nil
        }
    }

    /// 答え合わせ後に英語を聞き返せる形式か（音ありのとき）。
    private var canListenBack: Bool {
        guard soundOn else { return false }
        switch format {
        case .clozeChoice, .listeningCloze, .wordListening: return true
        case .wordOrdering, .clozeHandwriting, .composition: return false
        }
    }

    private func listenBack() {
        switch format {
        case .wordListening:
            speech.speak(word, language: "en-US")
        case .clozeChoice, .listeningCloze:
            if let ex = clozeExercise { speech.speak(ex.displayTokens.joined(separator: " "), language: "en-US") }
        default:
            break
        }
    }

    private func setup() {
        answered = false
        isCorrect = false
        selected = nil
        if format == .wordOrdering, let ex = orderingExercise {
            placed = []
            tray = ex.scrambledTiles
        }
        // 単語リスニングは出題時に1回読み上げる（音あり時）。
        if format == .wordListening, soundOn {
            speech.speak(word, language: "en-US")
        }
    }
}

private extension PuzzleFormat {
    /// 形式ごとに出題生成の seed をずらして同ステップ番号でも内容が被らないようにする。
    var seedSalt: UInt64 {
        switch self {
        case .wordOrdering: return 1
        case .clozeChoice: return 2
        case .listeningCloze: return 3
        case .wordListening: return 7
        case .clozeHandwriting: return 11
        case .composition: return 13
        }
    }

    /// 子ども向けの形式名（バッジ表示）。
    var childTitle: String {
        switch self {
        case .wordOrdering: return "ぶんづくり"
        case .clozeChoice: return "あなうめ"
        case .listeningCloze: return "きいて あなうめ"
        case .wordListening: return "おとを きく"
        case .clozeHandwriting: return "てがき"
        case .composition: return "えいさくぶん"
        }
    }
}

#if DEBUG
struct PuzzleSessionDebugLauncher: View {
    @State private var isPresented = false
    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "puzzlepiece.fill")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Circle().fill(Color.black.opacity(0.45)))
        }
        .accessibilityLabel("ことばパズル試遊")
        .sheet(isPresented: $isPresented) { PuzzleSessionView() }
    }
}
#endif

#Preview {
    PuzzleSessionView()
}
