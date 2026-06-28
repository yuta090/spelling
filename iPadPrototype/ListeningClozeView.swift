import SwiftUI
import UIKit
import SpellingSyncCore

// リスニング穴埋め（文の空所・設問中は無音→回答後に英語を読む）の最小プレイ画面。
// 設計: docs/kotoba-puzzle-spec-2026-06-28.md（形式カタログ「リスニング穴埋め」）
// ロジックは SpellingSyncCore（ListeningClozeGenerator / ClozeChoiceGrader / ConfusablesSound）に委譲。
// 「テストでなくゲーム」：間違えてOK・何度でも。
//
// 単語リスニングとの違い：
//  - 設問中は音を出さない（読んで選ぶ）。音は答え合わせの「あと」に出る。
//  - おとりは「音が近い語」（sea/see/she …）なので、目だけでなく音の知識が要る。
//  - 公共の場対応のゲートは“やわらかい”：おとなしを選んでも問題は遊べる（音の再生だけ止める）。

// MARK: - 配色（穴埋め選択・並べ替えと同系の温かいパレット）

private enum LC {
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

// MARK: - サンプル（仮データ。後で sentence_bank ＋ confusables_sound バンドルに差し替え）

private struct ListeningClozeSample {
    let item: SentenceItem
    let blankIndex: Int
}

private enum ListeningClozeSamples {
    /// おとりは同梱 confusables_sound.build.csv から供給（空所語は登録済みの語にする）。
    static func entries() -> [ConfusableEntry] {
        ConfusablesBundle.entries
    }

    static func make() -> [ListeningClozeSample] {
        func s(_ en: String, _ ja: String, blank: Int) -> ListeningClozeSample {
            ListeningClozeSample(
                item: SentenceItem(en: en, ja: ja,
                                   tokens: en.split(separator: " ").map(String.init),
                                   gradeBand: 1),
                blankIndex: blank
            )
        }
        return [
            s("I can see the sea", "うみが みえる", blank: 4),
            s("I eat rice", "ごはんを たべる", blank: 2),
            s("Turn right here", "ここで みぎに まがる", blank: 1),
            s("Take a bath", "おふろに はいる", blank: 2),
            s("Go back home", "おうちに かえる", blank: 1)
        ]
    }
}

// MARK: - 画面

struct ListeningClozeDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechPlayer()

    /// 答え合わせ後に音を鳴らすか（クイズ前のゲートで決める）。nil = まだ選んでいない。
    @State private var soundOn: Bool?

    private let samples: [ListeningClozeSample]
    private let entries: [ConfusableEntry]

    @State private var index = 0
    @State private var selected: String?
    @State private var grade: ClozeGrade?

    fileprivate init(samples: [ListeningClozeSample] = ListeningClozeSamples.make(),
                     entries: [ConfusableEntry] = ListeningClozeSamples.entries()) {
        self.samples = samples
        self.entries = entries
    }

    private var sample: ListeningClozeSample { samples[index] }

    private var seed: UInt64 { UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9 &+ 3 }

    private var exercise: ClozeChoiceExercise? {
        ListeningClozeGenerator.make(from: sample.item, confusables: entries,
                                     blankIndex: sample.blankIndex, optionCount: 4, seed: seed)
    }

