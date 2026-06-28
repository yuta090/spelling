import SwiftUI
import UIKit
import SpellingSyncCore

// 文づくり（並べ替え）の最小プレイ画面。
// 設計: docs/sentence-builder-design-2026-06-27.md
// ロジックは `SpellingSyncCore`（WordOrderingGenerator / WordOrderingGrader）に委譲し、
// この画面は提示と入力だけを担う（アプリ本体は薄く保つ方針）。
// まずは「触って確かめる」ための独立画面。未習語タップ→復習導線は次イテレーションで AppModel/SRS に接続する。

// MARK: - 配色（既存の温かいパレットに合わせる）


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

    /// このラウンドの1問（出題文＋それが復習注入された文か）。`isReview` はラウンド開始時に確定
    /// （以後の採点でモデルが変化してもバッジが揺れない＝round 内で安定）。
    private struct RoundEntry: Equatable {
        let item: SentenceItem
        let isReview: Bool
    }

    /// ID→文を解決するためのプール（base＋復習対象を含む、解決可能な全文）。
    private let items: [SentenceItem]
    /// このラウンドの通常出題（base）。`items` の部分集合でよい。既定は `items` 全体。
    private let baseItems: [SentenceItem]
    /// 「しらない ことば」を選んだときに復習へ積むコールバック（AppModel に依存させないため）。
    private let onEnrollReviewWord: (String) -> Void
    /// 復習チップに出してはいけない語（＝登場人物の名前）。英字のみ小文字化したキーで保持。
    /// 未成年実名を綴り練習・復習（→同期）に侵入させないためのガード。デフォルト空＝従来どおり。
    private let hiddenNameKeys: Set<String>
    /// 1ラウンドの出題順を組むコールバック（base のID列→出題順のID列）。
    /// AppModel が `ReviewQueue.composeRound` を呼び、間違えた文を追加問題として混ぜる。既定は素通し。
    private let composeRound: ([UUID]) -> [UUID]
    /// 文1問の初回正誤を復習キューに反映するコールバック（item.id, correct）。既定は noop。
    private let onGrade: (UUID, Bool) -> Void
    /// 1ラウンド完了の通知（ステップを進める）。既定は noop。
    private let onRoundComplete: () -> Void

    @StateObject private var speech = SpeechPlayer()
    /// タイルがトレイ↔解答欄を「飛んで」移動するための共有ネームスペース。
    @Namespace private var tileNS
    /// このラウンドの出題列（base＋復習注入を合成し、ラウンド開始時にスナップショットしたもの）。
    @State private var sequence: [RoundEntry] = []
    @State private var index = 0
    @State private var reshuffle = 0

    /// 正解列に置いたタイル（順序＝解答）。
    @State private var placed: [OrderingTile] = []
    /// まだ置いていないタイル。
    @State private var tray: [OrderingTile] = []
    @State private var grade: OrderingGrade?
    /// この問題で「しらない」と選んだ語（復習に積んだ＝マーカー表示）。
    @State private var markedUnknown: Set<String> = []
    /// このラウンドで既に採点済みの文ID（1文＝1回だけ復習キューへ反映＝初回正誤で評価）。
    @State private var gradedThisRound: Set<UUID> = []

    init(
        items: [SentenceItem] = WordOrderingSamples.make(),
        baseItems: [SentenceItem]? = nil,
        hiddenReviewWords: Set<String> = [],
        onEnrollReviewWord: @escaping (String) -> Void = { _ in },
        composeRound: @escaping ([UUID]) -> [UUID] = { $0 },
        onGrade: @escaping (UUID, Bool) -> Void = { _, _ in },
        onRoundComplete: @escaping () -> Void = {}
    ) {
        self.items = items
        self.baseItems = baseItems ?? items
        self.onEnrollReviewWord = onEnrollReviewWord
        self.hiddenNameKeys = Set(hiddenReviewWords.map(Self.nameKey))
        self.composeRound = composeRound
        self.onGrade = onGrade
        self.onRoundComplete = onRoundComplete
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

    /// 現在の1問（未構築/範囲外/空入力では nil）。本体は nil の間「じゅんびちゅう」を出す。
    private var currentEntry: RoundEntry? {
        sequence.indices.contains(index) ? sequence[index] : nil
    }

    private var item: SentenceItem? { currentEntry?.item }

    private var exercise: WordOrderingExercise? {
        guard let item else { return nil }
        return WordOrderingGenerator.make(from: item, seed: seed)
    }

    private var seed: UInt64 {
        UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9 &+ UInt64(truncatingIfNeeded: reshuffle)
    }

    private var isComplete: Bool { tray.isEmpty && !placed.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if currentEntry != nil {
                    playingContent
                } else {
                    // 出題が無い（空入力 / 構築前）。クラッシュさせず軽い待ち表示。
                    Text("じゅんびちゅう…")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(PuzzleTheme.bg.ignoresSafeArea())
            .navigationTitle("ぶんづくり")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
            .onAppear {
                if sequence.isEmpty { buildRound() }
                load()
            }
        }
    }

    private var playingContent: some View {
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
    }

    // MARK: 部品

    private var prompt: some View {
        VStack(spacing: 6) {
            if currentEntry?.isReview == true {
                // 復習として再出題された文。子に圧をかけない軽いマーク（評価語は使わない）。
                // 表示可否はラウンド開始時のスナップショット（currentEntry.isReview）なので採点で揺れない。
                Label("もういちど", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PuzzleTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(PuzzleTheme.hintFill))
                    .overlay(Capsule().stroke(PuzzleTheme.tileStroke, lineWidth: 1.5))
            }
            Text("にほんごを みて、ただしい じゅんに ならべよう")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(item?.ja ?? "")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// 解答スロット。置いたタイルをタップで戻せる。
    private var answerRow: some View {
        PuzzleFlowLayout(spacing: 10) {
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
                        .stroke(PuzzleTheme.slotStroke, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
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
        PuzzleFlowLayout(spacing: 10) {
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
            PuzzleTheme.haptic()
            let sentence = placed.map(\.text).joined(separator: " ")
            speech.speak(sentence, language: "en-US")
        } label: {
            Label("きいてみる", systemImage: "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.accent)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(Capsule().fill(PuzzleTheme.tileFill))
                .overlay(Capsule().stroke(PuzzleTheme.tileStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }

    private enum TileRole { case tray, placed }

    private func tileButton(_ tile: OrderingTile, role: TileRole) -> some View {
        Button {
            guard grade == nil else { return }
            PuzzleTheme.haptic()
            switch role {
            case .tray:
                move(tile, from: &tray, to: &placed)
            case .placed:
                move(tile, from: &placed, to: &tray)
            }
        } label: {
            Text(tile.text)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(PuzzleTheme.tileFill))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(PuzzleTheme.tileStroke, lineWidth: 2))
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
                        .foregroundStyle(PuzzleTheme.correct)
                } else {
                    VStack(spacing: 4) {
                        Label("ナイス チャレンジ！", systemImage: "flame.fill")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(PuzzleTheme.accent)
                        Text(grade.correctPositions > 0
                             ? "あと \(grade.total - grade.correctPositions)こ！ もういちど やってみよう"
                             : "だいじょうぶ、なんども やってみよう")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    // 不正解のときは「せいかいの文＋意味＋（あれば）文法解説」を1枚で見せる。
                    // 置いた（間違った）タイルはそのまま残し、その下に正解を出す。
                    // grammar が nil でも正解文・意味は出す（従来は正解文を見せていなかった欠落の修正）。
                    if let item {
                        AnswerExplanationCard(
                            explanation: SentenceFeedback.make(
                                item: item, submitted: placed.map(\.text), grade: grade
                            )
                        )
                    }
                }
                // 回答後に「しらない ことば」を選んで復習へ積む（並べ替えのタップとは衝突しない）。
                unknownWordChooser
                if grade.isCorrect {
                    PuzzlePrimaryButton(title: "つぎへ", tint: PuzzleTheme.accent, action: next)
                } else {
                    PuzzlePrimaryButton(title: "もういちど", tint: PuzzleTheme.retry, action: retry)
                }
            }
        } else {
            PuzzlePrimaryButton(title: "できた！", tint: isComplete ? PuzzleTheme.accent : Color.gray.opacity(0.4),
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
            PuzzleFlowLayout(spacing: 8) {
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
            PuzzleTheme.haptic()
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
            .foregroundStyle(marked ? .white : PuzzleTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(marked ? PuzzleTheme.accent : PuzzleTheme.tileFill))
            .overlay(Capsule().stroke(PuzzleTheme.tileStroke, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }

    /// 文の単語（出現順・重複を除く）。チューザーの表示元。
    /// 登場人物の名前トークンは除外（綴り練習・復習＝同期に名前を侵入させない）。
    private var sentenceWords: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for token in item?.tokens ?? [] {
            if isHiddenName(token) { continue }
            let key = token.lowercased()
            if seen.insert(key).inserted {
                out.append(token)
            }
        }
        return out
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

    /// 1ラウンドの出題列を組む。base（このラウンドの通常出題）のID列を `composeRound` に渡し、
    /// 返ったID順を **プール `items`** で文に解決して `RoundEntry` 化する。
    /// `isReview` は「base に無い＝復習として注入された文」をラウンド開始時に確定（以後揺れない）。
    /// プールに無いIDは解決できず落ちる（呼び出し側は復習対象を解決できる `items` を渡す契約）。
    private func buildRound() {
        let pool = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let baseSet = Set(baseItems.map(\.id))
        let ordered = composeRound(baseItems.map(\.id)).compactMap { id -> RoundEntry? in
            guard let sentence = pool[id] else { return nil }
            return RoundEntry(item: sentence, isReview: !baseSet.contains(id))
        }
        // 解決できる出題が無ければ base をそのまま（安全網）。それも空なら空ラウンド（本体は待ち表示）。
        sequence = ordered.isEmpty ? baseItems.map { RoundEntry(item: $0, isReview: false) } : ordered
        index = 0
        gradedThisRound = []
    }

    private func load() {
        guard let ex = exercise else { return }
        placed = []
        tray = ex.scrambledTiles
        grade = nil
    }

    private func check() {
        guard let item, let ex = exercise else { return }
        let result = WordOrderingGrader.grade(submitted: placed.map(\.text), answer: ex.answer)
        grade = result
        // 1文＝1回だけ復習キューへ反映（初回の正誤で評価。retry の再採点では二重反映しない）。
        if gradedThisRound.insert(item.id).inserted {
            onGrade(item.id, result.isCorrect)
        }
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
        markedUnknown = []   // 次の文へ。マーカーはリセット（retry では保持）。
        reshuffle = 0
        if index + 1 >= sequence.count {
            // ラウンド完了 → ステップを進め、新しいラウンドを組み直す（復習の再注入）。
            onRoundComplete()
            buildRound()
        } else {
            index += 1
        }
        load()
    }
}


// MARK: - DEBUG 起動ボタン（製品UIには出さない）

#if DEBUG
/// 文づくり（並べ替え）の試遊画面を開く DEBUG 限定ボタン。`RootView` に overlay で差し込む。
struct WordOrderingDebugLauncher: View {
    @EnvironmentObject private var model: AppModel
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
            // サンプル文の試遊。「しらない ことば」を子の復習へ積む（既存語彙にあれば無視）＋
            // 間違えた文を ReviewQueue で今後のラウンドに追加問題として混ぜる。
            // 本物テンプレ＋Cast の再生は RealContentSession 側。
            WordOrderingDemoView(
                onEnrollReviewWord: { model.enrollReviewWord($0) },
                composeRound: { model.composeGrammarRound(base: $0) },
                onGrade: { model.recordGrammarResult(itemID: $0, correct: $1) },
                onRoundComplete: { model.advanceGrammarRound() }
            )
        }
    }
}
#endif

#Preview {
    WordOrderingDemoView()
}
