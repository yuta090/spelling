import SwiftUI
import UIKit
import SpellingSyncCore

// 文づくり（並べ替え）の最小プレイ画面。
// 設計: docs/sentence-builder-design-2026-06-27.md
// ロジックは `SpellingSyncCore`（WordOrderingGenerator / WordOrderingGrader）に委譲し、
// この画面は提示と入力だけを担う（アプリ本体は薄く保つ方針）。
// まずは「触って確かめる」ための独立画面。未習語タップ→復習導線は次イテレーションで AppModel/SRS に接続する。

// MARK: - 配色（既存の温かいパレットに合わせる）

private enum WO {
    static let ink = Color(red: 0.45, green: 0.28, blue: 0.08)
    static let tileFill = Color(red: 1.0, green: 0.97, blue: 0.86)
    static let tileStroke = Color(red: 0.95, green: 0.73, blue: 0.34)
    static let slotStroke = Color(red: 0.90, green: 0.82, blue: 0.66)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let correct = Color(red: 0.30, green: 0.62, blue: 0.28)
    static let retry = Color(red: 0.84, green: 0.36, blue: 0.08)
    static let bg = Color(red: 1.0, green: 0.99, blue: 0.95)
    static let hintFill = Color(red: 1.0, green: 0.98, blue: 0.90)
}

// MARK: - サンプル文（仮データ。後で sentence_bank に差し替え）

private enum WordOrderingSamples {
    static func make() -> [SentenceItem] {
        func item(_ en: String, _ ja: String, band: Int, _ grammar: GrammarPoint) -> SentenceItem {
            SentenceItem(en: en, ja: ja, tokens: en.split(separator: " ").map(String.init),
                         gradeBand: band, grammar: grammar)
        }
        // 文法タグを散らして、不正解時の「かいせつ」が項目ごとに変わるのを確認できるようにする。
        return [
            item("I like apples", "わたしは りんごが すき", band: 1, .presentSimple),
            item("She is my friend", "かのじょは わたしの ともだち", band: 2, .beVerb),
            item("He can run fast", "かれは はやく はしれる", band: 2, .canModal),
            item("I am reading a book", "わたしは 本を よんでいる", band: 1, .presentContinuous),
            item("We played soccer", "わたしたちは サッカーを した", band: 1, .pastSimple),
            item("This bag is bigger", "この かばんは もっと 大きい", band: 2, .comparativeEr)
        ]
    }
}

// MARK: - 画面