    var body: some View {
        NavigationStack {
            Group {
                if samples.isEmpty {
                    EmptyStateView("もんだいが ありません", systemImage: "questionmark")
                } else if soundOn == nil {
                    soundGate
                } else {
                    quiz
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(LC.bg.ignoresSafeArea())
            .navigationTitle("きいて あなうめ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
        }
        .onDisappear { speech.stop() }   // 閉じたら読み上げを残さない。
    }

    // MARK: クイズ前ゲート（公共の場対応・やわらかい）

    private var soundGate: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(systemName: "headphones")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(LC.accent)
            Text("こたえた あとに えいごを ならす？")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(LC.ink)
                .multilineTextAlignment(.center)
            Text("でんしゃの なかなど しずかな ところでは「おとなし」でも あそべるよ")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            VStack(spacing: 12) {
                bigButton("🔊 おとを だす", tint: LC.accent) { soundOn = true }
                bigButton("🔇 おとなし", tint: LC.ink.opacity(0.7)) { soundOn = false }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: クイズ本体

    @ViewBuilder
    private var quiz: some View {
        if let ex = exercise {
            VStack(spacing: 24) {
                prompt
                sentenceLine(ex)
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

    private var prompt: some View {
        VStack(spacing: 6) {
            Text("ただしい かきかたを えらぼう")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(sample.item.ja)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LC.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// 空所つきの英文。回答後は正解語を埋める（設問中は無音なので“読んで選ぶ”）。
    private func sentenceLine(_ ex: ClozeChoiceExercise) -> some View {
        let filled = grade == nil ? nil : ex.answer
        return Text(sentenceString(ex, filled: filled))
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(LC.ink)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
    }

    private func sentenceString(_ ex: ClozeChoiceExercise, filled: String?) -> String {
        ex.displayTokens.enumerated().map { i, token in
            i == ex.blankIndex ? (filled ?? "＿＿＿") : token
        }.joined(separator: " ")
    }

    private func options(_ ex: ClozeChoiceExercise) -> some View {
        VStack(spacing: 12) {
            ForEach(ex.options, id: \.self) { option in
                Button {
                    LC.haptic()
                    selected = option
                    grade = ClozeChoiceGrader.grade(selected: option, answer: ex.answer)
                    // 答え合わせの「あと」に英語を読む（設問中は無音）。おとなしなら鳴らさない。
                    if soundOn == true { speakSentence(ex) }
                } label: {
                    Text(option)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(LC.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(LC.tileFill))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LC.tileStroke, lineWidth: 2))
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
                    .foregroundStyle(LC.correct)
            } else {
                VStack(spacing: 4) {
                    Label("ナイス チャレンジ！", systemImage: "flame.fill")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(LC.accent)
                    if let selected {
                        Text("えらんだの：\(selected) ／ せいかいは：\(ex.answer)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // 音を出す設定のときだけ「もういちど きく」を出す（おとなしでは隠す）。
            if soundOn == true {
                Button {
                    LC.haptic()
                    speakSentence(ex)
                } label: {
                    Label("もういちど きく", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(LC.accent)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Capsule().fill(LC.tileFill))
                        .overlay(Capsule().stroke(LC.tileStroke, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .tapFeedback(bounce: true)
            }

            bigButton(isCorrect ? "つぎへ" : "もういちど",
                      tint: isCorrect ? LC.accent : LC.retry) {
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

    /// 正解を埋めた完成文を読み上げる（答えは画面に既に出ているので漏れない）。
    private func speakSentence(_ ex: ClozeChoiceExercise) {
        speech.speak(ex.displayTokens.joined(separator: " "), language: "en-US")
    }

    private func retry() {
        speech.stop()          // 読み上げ中なら止める（やり直し中に正解が聞こえない）。
        withAnimation(.easeInOut(duration: 0.2)) {
            selected = nil
            grade = nil
        }
    }

    private func next() {
        // 採点後だけ進む。連打で1問飛ばさない＋空配列ガード。
        guard grade != nil, !samples.isEmpty else { return }
        speech.stop()          // 次の設問を無音で始める（前問の読み上げを持ち越さない）。
        index = (index + 1) % samples.count
        selected = nil
        grade = nil
    }
}

// MARK: - DEBUG 起動ボタン（製品UIには出さない）

#if DEBUG
/// リスニング穴埋めの試遊画面を開く DEBUG 限定ボタン。`RootView` に overlay で差し込む。
struct ListeningClozeDebugLauncher: View {
    @State private var isPresented = false
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .padding(.bottom, 12)
        .accessibilityLabel("リスニング穴埋め試遊")
        .sheet(isPresented: $isPresented) {
            ListeningClozeDemoView()
        }
    }
}
#endif

#Preview {
    ListeningClozeDemoView()
}
