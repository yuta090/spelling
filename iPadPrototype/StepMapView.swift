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

private struct StepMapTheme {
    let skyStops: [Gradient.Stop]
    let ground: Color
    let path: Color
    let goalEmoji: String
    let props: [StepMapProp]

    // 草原（小1相当の世界）。コース制を入れるときはここを差し替え可能にする。
    static let meadow = StepMapTheme(
        skyStops: [
            .init(color: Color(red: 0.66, green: 0.85, blue: 0.98), location: 0.00),
            .init(color: Color(red: 0.80, green: 0.92, blue: 1.00), location: 0.40),
            .init(color: Color(red: 0.86, green: 0.96, blue: 0.84), location: 0.80),
            .init(color: Color(red: 0.74, green: 0.90, blue: 0.66), location: 1.00),
        ],
        ground: Color(red: 0.62, green: 0.85, blue: 0.58),
        path: .white,
        goalEmoji: "🎈",
        props: [
            StepMapProp(emoji: "☁️", xFrac: 0.78, yFrac: 0.10, size: 60, opacity: 0.95),
            StepMapProp(emoji: "🌈", xFrac: 0.30, yFrac: 0.08, size: 56),
            StepMapProp(emoji: "🦋", xFrac: 0.42, yFrac: 0.22, size: 30),
            StepMapProp(emoji: "☁️", xFrac: 0.20, yFrac: 0.30, size: 52, opacity: 0.9),
            StepMapProp(emoji: "🐝", xFrac: 0.72, yFrac: 0.40, size: 26),
            StepMapProp(emoji: "🐤", xFrac: 0.30, yFrac: 0.55, size: 30),
            StepMapProp(emoji: "🌳", xFrac: 0.84, yFrac: 0.72, size: 46),
            StepMapProp(emoji: "🌻", xFrac: 0.16, yFrac: 0.80, size: 34),
            StepMapProp(emoji: "🌷", xFrac: 0.78, yFrac: 0.90, size: 30),
        ])
}

// MARK: - マップ本体

struct StepMapView: View {
    let steps: [WordStep]            // 昇順（[0]=下=スタート/ステップ1, 末尾=最新=空の上）
    let completedStepIDs: Set<String>
    let selectedStepID: String
    let language: AppLanguage
    let onSelect: (String) -> Void

    private let theme = StepMapTheme.meadow
    private let accent = Color(red: 0.16, green: 0.42, blue: 0.84)

    @State private var pulse = false

    // レイアウト定数（縦向き想定。横向き最適化は別タスク）。
    private let spacing: Double = 190
    private let groundPad: Double = 240
    private let skyPad: Double = 320

    private var orderedIDs: [String] { steps.map(\.id) }

    private var nodeStates: [StepMapLayout.NodeState] {
        StepMapLayout.nodeStates(orderedIDs: orderedIDs, completedToday: completedStepIDs, selectedID: selectedStepID)
    }

    private var currentID: String? {
        StepMapLayout.currentStepID(orderedIDs: orderedIDs, completedToday: completedStepIDs, selectedID: selectedStepID)
    }

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width)
            let n = steps.count
            // ステップが少なくても空がシートを満たすよう、最低でもビューポート高さは確保する。
            // 座標は下（地面）基準なので、高さを足したぶんは上（空）が広がるだけでノード位置は崩れない。
            let layoutH = StepMapLayout.contentHeight(count: n, spacing: spacing, groundPad: groundPad, skyPad: skyPad)
            let contentH = max(layoutH, Double(geo.size.height))
            let nodePoints = StepMapLayout.nodePoints(count: n, width: w, contentHeight: contentH, spacing: spacing, groundPad: groundPad)
            let pathPts = StepMapLayout.pathPoints(nodePoints: nodePoints, width: w, contentHeight: contentH, skyPad: skyPad)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .top) {
                        LinearGradient(stops: theme.skyStops, startPoint: .top, endPoint: .bottom)
                            .frame(width: CGFloat(w), height: CGFloat(contentH))

                        // 地面は背景レイヤー（ノードより先に描く＝ノードのラベルを覆わない）。
                        ground(width: w, contentHeight: contentH)

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
                        .position(x: CGFloat(w) * 0.5, y: CGFloat(skyPad) - 140)

                        // ノード
                        ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                            let p = cgPoint(nodePoints[idx])
                            Button {
                                onSelect(step.id)
                            } label: {
                                StepNodeView(
                                    title: step.title(language: language),
                                    count: step.words.count,
                                    state: nodeStates[idx],
                                    accent: accent,
                                    pulse: pulse,
                                    language: language
                                )
                            }
                            .buttonStyle(.plain)
                            .tapFeedback()
                            .position(p)
                            .id(step.id)
                        }

                        // 「いまここ」足元のアバター
                        if let cur = currentID, let idx = steps.firstIndex(where: { $0.id == cur }) {
                            let p = cgPoint(nodePoints[idx])
                            Text("🧒").font(.system(size: 52))
                                .position(x: p.x - 72, y: p.y + 14)
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
    }

    private func cgPoint(_ p: StepMapLayout.Point) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    private func decorations(width w: Double, height: Double) -> some View {
        ZStack {
            ForEach(theme.props) { prop in
                Text(prop.emoji)
                    .font(.system(size: prop.size))
                    .opacity(prop.opacity)
                    .position(x: CGFloat(w) * prop.xFrac, y: CGFloat(height) * prop.yFrac)
            }
        }
        .allowsHitTesting(false)
    }

    private func ground(width w: Double, contentHeight: Double) -> some View {
        ZStack {
            Ellipse().fill(theme.ground)
                .frame(width: CGFloat(w) * 1.4, height: 300)
                .position(x: CGFloat(w) * 0.5, y: CGFloat(contentHeight) - 20)
            Text(language.text(japanese: "スタート", english: "Start"))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(StepMapPalette.navy.opacity(0.75))
                .position(x: CGFloat(w) * 0.34, y: CGFloat(contentHeight) - 28)
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
                Image(systemName: "star.fill").font(.system(size: 46, weight: .black)).foregroundStyle(.white)
                Circle().stroke(accent.opacity(0.5), lineWidth: 5).frame(width: 132, height: 132)
                    .scaleEffect(pulse ? 1.12 : 0.96).opacity(pulse ? 0.2 : 0.7)
                Text("✨").font(.system(size: 26)).offset(x: 48, y: -46)
            }
            VStack(spacing: 3) {
                Text(language.text(japanese: "いまここ", english: "You're here"))
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
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
