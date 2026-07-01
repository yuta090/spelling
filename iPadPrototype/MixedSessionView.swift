import SwiftUI
import UIKit
import SpellingSyncCore

// 混合セッションの試遊画面：並べ替えと穴埋めが SessionComposer の順で交互に出る。
// 設計: docs/exercise-formats-and-distractors-2026-06-28.md
// ロジックは SpellingSyncCore（SessionComposer / 各 Generator / Grader）に委譲。

private enum MX {
    static let ink = Color(red: 0.45, green: 0.28, blue: 0.08)
    static let tileFill = Color(red: 1.0, green: 0.97, blue: 0.86)
    static let tileStroke = Color(red: 0.95, green: 0.73, blue: 0.34)
    static let slotStroke = Color(red: 0.90, green: 0.82, blue: 0.66)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let correct = Color(red: 0.30, green: 0.62, blue: 0.28)
    static let retry = Color(red: 0.84, green: 0.36, blue: 0.08)
    static let bg = Color(red: 1.0, green: 0.99, blue: 0.95)
    @MainActor
    static func haptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - サンプル（並べ替え・穴埋めの両方で使える文）

private struct MixSample {
    let item: SentenceItem
    let blankIndex: Int
    let distractors: [String]
}

private enum MixedSamples {
    static func make() -> [MixSample] {
        func s(_ en: String, _ ja: String, blank: Int, _ d: [String], _ g: GrammarPoint) -> MixSample {
            MixSample(item: SentenceItem(en: en, ja: ja,
                                         tokens: en.split(separator: " ").map(String.init),
                                         gradeBand: 1, grammar: g),
                      blankIndex: blank, distractors: d)
        }
        return [
            s("I like apples", "わたしは りんごが すき", blank: 1, ["likes", "liked", "want"], .presentSimple),
            s("She is happy", "かのじょは うれしい", blank: 1, ["am", "are", "be"], .beVerb),
            s("We go to school", "がっこうへ いく", blank: 1, ["goes", "went", "going"], .presentSimple),
            s("He can swim", "かれは およげる", blank: 1, ["is", "does", "will"], .canModal),
            s("This bag is bigger", "この かばんは もっと 大きい", blank: 3, ["big", "biggest", "more"], .comparativeEr)
        ]
    }
}

// MARK: - セッション全体

struct MixedSessionDemoView: View {
    @Environment(\.dismiss) private var dismiss

    private let samples: [MixSample]
    private let byID: [UUID: MixSample]
    private let steps: [SessionStep]
    @State private var stepIndex = 0

