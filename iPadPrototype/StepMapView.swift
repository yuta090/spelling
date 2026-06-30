import SwiftUI
import SpellingSyncCore

// 子ども側「ステップをえらぼう」を、下＝スタート→上にスクロールで空へ登る冒険マップで描く。
// 座標計算・状態判定は SpellingSyncCore.StepMapLayout（テスト済み）。ここは描画だけ。
//
// このPRの範囲（仕様 docs/step-map-and-courses-spec-2026-06-29.md のうち「ステップ選択メニュー」限定）:
// - 単一コース／WorldTheme は1種（草原）固定。コース切替・カメラステップはまだ入れない。

// MARK: - 配色・テーマ（単一・草原）

private enum StepMapPalette {
    static let navy  = Color(red: 0.10, green: 0.22, blue: 0.42)
    static let green = Color(red: 0.20, green: 0.58, blue: 0.24)
}

// どのテーマ背景の上でも白文字が読めるよう、軽い影を足す。
private extension View {
    func stepMapLegible() -> some View { shadow(color: .black.opacity(0.30), radius: 3, y: 1) }
}

// 点在する飾り（背景の世界観）。xFrac/yFrac は 0..1（yFrac 0=上＝空の高い所, 1=下＝スタート）。
private struct StepMapProp: Identifiable {
    let id = UUID()
    let emoji: String
    let xFrac: CGFloat
    let yFrac: CGFloat
    let size: CGFloat
    var opacity: Double = 1
}

// Core の SwiftUI 非依存 RGB を Color へ。
private extension Color {
    init(_ rgb: ThemeRGB) { self.init(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

private struct StepMapTheme {
    let skyStops: [Gradient.Stop]
    let ground: Color
    let path: Color
    let accent: Color
    let accentForeground: Color   // accent 上の文字/アイコン色（淡色テーマで白が読めないのを防ぐ）
    let goalEmoji: String
    let props: [StepMapProp]

    // Core `WorldTheme`（コースID で引いたテーマ）→ 描画用に変換する。
    // 配色・飾り・ゴール・アクセントを丸ごとコースの世界観に差し替える。
    init(_ w: WorldTheme) {
        skyStops = w.skyStops.map { .init(color: Color($0.color), location: $0.location) }
        ground = Color(w.ground)
        path = Color(w.path)
        accent = Color(w.accent)
        accentForeground = Color(w.accentForeground)
        goalEmoji = w.goalEmoji
        props = w.props.map {
            StepMapProp(emoji: $0.emoji,
                        xFrac: CGFloat($0.xFrac), yFrac: CGFloat($0.yFrac),
                        size: CGFloat($0.size), opacity: $0.opacity)
        }
    }
}

// MARK: - マップ本体

struct StepMapView: View {
    let steps: [WordStep]            // 昇順（[0]=下=スタート/ステップ1, 末尾=最新=空の上）
    let completedStepIDs: Set<String>
    let selectedStepID: String
    let language: AppLanguage
    let character: HomeRewardCharacter   // 「いまここ」足元に立つ＝子が今選んでいるなかま
    let courseID: String                 // アクティブコースID（"grade-3"/"eiken-g5"/"personal" …）でテーマを引く
    let onSelect: (String) -> Void

    // コースID由来のテーマ（未知IDは Core 側で既定＝草原にフォールバック）。
    private var theme: StepMapTheme { StepMapTheme(WorldTheme.theme(forCourseID: courseID)) }
    private var accent: Color { theme.accent }

    @State private var pulse = false
    // タップ後すぐ閉じず、選んだステップへ「ついた」演出を見せてから閉じる。
    // pendingID = 選択確定の途中（なかまがそのノードへ移動して点灯）。confirmPop = 到着のきらっと。
    @State private var pendingID: String?
    @State private var confirmPop = false
    // 演出途中で「とじる」やスワイプで閉じられたら、遅延中の確定/きらっとを取り消す（取り残し防止）。
    @State private var popWork: DispatchWorkItem?
    @State private var commitWork: DispatchWorkItem?

    private var orderedIDs: [String] { steps.map(\.id) }

    // タップ確定中は pendingID を「選択中」として扱う＝なかま・ノードがそのステップへ移って点灯する。
    private var effectiveSelectedID: String { pendingID ?? selectedStepID }

    private var nodeStates: [StepMapLayout.NodeState] {
        StepMapLayout.nodeStates(orderedIDs: orderedIDs, completedToday: completedStepIDs, selectedID: effectiveSelectedID)
    }

    private var currentID: String? {
        StepMapLayout.currentStepID(orderedIDs: orderedIDs, completedToday: completedStepIDs, selectedID: effectiveSelectedID)
    }

    // なかまの足元位置。確定中は完了済みステップでも必ず「選んだノード」へ寄り添わせる
    // （currentStepID は完了済みを current にしないため、ここで pendingID を優先する）。
    private var avatarStepID: String? { pendingID ?? currentID }

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width)
            let n = steps.count
            // 横向き（横長）ではノード間隔・上下余白を詰め、ジグザグを内側へ寄せる（Core が値を持つ）。
            let m = StepMapLayout.metrics(isLandscape: geo.size.width > geo.size.height)
            // ステップが少なくても空がシートを満たすよう、最低でもビューポート高さは確保する。
            // 座標は下（地面）基準なので、高さを足したぶんは上（空）が広がるだけでノード位置は崩れない。
            let layoutH = StepMapLayout.contentHeight(count: n, spacing: m.spacing, groundPad: m.groundPad, skyPad: m.skyPad)
            let contentH = max(layoutH, Double(geo.size.height))
            let nodePoints = StepMapLayout.nodePoints(count: n, width: w, contentHeight: contentH, spacing: m.spacing, groundPad: m.groundPad, leftFrac: m.leftFrac, rightFrac: m.rightFrac)
            let pathPts = StepMapLayout.pathPoints(nodePoints: nodePoints, width: w, contentHeight: contentH, skyPad: m.skyPad, leftFrac: m.leftFrac)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .top) {
                        LinearGradient(stops: theme.skyStops, startPoint: .top, endPoint: .bottom)
                            .frame(width: CGFloat(w), height: CGFloat(contentH))

                        // 地面は背景レイヤー（ノードより先に描く＝ノードのラベルを覆わない）。
                        ground(width: w, contentHeight: contentH, leftFrac: m.leftFrac)

                        decorations(width: w, height: contentH)

                        StepMapDottedPath(points: pathPts.map(cgPoint))
                            .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [2, 20]))
                            .foregroundStyle(theme.path.opacity(0.9))

