import SwiftUI
import UIKit
import SpellingSyncCore

// 穴埋め・選択（読む）の最小プレイ画面。
// 設計: docs/exercise-formats-and-distractors-2026-06-28.md
// ロジックは SpellingSyncCore（ClozeChoiceGenerator / ClozeChoiceGrader）に委譲。
// 「テストでなくゲーム」：間違えてOK・何度でも。答え合わせ後に正しい文を音声で聞ける。

// MARK: - 配色（並べ替え画面と同系の温かいパレット）

private enum CZ {
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

// MARK: - サンプル（仮データ。後で sentence_bank ＋ おとり生成に差し替え）

private struct ClozeSample {
    let item: SentenceItem
    let blankIndex: Int
    let distractors: [String]
}

private enum ClozeChoiceSamples {
    static func make() -> [ClozeSample] {
        func s(_ en: String, _ ja: String, blank: Int, _ distractors: [String], _ g: GrammarPoint) -> ClozeSample {
            ClozeSample(
                item: SentenceItem(en: en, ja: ja,
                                   tokens: en.split(separator: " ").map(String.init),
                                   gradeBand: 1, grammar: g),
                blankIndex: blank,
                distractors: distractors
            )
        }
        // おとりは語形変化・文法の紛らわしい近接形（研究: 初級は形が近い語が効く）。
        return [
            s("I like apples", "わたしは りんごが すき", blank: 1, ["likes", "liked", "want"], .presentSimple),
            s("She is happy", "かのじょは うれしい", blank: 1, ["am", "are", "be"], .beVerb),
            s("We played soccer", "サッカーを した", blank: 1, ["play", "plays", "playing"], .pastSimple),
            s("He can swim", "かれは およげる", blank: 1, ["is", "does", "will"], .canModal),
            s("This bag is bigger", "この かばんは もっと 大きい", blank: 3, ["big", "biggest", "more"], .comparativeEr)
        ]
    }
}

// MARK: - 画面

struct ClozeChoiceDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()

    private let samples: [ClozeSample]
    @State private var index = 0
    @State private var selected: String?
    @State private var grade: ClozeGrade?

    fileprivate init(samples: [ClozeSample] = ClozeChoiceSamples.make()) {
        self.samples = samples
    }

    private var sample: ClozeSample { samples[index] }

    private var exercise: ClozeChoiceExercise? {
        ClozeChoiceGenerator.make(from: sample.item, distractors: sample.distractors,
                                  blankIndex: sample.blankIndex, optionCount: 4, seed: seed)
    }

    private var seed: UInt64 { UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9 &+ 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                prompt
                if let ex = exercise {
                    sentenceLine(ex)
                    Spacer(minLength: 0)
                    if grade == nil {
                        options(ex)
                    } else {
                        feedback(ex)
                    }
                } else {
                    EmptyStateView("もんだいを よういできません", systemImage: "questionmark")
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(CZ.bg.ignoresSafeArea())
            .navigationTitle("あなうめ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
    }

    // MARK: 部品

    private var prompt: some View {
        VStack(spacing: 6) {
            Text("ただしい ことばを えらぼう")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(sample.item.ja)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(CZ.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// 空所つきの英文。回答後は正解語を緑で埋める。
    private func sentenceLine(_ ex: ClozeChoiceExercise) -> some View {
        let filled = grade == nil ? nil : ex.answer
        return Text(sentenceString(ex, filled: filled))
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(CZ.ink)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
    }

    private func sentenceString(_ ex: ClozeChoiceExercise, filled: String?) -> String {
        ex.displayTokens.enumerated().map { i, token in
            i == ex.blankIndex ? (filled ?? "＿＿＿") : token
        }.joined(separator: " ")
    }

    /// 選択肢ボタン（タップで回答）。
    private func options(_ ex: ClozeChoiceExercise) -> some View {
        VStack(spacing: 12) {
            ForEach(ex.options, id: \.self) { option in
                Button {
                    CZ.haptic()
                    selected = option
                    grade = ClozeChoiceGrader.grade(selected: option, answer: ex.answer)
                } label: {
                    Text(option)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(CZ.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(CZ.tileFill))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CZ.tileStroke, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .tapFeedback(bounce: true)
            }
        }
    }

    @ViewBuilder
    private func feedback(_ ex: ClozeChoiceExercise) -> some View {
        let isCorrect = grade?.isCorrect == true
        VStack(spacing: 14) {
            if isCorrect {
                Label("やったね！ せいかい！", systemImage: "star.fill")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(CZ.correct)
            } else {
                VStack(spacing: 4) {
                    Label("ナイス チャレンジ！", systemImage: "flame.fill")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(CZ.accent)
                    if let selected {
                        Text("えらんだの：\(selected) ／ せいかいは：\(ex.answer)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // 答え合わせ後に正しい文を聞ける。
            Button {
                CZ.haptic()
                speech.speak(ex.displayTokens.joined(separator: " "), language: "en-US")
            } label: {
                Label("きいてみる", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(CZ.accent)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Capsule().fill(CZ.tileFill))
                    .overlay(Capsule().stroke(CZ.tileStroke, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .tapFeedback(bounce: true)

            bigButton(isCorrect ? "つぎへ" : "もういちど",
                      tint: isCorrect ? CZ.accent : CZ.retry) {
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

    private func retry() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selected = nil
            grade = nil
        }
    }

    private func next() {
        index = (index + 1) % samples.count
        selected = nil
        grade = nil
    }
}

// MARK: - DEBUG 起動ボタン（製品UIには出さない）

#if DEBUG
/// 穴埋め選択の試遊画面を開く DEBUG 限定ボタン。`RootView` に overlay で差し込む。
struct ClozeChoiceDebugLauncher: View {
    @State private var isPresented = false
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .padding(.bottom, 12)
        .accessibilityLabel("穴埋め試遊")
        .sheet(isPresented: $isPresented) {
            ClozeChoiceDemoView()
        }
    }
}
#endif

#Preview {
    ClozeChoiceDemoView()
}
