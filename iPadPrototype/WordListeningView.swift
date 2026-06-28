import SwiftUI
import UIKit
import SpellingSyncCore

// 単語リスニング（音を聞いて正しい綴りを選ぶ）の最小プレイ画面。
// 設計: docs/kotoba-puzzle-spec-2026-06-28.md / exercise-formats-and-distractors-2026-06-28.md
// ロジックは SpellingSyncCore（WordListeningGenerator / WordListeningGrader / ConfusablesSound）に委譲。
// 「テストでなくゲーム」：間違えてOK・何度でも。スピーカーを押すと何度でも聞ける。
//
// 公共の場（電車など）対応：クイズ前に「おとを だす？」のゲートを置く。
// 単語リスニングは音が本体なので、おとOFF を選んだときは無理に出題せず、やさしく見送る。

// MARK: - 配色（穴埋め・並べ替え画面と同系の温かいパレット）

private enum WL {
    static let ink = Color(red: 0.45, green: 0.28, blue: 0.08)
    static let tileFill = Color(red: 1.0, green: 0.97, blue: 0.86)
    static let tileStroke = Color(red: 0.95, green: 0.73, blue: 0.34)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let correct = Color(red: 0.30, green: 0.62, blue: 0.28)
    static let retry = Color(red: 0.84, green: 0.36, blue: 0.08)
    static let bg = Color(red: 1.0, green: 0.99, blue: 0.95)

    static func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - サンプル（仮データ。後で wordbank ＋ confusables_sound バンドルに差し替え）

private enum WordListeningSamples {
    /// 承認済み confusables（scripts/confusables_sound_draft.csv の一部）を埋め込み、
    /// 実データ経路（ConfusablesSound.parse → distractors）で組み立てる。
    static let confusablesCSV = """
    word,sounds_like,approved,source
    right,light|night|white,1,ai
    rice,nice|race|lice,1,ai
    berry,very|cherry|bury,1,ai
    base,case|face|vase,1,ai
    sea,see|tea|she,1,ai
    back,bag|pack|sack,1,ai
    bath,path|bat|math,1,ai
    """

    /// 出題する単語（このデモで読み上げる語）。
    static let words = ["right", "rice", "berry", "base", "sea", "back", "bath"]

    static func entries() -> [ConfusableEntry] {
        ConfusablesSound.parse(csv: confusablesCSV)
    }
}

// MARK: - 画面

struct WordListeningDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()

    /// 音を出すか（クイズ前のゲートで決める）。nil = まだ選んでいない。
    @State private var soundOn: Bool?

    private let words: [String]
    private let entries: [ConfusableEntry]

    @State private var index = 0
    @State private var selected: String?
    @State private var grade: ClozeGrade?

    fileprivate init(words: [String] = WordListeningSamples.words,
                     entries: [ConfusableEntry] = WordListeningSamples.entries()) {
        self.words = words
        self.entries = entries
    }

    private var word: String { words[index] }

    private var seed: UInt64 { UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9 &+ 7 }