                        // ゴール（つづく…）
                        VStack(spacing: 4) {
                            Text(theme.goalEmoji).font(.system(size: 50))
                            Text(language.text(japanese: "つづく…", english: "More…"))
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white).stepMapLegible()
                        }
                        .position(x: CGFloat(w) * 0.5, y: CGFloat(m.skyPad) - 140)

                        // ノード
                        ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                            let p = cgPoint(nodePoints[idx])
                            let isChosen = pendingID == step.id
                            Button {
                                chooseStep(step.id, proxy: proxy)
                            } label: {
                                StepNodeView(
                                    title: step.title(language: language),
                                    count: step.words.count,
                                    state: nodeStates[idx],
                                    accent: accent,
                                    accentForeground: theme.accentForeground,
                                    pulse: pulse,
                                    language: language
                                )
                            }
                            .buttonStyle(.plain)
                            .tapFeedback()
                            // 選んだノードだけ、到着の瞬間にぽよんと弾ませて閉じる前の合図にする。
                            .scaleEffect(isChosen && confirmPop ? 1.16 : 1)
                            .overlay {
                                if isChosen && confirmPop {
                                    Text("✨")
                                        .font(.system(size: 30))
                                        .offset(y: -54)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .zIndex(isChosen ? 1 : 0)
                            .position(p)
                            .id(step.id)
                        }

                        // 「いまここ」足元のアバター（子が今選んでいるなかま）
                        if let cur = avatarStepID, let idx = steps.firstIndex(where: { $0.id == cur }) {
                            let p = cgPoint(nodePoints[idx])
                            RewardCharacterAvatar(character: character)
                                .frame(width: 58, height: 58)
                                .stepMapLegible()
                                .position(x: p.x - 74, y: p.y + 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: CGFloat(w), height: CGFloat(contentH))
                }
                .onAppear {
                    guard let cur = currentID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation { proxy.scrollTo(cur, anchor: .center) }
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onDisappear {
            // 演出の余韻中に閉じられた場合に備え、遅延中の確定/きらっとを止める。
            popWork?.cancel()
            commitWork?.cancel()
        }
    }

    // タップ→すぐ閉じるのではなく、なかまが選んだステップへ歩いて「ついた」演出を見せてから閉じる。
    // ① pendingID をセット＝なかま/ノードがそのステップへ移って点灯（spring で気持ちよく）
    // ② 中央へスクロールして主役を見せる
    // ③ 到着のきらっと（confirmPop）→ 余韻を置いてから onSelect（モデル確定＋シート閉じ）
    private func chooseStep(_ id: String, proxy: ScrollViewProxy) {
        guard pendingID == nil else { return }   // 二度押し・連打を無視
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            pendingID = id
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            proxy.scrollTo(id, anchor: .center)
        }
        let pop = DispatchWorkItem {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) {
                confirmPop = true
            }
        }
        let commit = DispatchWorkItem {
            guard pendingID == id else { return }   // 途中で閉じられていたら確定しない
            onSelect(id)
        }
        popWork = pop
        commitWork = commit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: pop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95, execute: commit)
    }

    private func cgPoint(_ p: StepMapLayout.Point) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    private func decorations(width w: Double, height: Double) -> some View {
        // theme は計算プロパティで毎回作り直すため StepMapProp.id(UUID) は安定しない。
        // 配置スロットは固定なので enumerated の index を安定IDにして無駄な再生成/ちらつきを防ぐ。
        ZStack {
            ForEach(Array(theme.props.enumerated()), id: \.offset) { _, prop in
                Text(prop.emoji)
                    .font(.system(size: prop.size))
                    .opacity(prop.opacity)
                    .position(x: CGFloat(w) * prop.xFrac, y: CGFloat(height) * prop.yFrac)
            }
        }
        .allowsHitTesting(false)
    }

    private func ground(width w: Double, contentHeight: Double, leftFrac: Double) -> some View {
        ZStack {
            Ellipse().fill(theme.ground)
                .frame(width: CGFloat(w) * 1.4, height: 300)
                .position(x: CGFloat(w) * 0.5, y: CGFloat(contentHeight) - 20)
            // 「スタート」は一番下のノード（index 0 = leftFrac）と道のアンカーに合わせて置く。
            Text(language.text(japanese: "スタート", english: "Start"))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(StepMapPalette.navy.opacity(0.75))
                .position(x: CGFloat(w) * CGFloat(leftFrac), y: CGFloat(contentHeight) - 28)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - ノード1個

private struct StepNodeView: View {
    let title: String
    let count: Int
    let state: StepMapLayout.NodeState
    let accent: Color
    let accentForeground: Color
    let pulse: Bool
    let language: AppLanguage

    var body: some View {
        switch state {
        case .done:     doneNode
        case .current:  currentNode
        case .upcoming: upcomingNode
        }
    }

    private var doneNode: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(StepMapPalette.green).frame(width: 82, height: 82)
                    .shadow(color: StepMapPalette.green.opacity(0.35), radius: 10, y: 5)
                Image(systemName: "checkmark").font(.system(size: 36, weight: .black)).foregroundStyle(.white)
                Circle().stroke(.white.opacity(0.9), lineWidth: 4).frame(width: 62, height: 62)
            }
            VStack(spacing: 3) {
                Text(title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(.white).stepMapLegible()
                Text(language.text(japanese: "できた！", english: "Done!"))
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(.vertical, 3).padding(.horizontal, 10).background(StepMapPalette.green, in: Capsule())
            }
        }
    }

    private var currentNode: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.white).frame(width: 118, height: 118).shadow(color: accent.opacity(0.45), radius: 18, y: 8)
                Circle().fill(accent).frame(width: 102, height: 102)
                Image(systemName: "star.fill").font(.system(size: 46, weight: .black)).foregroundStyle(accentForeground)
                Circle().stroke(accent.opacity(0.5), lineWidth: 5).frame(width: 132, height: 132)
                    .scaleEffect(pulse ? 1.12 : 0.96).opacity(pulse ? 0.2 : 0.7)
                Text("✨").font(.system(size: 26)).offset(x: 48, y: -46)
            }
            VStack(spacing: 3) {
                Text(language.text(japanese: "いまここ", english: "You're here"))
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(accentForeground)
                    .padding(.vertical, 4).padding(.horizontal, 12).background(accent, in: Capsule())
                Text(title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white).stepMapLegible()
                countPill
            }
        }
    }

    private var upcomingNode: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.white.opacity(0.9)).frame(width: 78, height: 78)
                Circle().stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, dash: [6, 6])).frame(width: 78, height: 78)
                Image(systemName: "sparkles").font(.system(size: 28, weight: .bold)).foregroundStyle(accent.opacity(0.85))
            }
            VStack(spacing: 3) {
                Text(title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(.white).stepMapLegible()
                countPill
            }
        }
    }

    private var countPill: some View {
        Text(language.text(japanese: "\(count)こ", english: "\(count) words"))
            .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(StepMapPalette.navy)
            .padding(.vertical, 4).padding(.horizontal, 12).background(.white.opacity(0.92), in: Capsule())
    }
}

// MARK: - 点線の小道

private struct StepMapDottedPath: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for i in 1..<points.count {
            let prev = points[i - 1]
            let cur = points[i]
            let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
            p.addQuadCurve(to: cur, control: CGPoint(x: prev.x, y: mid.y))
        }
        return p
    }
}