    fileprivate init(samples: [MixSample] = MixedSamples.make()) {
        self.samples = samples
        self.byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.item.id, $0) })
        // 並べ替えと穴埋めを混ぜた決定論セッション。
        self.steps = SessionComposer.compose(
            items: samples.map(\.item),
            formats: [.wordOrdering, .clozeChoice],
            length: 8, seed: 20260628)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if steps.indices.contains(stepIndex), let sample = byID[steps[stepIndex].item.id] {
                    progressBar
                    StepPlayer(step: steps[stepIndex], sample: sample, stepNumber: stepIndex) {
                        stepIndex = (stepIndex + 1) % steps.count
                    }
                    .id(stepIndex)   // ステップが変わるたびに状態をリセット
                } else {
                    EmptyStateView("セッションを よういできません", systemImage: "questionmark")
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(MX.bg.ignoresSafeArea())
            .navigationTitle("れんしゅう")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("とじる") { dismiss() } }
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                Circle()
                    .fill(i == stepIndex ? MX.accent : MX.slotStroke.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            Spacer()
            Text("\(stepIndex + 1) / \(steps.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 1ステップ（形式で出し分け・自前の状態）

private struct StepPlayer: View {
    let step: SessionStep
    let sample: MixSample
    let stepNumber: Int
    let onAdvance: () -> Void

    @State private var placed: [OrderingTile] = []
    @State private var tray: [OrderingTile] = []
    @State private var selected: String?
    @State private var answered = false
    @State private var isCorrect = false

    private var seed: UInt64 { UInt64(truncatingIfNeeded: stepNumber) &* 0x9E37_79B9 &+ 1 }

    var body: some View {
        VStack(spacing: 18) {
            badge
            Text(sample.item.ja)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(MX.ink)
                .multilineTextAlignment(.center)

            switch step.format {
            case .wordOrdering: ordering
            case .clozeChoice:  cloze
            default:            cloze   // v1 は2形式のみ
            }

            Spacer(minLength: 0)
            if answered { feedback } else { actions }
        }
        .onAppear(perform: setup)
    }

    private var badge: some View {
        Text(step.format == .wordOrdering ? "ならべかえ" : "あなうめ")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(MX.accent))
    }

    // MARK: 並べ替え
    private var orderingExercise: WordOrderingExercise? {
        WordOrderingGenerator.make(from: sample.item, seed: seed)
    }

    @ViewBuilder private var ordering: some View {
        MiniFlow(spacing: 8) {
            ForEach(placed) { tile in tileButton(tile, fromTray: false) }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MX.slotStroke, style: .init(lineWidth: 2, dash: [7, 6]))))

        MiniFlow(spacing: 8) {
            ForEach(tray) { tile in tileButton(tile, fromTray: true) }
        }
    }

    private func tileButton(_ tile: OrderingTile, fromTray: Bool) -> some View {
        Button {
            guard !answered else { return }
            MX.haptic()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                if fromTray, let i = tray.firstIndex(of: tile) { tray.remove(at: i); placed.append(tile) }
                else if let i = placed.firstIndex(of: tile) { placed.remove(at: i); tray.append(tile) }
            }
        } label: {
            Text(tile.text)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(MX.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(MX.tileFill))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MX.tileStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }

    // MARK: 穴埋め
    private var clozeExercise: ClozeChoiceExercise? {
        ClozeChoiceGenerator.make(from: sample.item, distractors: sample.distractors,
                                  blankIndex: sample.blankIndex, optionCount: 4, seed: seed)
    }

    @ViewBuilder private var cloze: some View {
        if let ex = clozeExercise {
            Text(clozeSentence(ex, filled: answered ? ex.answer : nil))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(MX.ink)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                ForEach(ex.options, id: \.self) { option in
                    Button {
                        guard !answered else { return }
                        MX.haptic()
                        selected = option
                        isCorrect = ClozeChoiceGrader.grade(selected: option, answer: ex.answer).isCorrect
                        answered = true
                    } label: {
                        Text(option)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(MX.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(MX.tileFill))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MX.tileStroke, lineWidth: 2))
                    }
                    .buttonStyle(.plain).tapFeedback(bounce: true)
                }
            }
        }
    }

    private func clozeSentence(_ ex: ClozeChoiceExercise, filled: String?) -> String {
        ex.displayTokens.enumerated().map { i, t in i == ex.blankIndex ? (filled ?? "＿＿＿") : t }
            .joined(separator: " ")
    }

    // MARK: 共通 アクション/フィードバック
    @ViewBuilder private var actions: some View {
        if step.format == .wordOrdering {
            bigButton("できた！", tint: (tray.isEmpty && !placed.isEmpty) ? MX.accent : .gray.opacity(0.4)) {
                guard let ex = orderingExercise else { return }
                isCorrect = WordOrderingGrader.grade(submitted: placed.map(\.text), answer: ex.answer).isCorrect
                answered = true
            }
            .disabled(!(tray.isEmpty && !placed.isEmpty))
        }
        // 穴埋めは選択した瞬間に確定するのでボタン無し。
    }

    @ViewBuilder private var feedback: some View {
        VStack(spacing: 12) {
            if isCorrect {
                Label("やったね！ せいかい！", systemImage: "star.fill")
                    .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(MX.correct)
            } else {
                Label("ナイス チャレンジ！", systemImage: "flame.fill")
                    .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(MX.accent)
            }
            bigButton(isCorrect ? "つぎへ" : "もういちど", tint: isCorrect ? MX.accent : MX.retry) {
                if isCorrect { onAdvance() } else { setup() }   // もういちど＝同ステップを組み直す
            }
        }
    }

    private func bigButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(tint))
        }
        .buttonStyle(.plain).tapFeedback(bounce: true)
    }

    private func setup() {
        answered = false
        isCorrect = false
        selected = nil
        if step.format == .wordOrdering, let ex = orderingExercise {
            placed = []
            tray = ex.scrambledTiles
        }
    }
}

// MARK: - 折り返しレイアウト（iOS16+・この画面用）

private struct MiniFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { widest = max(widest, x - spacing); x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: min(max(widest, x - spacing), maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - DEBUG 起動ボタン

#if DEBUG
struct MixedSessionDebugLauncher: View {
    @State private var isPresented = false
    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "shuffle.circle.fill")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Circle().fill(Color.black.opacity(0.45)))
        }
        .padding(.leading, 12).padding(.bottom, 60)
        .accessibilityLabel("混合セッション試遊")
        .sheet(isPresented: $isPresented) { MixedSessionDemoView() }
    }
}
#endif

#Preview {
    MixedSessionDemoView()
}