struct WordOrderingDemoView: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [SentenceItem]
    @StateObject private var speech = SpeechPlayer()
    /// タイルがトレイ↔解答欄を「飛んで」移動するための共有ネームスペース。
    @Namespace private var tileNS
    @State private var index = 0
    @State private var reshuffle = 0

    /// 正解列に置いたタイル（順序＝解答）。
    @State private var placed: [OrderingTile] = []
    /// まだ置いていないタイル。
    @State private var tray: [OrderingTile] = []
    @State private var grade: OrderingGrade?

    init(items: [SentenceItem] = WordOrderingSamples.make()) {
        self.items = items
    }

    private var item: SentenceItem { items[index] }

    private var exercise: WordOrderingExercise? {
        WordOrderingGenerator.make(from: item, seed: seed)
    }

    private var seed: UInt64 {
        UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9 &+ UInt64(truncatingIfNeeded: reshuffle)
    }

    private var isComplete: Bool { tray.isEmpty && !placed.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                prompt
                VStack(spacing: 10) {
                    answerRow
                    // 完成させた文の真下に「きいてみる」。読むのは“子が並べた文”なので答えは漏れない。
                    if isComplete {
                        listenButton
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isComplete)
                trayRow
                Spacer(minLength: 0)
                feedbackAndActions
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(WO.bg.ignoresSafeArea())
            .navigationTitle("ぶんづくり")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: 部品

    private var prompt: some View {
        VStack(spacing: 6) {
            Text("にほんごを みて、ただしい じゅんに ならべよう")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(item.ja)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(WO.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// 解答スロット。置いたタイルをタップで戻せる。
    private var answerRow: some View {
        FlowLayout(spacing: 10) {
            ForEach(placed) { tile in
                tileButton(tile, role: .placed)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(WO.slotStroke, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                )
        )
        .overlay(alignment: .leading) {
            if placed.isEmpty {
                Text("ここに ならべる")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 18)
                    .allowsHitTesting(false)
            }
        }
    }

    /// バラのタイル置き場。
    private var trayRow: some View {
        FlowLayout(spacing: 10) {
            ForEach(tray) { tile in
                tileButton(tile, role: .tray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 完成した文を聞くボタン。読み上げるのは **子が並べた文**（`placed`）。
    /// 正解文ではないので、間違っていても答えは漏れず、耳でのセルフチェックになる。
    private var listenButton: some View {
        Button {
            WordOrderingHaptics.tap()
            let sentence = placed.map(\.text).joined(separator: " ")
            speech.speak(sentence, language: "en-US")
        } label: {
            Label("きいてみる", systemImage: "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(WO.accent)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(Capsule().fill(WO.tileFill))
                .overlay(Capsule().stroke(WO.tileStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }

    /// 不正解時の文法解説カード。`GrammarPoint` の事前作成された固定文（トンマナ安全）。
    private func explanationCard(_ point: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(point.titleJa, systemImage: "lightbulb.fill")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WO.accent)
            Text(point.explanationJa)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(WO.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(WO.hintFill))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WO.tileStroke, lineWidth: 1.5))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private enum TileRole { case tray, placed }

    private func tileButton(_ tile: OrderingTile, role: TileRole) -> some View {
        Button {
            guard grade == nil else { return }
            WordOrderingHaptics.tap()
            switch role {
            case .tray:
                move(tile, from: &tray, to: &placed)
            case .placed:
                move(tile, from: &placed, to: &tray)
            }
        } label: {
            Text(tile.text)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(WO.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(WO.tileFill))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(WO.tileStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        // トレイ↔解答欄でタイルが実際に飛んで移動する（選んだ気持ちよさ）。
        .matchedGeometryEffect(id: tile.id, in: tileNS)
        .tapFeedback(bounce: true)
    }

    @ViewBuilder
    private var feedbackAndActions: some View {
        if let grade {
            VStack(spacing: 14) {
                if grade.isCorrect {
                    Label("せいかい！", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(WO.correct)
                    bigButton("つぎへ", tint: WO.accent, action: next)
                } else {
                    Label("おしい！ \(grade.correctPositions)/\(grade.total) あってる",
                          systemImage: "arrow.uturn.left.circle.fill")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(WO.retry)
                    // 不正解のときだけ、その文の文法の「かいせつ」を出す（事前作成の固定文）。
                    if let grammar = item.grammar {
                        explanationCard(grammar)
                    }
                    bigButton("もういちど", tint: WO.retry, action: retry)
                }
            }
        } else {
            bigButton("こたえあわせ", tint: isComplete ? WO.accent : Color.gray.opacity(0.4),
                      action: check)
                .disabled(!isComplete)
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

    // MARK: 操作

    private func move(_ tile: OrderingTile, from src: inout [OrderingTile], to dst: inout [OrderingTile]) {
        guard let i = src.firstIndex(of: tile) else { return }
        // 低ダンピングで少し行き過ぎてプルッと戻る（タイルが飛ぶ動きに弾みをつける）。
        withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
            src.remove(at: i)
            dst.append(tile)
        }
    }

    private func load() {
        guard let ex = exercise else { return }
        placed = []
        tray = ex.scrambledTiles
        grade = nil
    }

    private func check() {
        guard let ex = exercise else { return }
        grade = WordOrderingGrader.grade(submitted: placed.map(\.text), answer: ex.answer)
    }

    private func retry() {
        withAnimation(.easeInOut(duration: 0.2)) {
            tray = (tray + placed)
            placed = []
            grade = nil
        }
        reshuffle += 1
        load()
    }

    private func next() {
        index = (index + 1) % items.count
        reshuffle = 0
        load()
    }
}

// MARK: - 折り返しレイアウト（iOS16+）

/// タイルを左上から詰めて、横幅を超えたら折り返す素朴なフローレイアウト。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - ハプティクス

/// タイル選択時の軽い触覚フィードバック（選んだ手応え）。
private enum WordOrderingHaptics {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - DEBUG 起動ボタン（製品UIには出さない）

#if DEBUG
/// 文づくり（並べ替え）の試遊画面を開く DEBUG 限定ボタン。`RootView` に overlay で差し込む。
struct WordOrderingDebugLauncher: View {
    @State private var isPresented = false
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "arrow.left.arrow.right.square.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .accessibilityLabel("文づくり試遊")
        .sheet(isPresented: $isPresented) {
            WordOrderingDemoView()
        }
    }
}
#endif

#Preview {
    WordOrderingDemoView()
}