    private var exercise: WordListeningExercise? {
        let distractors = ConfusablesSound.distractors(for: word, in: entries)
        return WordListeningGenerator.make(word: word, distractors: distractors,
                                           optionCount: 4, seed: seed)
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    // 注入データが空でも word[index] でクラッシュしないよう守る（既定データは非空）。
                    EmptyStateView("もんだいが ありません", systemImage: "questionmark")
                } else {
                    switch soundOn {
                    case .none:
                        soundGate
                    case .some(true):
                        quiz
                    case .some(false):
                        soundOffNotice
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(WL.bg.ignoresSafeArea())
            .navigationTitle("おとを きいて えらぼう")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
    }

    // MARK: クイズ前ゲート（公共の場対応）

    private var soundGate: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(systemName: "headphones")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(WL.accent)
            Text("おとを だして いい？")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(WL.ink)
            Text("でんしゃの なかなど、しずかな ところでは「おとなし」をえらんでね")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            VStack(spacing: 12) {
                bigButton("🔊 おとを だす", tint: WL.accent) {
                    soundOn = true
                    speakWord()
                }
                bigButton("🔇 おとなし", tint: WL.ink.opacity(0.7)) {
                    soundOn = false
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var soundOffNotice: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.secondary)
            Text("おとが だせる ところで あそぼう！")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WL.ink)
                .multilineTextAlignment(.center)
            Text("「おとを きいて えらぶ」は みみで あそぶ もんだいだよ")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            bigButton("やっぱり おとを だす", tint: WL.accent) {
                soundOn = true
                speakWord()
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: クイズ本体

    @ViewBuilder
    private var quiz: some View {
        if let ex = exercise {
            VStack(spacing: 24) {
                speakerButton
                Spacer(minLength: 0)
                if grade == nil {
                    options(ex)
                } else {
                    feedback(ex)
                }
            }
        } else {
            EmptyStateView("もんだいを よういできません", systemImage: "questionmark")
        }
    }

    /// 大きいスピーカー。押すたびに何度でも聞ける。
    private var speakerButton: some View {
        VStack(spacing: 10) {
            Text("おとを きいて、ただしい かきかたを えらぼう")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                WL.haptic()
                speakWord()
            } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 140, height: 140)
                    .background(Circle().fill(WL.accent))
            }
            .buttonStyle(.plain)
            .tapFeedback(bounce: true)
            .accessibilityLabel("もういちど きく")
            Text("タップで もういちど")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    /// 選択肢ボタン（タップで回答）。
    private func options(_ ex: WordListeningExercise) -> some View {
        VStack(spacing: 12) {
            ForEach(ex.options, id: \.self) { option in
                Button {
                    WL.haptic()
                    selected = option
                    grade = WordListeningGrader.grade(selected: option, answer: ex.answer)
                } label: {
                    Text(option)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(WL.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(WL.tileFill))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WL.tileStroke, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .tapFeedback(bounce: true)
            }
        }
    }

    @ViewBuilder
    private func feedback(_ ex: WordListeningExercise) -> some View {
        let isCorrect = grade?.isCorrect == true
        VStack(spacing: 14) {
            // 答え合わせ後は正解語を大きく見せる（耳→目の確認）。
            Text(ex.answer)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(isCorrect ? WL.correct : WL.ink)

            if isCorrect {
                Label("やったね！ せいかい！", systemImage: "star.fill")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(WL.correct)
            } else {
                VStack(spacing: 4) {
                    Label("ナイス チャレンジ！", systemImage: "flame.fill")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(WL.accent)
                    if let selected {
                        Text("えらんだの：\(selected) ／ せいかいは：\(ex.answer)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // もう一度聞ける。
            Button {
                WL.haptic()
                speakWord()
            } label: {
                Label("もういちど きく", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(WL.accent)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Capsule().fill(WL.tileFill))
                    .overlay(Capsule().stroke(WL.tileStroke, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .tapFeedback(bounce: true)

            bigButton(isCorrect ? "つぎへ" : "もういちど",
                      tint: isCorrect ? WL.accent : WL.retry) {
                if isCorrect { next() } else { retry() }
            }
        }
    }

    private func bigButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 18).fill(tint))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }

    // MARK: 動作

    private func speakWord() {
        speech.speak(word, language: "en-US")
    }

    private func retry() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selected = nil
            grade = nil
        }
    }

    private func next() {
        // 採点後だけ進む。子どもが「つぎへ」を連打しても1問飛ばさない。
        guard grade != nil, !words.isEmpty else { return }
        index = (index + 1) % words.count
        selected = nil
        grade = nil
        speakWord()
    }
}

// MARK: - DEBUG 起動ボタン（製品UIには出さない）

#if DEBUG
/// 単語リスニングの試遊画面を開く DEBUG 限定ボタン。`RootView` に overlay で差し込む。
struct WordListeningDebugLauncher: View {
    @State private var isPresented = false
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "ear.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .padding(.bottom, 12)
        .accessibilityLabel("リスニング試遊")
        .sheet(isPresented: $isPresented) {
            WordListeningDemoView()
        }
    }
}
#endif

#Preview {
    WordListeningDemoView()
}
