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
    /// 「しらない ことば」を選んだときに復習へ積むコールバック（AppModel に依存させないため）。
    private let onEnrollReviewWord: (String) -> Void
    /// 復習チップに出してはいけない語（＝登場人物の名前）。英字のみ小文字化したキーで保持。
    /// 未成年実名を綴り練習・復習（→同期）に侵入させないためのガード。デフォルト空＝従来どおり。
    private let hiddenNameKeys: Set<String>
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
    /// この問題で「しらない」と選んだ語（復習に積んだ＝マーカー表示）。
    @State private var markedUnknown: Set<String> = []

    init(
        items: [SentenceItem] = WordOrderingSamples.make(),
        hiddenReviewWords: Set<String> = [],
        onEnrollReviewWord: @escaping (String) -> Void = { _ in }
    ) {
        self.items = items
        self.onEnrollReviewWord = onEnrollReviewWord
        self.hiddenNameKeys = Set(hiddenReviewWords.map(Self.nameKey))
    }

    /// 復習除外比較用キー：英字のみ・小文字（"Yuta," も "yuki" も名前一致するように）。
    static func nameKey(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter })
    }

    /// このトークンは登場人物の名前か（呼びかけ "Yuta," や所有格 "Yuki's" も含めて判定）。
    private func isHiddenName(_ token: String) -> Bool {
        let key = Self.nameKey(token)
        if hiddenNameKeys.contains(key) { return true }
        // 所有格 "Yuki's" → "yukis" の末尾 s を落として再判定。
        if key.hasSuffix("s"), hiddenNameKeys.contains(String(key.dropLast())) { return true }
        return false
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
                // テストではなく“ゲーム”：間違えても前向き＆何度でも。
                if grade.isCorrect {
                    Label("やったね！ せいかい！", systemImage: "star.fill")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(WO.correct)
                } else {
                    VStack(spacing: 4) {
                        Label("ナイス チャレンジ！", systemImage: "flame.fill")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(WO.accent)
                        Text(grade.correctPositions > 0
                             ? "あと \(grade.total - grade.correctPositions)こ！ もういちど やってみよう"
                             : "だいじょうぶ、なんども やってみよう")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    // 不正解のときは「せいかいの文＋意味＋（あれば）文法解説」を1枚で見せる。
                    // 置いた（間違った）タイルはそのまま残し、その下に正解を出す。
                    // grammar が nil でも正解文・意味は出す（従来は正解文を見せていなかった欠落の修正）。
                    AnswerExplanationCard(
                        explanation: SentenceFeedback.make(
                            item: item, submitted: placed.map(\.text), grade: grade
                        )
                    )
                }
                // 回答後に「しらない ことば」を選んで復習へ積む（並べ替えのタップとは衝突しない）。
                unknownWordChooser
                if grade.isCorrect {
                    bigButton("つぎへ", tint: WO.accent, action: next)
                } else {
                    bigButton("もういちど", tint: WO.retry, action: retry)
                }
            }
        } else {
            bigButton("できた！", tint: isComplete ? WO.accent : Color.gray.opacity(0.4),
                      action: check)
                .disabled(!isComplete)
        }
    }

    /// 回答後に出す「しらない ことばは？」チューザー。タップした語を復習へ積む（★マーカー）。
    private var unknownWordChooser: some View {
        VStack(spacing: 8) {
            Text("しらない ことばは？ タップで ふくしゅうに ついか")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(sentenceWords, id: \.self) { unknownChip($0) }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// 文の単語チップ（重複は1つに）。タップで「しらない」マーク＝復習登録。
    private func unknownChip(_ word: String) -> some View {
        let key = word.lowercased()
        let marked = markedUnknown.contains(key)
        return Button {
            WordOrderingHaptics.tap()
            if marked {
                markedUnknown.remove(key)            // マーク解除（既に積んだ復習は取り消さない）
            } else if !isHiddenName(word) {
                // 名前は復習へ積まない（同期で端末外へ出さないための最終ガード）。
                markedUnknown.insert(key)
                onEnrollReviewWord(word)             // 復習へ積む（重複は AppModel 側で無視）
            }
        } label: {
            HStack(spacing: 4) {
                if marked {
                    Image(systemName: "star.fill").font(.system(size: 12, weight: .bold))
                }
                Text(word)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(marked ? .white : WO.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(marked ? WO.accent : WO.tileFill))
            .overlay(Capsule().stroke(WO.tileStroke, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }

    /// 文の単語（出現順・重複を除く）。チューザーの表示元。
    /// 登場人物の名前トークンは除外（綴り練習・復習＝同期に名前を侵入させない）。
    private var sentenceWords: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for token in item.tokens {
            if isHiddenName(token) { continue }
            let key = token.lowercased()
            if seen.insert(key).inserted {
                out.append(token)
            }
        }
        return out
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
        markedUnknown = []   // 次の文へ。マーカーはリセット（retry では保持）。
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
    @EnvironmentObject private var model: AppModel
    @State private var isPresented = false
    /// 開くたびに更新して、パーソナライズ例文の並び/友達選択を変える（決定論シードの種）。
    @State private var sessionSeed: UInt64 = 1

    var body: some View {
        Button {
            sessionSeed = sessionSeed &+ 0x9E37_79B9_7F4A_7C15
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
            // 同梱テンプレ＋登録済み Cast から1セッション分を解決して出題。
            // Cast 未登録/テンプレ無しはフォールバック（＝既定サンプル）に縮退する。
            let items = personalizedSession()
            if items.isEmpty {
                WordOrderingDemoView(onEnrollReviewWord: { model.enrollReviewWord($0) })
            } else {
                WordOrderingDemoView(items: items,
                                     hiddenReviewWords: castNameTokens(),
                                     onEnrollReviewWord: { model.enrollReviewWord($0) })
            }
        }
    }

    /// 同梱テンプレ→Cast 解決済み `SentenceItem` 列。テンプレが無ければ空（既定サンプルへ縮退）。
    private func personalizedSession() -> [SentenceItem] {
        let templates = PersonTemplateStore.loadBundled()
        guard !templates.isEmpty else { return [] }
        return PersonalizedSessionBuilder.build(
            templates: templates,
            cast: model.cast,
            count: 8,
            seed: sessionSeed
        )
    }

    /// 例文に出る登場人物の名前（ローマ字）。復習チップから除外して同期流出を防ぐ。
    private func castNameTokens() -> Set<String> {
        Set(model.cast.people.map(\.romaji).filter { !$0.isEmpty })
    }
}
#endif

#Preview {
    WordOrderingDemoView()
}
