import SwiftUI

// MARK: - モデル

enum StepState { case done, current, upcoming }
enum StepKind  { case word, camera }   // word=単語練習(丸) / camera=カメラ取り込み(角丸四角)

struct StepNode: Identifiable {
    let id: Int            // 1 = 地上(スタート寄り)、大きいほど世界の上
    let title: String
    let count: Int
    let state: StepState
    let kind: StepKind
    let buddy: String?
}

// MARK: - ワールドテーマ（学年ごとに「別世界」にする）

// 点在する飾り（背景の世界観をつくる）。xFrac/yFrac は 0..1（yFrac 0=上＝世界の高い所, 1=下＝スタート）。
struct Prop: Identifiable {
    let id = UUID()
    let emoji: String
    let xFrac: CGFloat
    let yFrac: CGFloat
    let size: CGFloat
    var opacity: Double = 1
}

// コースごとの世界観。空のグラデ・地面色・小道色・ゴール・飾りを差し替える。
// 「全部が宇宙に行くだけ」にしないための核。学年が上がるほど高い世界へ＝小1草原→…→小6宇宙。
struct WorldTheme {
    let skyStops: [Gradient.Stop]   // 上→下
    let ground: Color
    let path: Color
    let goalEmoji: String
    let goalLabel: String
    let props: [Prop]
}

extension WorldTheme {
    // 小1：そうげん（草原）
    static let meadow = WorldTheme(
        skyStops: [
            .init(color: Color(red: 0.66, green: 0.85, blue: 0.98), location: 0.00),
            .init(color: Color(red: 0.80, green: 0.92, blue: 1.00), location: 0.40),
            .init(color: Color(red: 0.86, green: 0.96, blue: 0.84), location: 0.80),
            .init(color: Color(red: 0.74, green: 0.90, blue: 0.66), location: 1.00),
        ],
        ground: Color(red: 0.62, green: 0.85, blue: 0.58),
        path: .white,
        goalEmoji: "🎈", goalLabel: "つづく…",
        props: [
            Prop(emoji: "☁️", xFrac: 0.78, yFrac: 0.10, size: 60, opacity: 0.95),
            Prop(emoji: "🌈", xFrac: 0.30, yFrac: 0.08, size: 56),
            Prop(emoji: "🦋", xFrac: 0.42, yFrac: 0.22, size: 30),
            Prop(emoji: "☁️", xFrac: 0.20, yFrac: 0.30, size: 52, opacity: 0.9),
            Prop(emoji: "🐝", xFrac: 0.72, yFrac: 0.40, size: 26),
            Prop(emoji: "🐤", xFrac: 0.30, yFrac: 0.55, size: 30),
            Prop(emoji: "🌳", xFrac: 0.84, yFrac: 0.72, size: 46),
            Prop(emoji: "🌻", xFrac: 0.16, yFrac: 0.80, size: 34),
            Prop(emoji: "🌷", xFrac: 0.78, yFrac: 0.90, size: 30),
        ])

    // 小2：うみべ（海辺）
    static let seaside = WorldTheme(
        skyStops: [
            .init(color: Color(red: 0.55, green: 0.80, blue: 0.95), location: 0.00),
            .init(color: Color(red: 0.70, green: 0.88, blue: 0.98), location: 0.35),
            .init(color: Color(red: 0.40, green: 0.74, blue: 0.88), location: 0.70),
            .init(color: Color(red: 0.95, green: 0.89, blue: 0.68), location: 1.00),
        ],
        ground: Color(red: 0.96, green: 0.90, blue: 0.70),
        path: .white,
        goalEmoji: "🏝️", goalLabel: "つづく…",
        props: [
            Prop(emoji: "☁️", xFrac: 0.74, yFrac: 0.10, size: 56, opacity: 0.95),
            Prop(emoji: "⛵️", xFrac: 0.30, yFrac: 0.20, size: 46),
            Prop(emoji: "🐠", xFrac: 0.70, yFrac: 0.40, size: 30),
            Prop(emoji: "🌊", xFrac: 0.20, yFrac: 0.50, size: 40),
            Prop(emoji: "🐟", xFrac: 0.78, yFrac: 0.58, size: 26),
            Prop(emoji: "🐚", xFrac: 0.18, yFrac: 0.82, size: 30),
            Prop(emoji: "🦀", xFrac: 0.82, yFrac: 0.90, size: 30),
        ])

    // 小3：もり（森）
    static let forest = WorldTheme(
        skyStops: [
            .init(color: Color(red: 0.62, green: 0.82, blue: 0.92), location: 0.00),
            .init(color: Color(red: 0.50, green: 0.74, blue: 0.56), location: 0.40),
            .init(color: Color(red: 0.30, green: 0.56, blue: 0.34), location: 0.80),
            .init(color: Color(red: 0.22, green: 0.46, blue: 0.26), location: 1.00),
        ],
        ground: Color(red: 0.28, green: 0.50, blue: 0.30),
        path: Color(red: 0.95, green: 0.92, blue: 0.78),
        goalEmoji: "🏕️", goalLabel: "つづく…",
        props: [
            Prop(emoji: "🌲", xFrac: 0.82, yFrac: 0.12, size: 50),
            Prop(emoji: "🦉", xFrac: 0.28, yFrac: 0.22, size: 32),
            Prop(emoji: "🍃", xFrac: 0.66, yFrac: 0.34, size: 28, opacity: 0.9),
            Prop(emoji: "🌲", xFrac: 0.16, yFrac: 0.46, size: 46),
            Prop(emoji: "🍄", xFrac: 0.74, yFrac: 0.60, size: 28),
            Prop(emoji: "🦊", xFrac: 0.22, yFrac: 0.74, size: 34),
            Prop(emoji: "🐿️", xFrac: 0.80, yFrac: 0.88, size: 28),
        ])

    // 小4：やま（山・雪）
    static let mountain = WorldTheme(
        skyStops: [
            .init(color: Color(red: 0.85, green: 0.93, blue: 1.00), location: 0.00),
            .init(color: Color(red: 0.70, green: 0.84, blue: 0.95), location: 0.40),
            .init(color: Color(red: 0.64, green: 0.72, blue: 0.82), location: 0.80),
            .init(color: Color(red: 0.56, green: 0.63, blue: 0.73), location: 1.00),
        ],
        ground: Color(red: 0.64, green: 0.70, blue: 0.80),
        path: .white,
        goalEmoji: "🚩", goalLabel: "ちょうじょう",
        props: [
            Prop(emoji: "🏔️", xFrac: 0.76, yFrac: 0.12, size: 56),
            Prop(emoji: "❄️", xFrac: 0.30, yFrac: 0.18, size: 26),
            Prop(emoji: "☁️", xFrac: 0.20, yFrac: 0.34, size: 50, opacity: 0.9),
            Prop(emoji: "🦅", xFrac: 0.72, yFrac: 0.46, size: 30),
            Prop(emoji: "🌲", xFrac: 0.18, yFrac: 0.66, size: 40),
            Prop(emoji: "🐐", xFrac: 0.80, yFrac: 0.84, size: 32),
            Prop(emoji: "🪨", xFrac: 0.22, yFrac: 0.90, size: 30),
        ])

    // 小6：うちゅう（宇宙）＝最後に到達する世界
    static let space = WorldTheme(
        skyStops: [
            .init(color: Color(red: 0.05, green: 0.06, blue: 0.20), location: 0.00),
            .init(color: Color(red: 0.10, green: 0.14, blue: 0.34), location: 0.40),
            .init(color: Color(red: 0.20, green: 0.26, blue: 0.50), location: 0.80),
            .init(color: Color(red: 0.32, green: 0.42, blue: 0.64), location: 1.00),
        ],
        ground: Color(red: 0.22, green: 0.26, blue: 0.46),
        path: .white,
        goalEmoji: "🚀", goalLabel: "つづく…",
        props: [
            Prop(emoji: "🪐", xFrac: 0.78, yFrac: 0.10, size: 46),
            Prop(emoji: "⭐️", xFrac: 0.25, yFrac: 0.13, size: 26),
            Prop(emoji: "✦", xFrac: 0.50, yFrac: 0.08, size: 22, opacity: 0.9),
            Prop(emoji: "🌙", xFrac: 0.20, yFrac: 0.30, size: 44),
            Prop(emoji: "☄️", xFrac: 0.74, yFrac: 0.42, size: 34),
            Prop(emoji: "✦", xFrac: 0.40, yFrac: 0.56, size: 18, opacity: 0.85),
            Prop(emoji: "🛸", xFrac: 0.78, yFrac: 0.70, size: 36),
            Prop(emoji: "⭐️", xFrac: 0.22, yFrac: 0.86, size: 24),
        ])

    // 英検5級：きいろの世界（太陽・お日さま）
    static let sun = WorldTheme(
        skyStops: [
            .init(color: Color(red: 1.00, green: 0.92, blue: 0.62), location: 0.00),
            .init(color: Color(red: 1.00, green: 0.86, blue: 0.50), location: 0.40),
            .init(color: Color(red: 1.00, green: 0.82, blue: 0.46), location: 0.80),
            .init(color: Color(red: 0.98, green: 0.76, blue: 0.42), location: 1.00),
        ],
        ground: Color(red: 0.98, green: 0.80, blue: 0.46),
        path: .white,
        goalEmoji: "🏅", goalLabel: "つづく…",
        props: [
            Prop(emoji: "☀️", xFrac: 0.76, yFrac: 0.10, size: 58),
            Prop(emoji: "🦋", xFrac: 0.28, yFrac: 0.22, size: 30),
            Prop(emoji: "☁️", xFrac: 0.20, yFrac: 0.34, size: 48, opacity: 0.85),
            Prop(emoji: "🐥", xFrac: 0.72, yFrac: 0.48, size: 30),
            Prop(emoji: "🌼", xFrac: 0.18, yFrac: 0.74, size: 32),
            Prop(emoji: "🌻", xFrac: 0.82, yFrac: 0.88, size: 36),
        ])
}

struct Course: Identifiable {
    let id: String
    let childName: String   // 子に見せるやさしい名前
    let emoji: String
    let accent: Color
    let seed: Int
    let theme: WorldTheme
}

// 子画面では既定で「親が設定した1コース」だけを表示（切り替えUIは出さない）。
// 親の設定画面で「子どもにも選ばせる」をONにすると、許可コースの中で子も切り替え可能になる。
let currentCourse = Course(id: "g1", childName: "小1のたび", emoji: "🎒",
                           accent: Color(red: 0.16, green: 0.42, blue: 0.84), seed: 1, theme: .meadow)

// 親が「子にも選ばせる」を許可したときに、子が選べるコース群。
// 学年ごとに世界（theme）が違う＝小1草原→小2海辺→小3森→小4山→小6宇宙、英検5は太陽の世界。
let allowedCourses: [Course] = [
    currentCourse,
    Course(id: "g2", childName: "小2のたび", emoji: "🐚", accent: Color(red: 0.10, green: 0.60, blue: 0.74), seed: 2, theme: .seaside),
    Course(id: "g3", childName: "小3のたび", emoji: "🌲", accent: Color(red: 0.20, green: 0.58, blue: 0.30), seed: 3, theme: .forest),
    Course(id: "g4", childName: "小4のたび", emoji: "🏔️", accent: Color(red: 0.36, green: 0.46, blue: 0.66), seed: 4, theme: .mountain),
    Course(id: "g6", childName: "小6のたび", emoji: "🚀", accent: Color(red: 0.48, green: 0.40, blue: 0.86), seed: 6, theme: .space),
    Course(id: "e5", childName: "きいろのたび", emoji: "🏅", accent: Color(red: 0.95, green: 0.55, blue: 0.18), seed: 9, theme: .sun),
]

// ステップ地図はこの配列から座標を計算して描く＝データ駆動。
// 途中にカメラ取り込みステップが挿入されても、配列が変わるだけで自動的に並び直す。
func makeSteps(for c: Course) -> [StepNode] {
    let buddies = ["🦊", "🦋", "🐤", "🐢", "🐰", "🦉"]
    var out: [StepNode] = []
    var id = 0
    func add(_ title: String, _ count: Int, _ state: StepState, _ kind: StepKind, buddyEvery: Bool = false) {
        id += 1
        out.append(StepNode(id: id, title: title, count: count, state: state, kind: kind,
                            buddy: buddyEvery ? buddies[(id + c.seed) % buddies.count] : nil))
    }
    add("ステップ 1", 7, .done, .word, buddyEvery: true)
    add("ステップ 2", 8, .done, .word)
    add("ステップ 3", 6, .done, .word)
    add("ステップ 4", 9, .current, .word, buddyEvery: true)   // ← いまここ
    add("カメラステップ", 5, .upcoming, .camera)              // ← 途中に挿入されたカメラ取り込み
    add("ステップ 5", 10, .upcoming, .word, buddyEvery: true)
    add("ステップ 6", 5, .upcoming, .word)
    add("ステップ 7", 6, .upcoming, .word, buddyEvery: true)
    add("カメラステップ", 4, .upcoming, .camera)
    add("ステップ 8", 7, .upcoming, .word)
    add("ステップ 9", 8, .upcoming, .word, buddyEvery: true)
    add("ステップ 10", 9, .upcoming, .word)
    return out
}

// MARK: - 配色

enum Palette {
    static let navy   = Color(red: 0.10, green: 0.22, blue: 0.42)
    static let green  = Color(red: 0.20, green: 0.58, blue: 0.24)
    static let camera = Color(red: 0.92, green: 0.45, blue: 0.20)   // カメラ系アクセント(オレンジ)
}

// どのテーマの上でも白文字が読めるよう、軽い影を足す
extension View {
    func legible() -> some View { self.shadow(color: .black.opacity(0.30), radius: 3, y: 1) }
}

// MARK: - ルート

struct StepMapView: View {
    // 親の設定画面のトグル相当。false=表示のみ / true=子も切り替え可。
    // ※プロトタイプでは「学年ごとに世界が変わる」のを見せるため true にしてある。
    private let childCanSwitch = true
    @State private var course = currentCourse
    @State private var pulse = false

    private let spacing: CGFloat = 190
    private let groundPad: CGFloat = 240
    private let skyPad: CGFloat = 320

    private var steps: [StepNode] { makeSteps(for: course) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let n = steps.count
            let contentHeight = groundPad + skyPad + CGFloat(n - 1) * spacing

            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        ZStack(alignment: .top) {
                            skyBackground(height: contentHeight, width: w)
                            decorations(width: w, height: contentHeight)

                            DottedPath(points: pathPoints(width: w, contentHeight: contentHeight))
                                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [2, 20]))
                                .foregroundStyle(course.theme.path.opacity(0.9))

                            VStack(spacing: 4) {
                                Text(course.theme.goalEmoji).font(.system(size: 50))
                                Text(course.theme.goalLabel).font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white).legible()
                            }
                            .position(x: w * 0.5, y: skyPad - 140)

                            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                                let p = nodePoint(idx, width: w, contentHeight: contentHeight)
                                NodeView(step: step, pulse: pulse, accent: course.accent)
                                    .position(p)
                                    .id(step.id)
                                if let buddy = step.buddy {
                                    Text(buddy).font(.system(size: 38))
                                        .position(x: p.x + 74, y: p.y - 4)
                                }
                            }

                            if let cur = steps.firstIndex(where: { $0.state == .current }) {
                                let p = nodePoint(cur, width: w, contentHeight: contentHeight)
                                Text("🧒").font(.system(size: 54))
                                    .position(x: p.x - 72, y: p.y + 14)
                            }

                            ground(width: w, contentHeight: contentHeight)
                        }
                        .frame(width: w, height: contentHeight)
                    }
                    .onAppear {
                        if let cur = steps.first(where: { $0.state == .current }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation { proxy.scrollTo(cur.id, anchor: .center) }
                            }
                        }
                    }
                }

                topBar(width: w)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: 位置計算

    private func nodePoint(_ i: Int, width w: CGFloat, contentHeight: CGFloat) -> CGPoint {
        let x = (i % 2 == 0) ? w * 0.34 : w * 0.66
        let y = contentHeight - groundPad - CGFloat(i) * spacing
        return CGPoint(x: x, y: y)
    }

    private func pathPoints(width w: CGFloat, contentHeight: CGFloat) -> [CGPoint] {
        var pts: [CGPoint] = [CGPoint(x: w * 0.34, y: contentHeight - 110)]
        for i in 0..<steps.count { pts.append(nodePoint(i, width: w, contentHeight: contentHeight)) }
        pts.append(CGPoint(x: w * 0.5, y: skyPad - 110))
        return pts
    }

    // MARK: 上部バー（おうちボタン＋コース表示/切替）

    private func topBar(width w: CGFloat) -> some View {
        HStack(spacing: 12) {
            // ホームに戻る
            Button(action: {}) {
                ZStack {
                    Circle().fill(.white).frame(width: 62, height: 62)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    Image(systemName: "house.fill")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(Palette.navy)
                }
            }

            Spacer()

            Text("ステップをえらぼう")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.navy)
                .padding(.vertical, 9).padding(.horizontal, 18)
                .background(.white.opacity(0.85), in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            Spacer()

            // コース表示。既定は表示のみ。親が許可(childCanSwitch)したときだけメニューで切替可。
            if childCanSwitch {
                Menu {
                    ForEach(allowedCourses) { c in
                        Button { withAnimation { course = c } } label: {
                            Label("\(c.emoji) \(c.childName)", systemImage: course.id == c.id ? "checkmark" : "")
                        }
                    }
                } label: { courseChip(showChevron: true) }
            } else {
                courseChip(showChevron: false)
            }
        }
        .padding(.horizontal, 22).padding(.top, 22)
    }

    private func courseChip(showChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Text(course.emoji).font(.system(size: 20))
            Text(course.childName)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            if showChevron {
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .black)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 15)
        .background(course.accent, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
    }

    // MARK: 背景（テーマごとに別世界）

    private func skyBackground(height: CGFloat, width w: CGFloat) -> some View {
        LinearGradient(stops: course.theme.skyStops, startPoint: .top, endPoint: .bottom)
            .frame(width: w, height: height)
    }

    private func decorations(width w: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(course.theme.props) { prop in
                Text(prop.emoji)
                    .font(.system(size: prop.size))
                    .opacity(prop.opacity)
                    .position(x: w * prop.xFrac, y: height * prop.yFrac)
            }
        }
    }

    private func ground(width w: CGFloat, contentHeight: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(course.theme.ground)
                .frame(width: w * 1.4, height: 300)
                .position(x: w * 0.5, y: contentHeight - 20)
            Text("スタート").font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.navy.opacity(0.75))
                .position(x: w * 0.34, y: contentHeight - 28)
        }
    }
}

// MARK: - ノード

struct NodeView: View {
    let step: StepNode
    let pulse: Bool
    let accent: Color

    var body: some View {
        if step.kind == .camera { cameraNode } else { wordNode }
    }

    // 単語練習＝丸ノード
    @ViewBuilder private var wordNode: some View {
        switch step.state {
        case .done:
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Palette.green).frame(width: 82, height: 82)
                        .shadow(color: Palette.green.opacity(0.35), radius: 10, y: 5)
                    Image(systemName: "checkmark").font(.system(size: 36, weight: .black)).foregroundStyle(.white)
                    Circle().stroke(.white.opacity(0.9), lineWidth: 4).frame(width: 62, height: 62)
                }
                titleLabel(step.title, badge: "できた！", badgeColor: Palette.green)
            }
        case .current:
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(.white).frame(width: 118, height: 118).shadow(color: accent.opacity(0.45), radius: 18, y: 8)
                    Circle().fill(accent).frame(width: 102, height: 102)
                    Image(systemName: "star.fill").font(.system(size: 46, weight: .black)).foregroundStyle(.white)
                    Circle().stroke(accent.opacity(0.5), lineWidth: 5).frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.12 : 0.96).opacity(pulse ? 0.2 : 0.7)
                    Text("✨").font(.system(size: 26)).offset(x: 48, y: -46)
                }
                currentLabel
            }
        case .upcoming:
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(.white.opacity(0.9)).frame(width: 78, height: 78)
                    Circle().stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, dash: [6, 6])).frame(width: 78, height: 78)
                    Image(systemName: "sparkles").font(.system(size: 28, weight: .bold)).foregroundStyle(accent.opacity(0.85))
                }
                VStack(spacing: 3) {
                    Text(step.title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(.white).legible()
                    countPill
                }
            }
        }
    }

    // カメラ取り込み＝角丸四角ノード（活動の種類が一目で違う）
    @ViewBuilder private var cameraNode: some View {
        let isCurrent = step.state == .current
        let isDone = step.state == .done
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(isDone ? Palette.green : (isCurrent ? Palette.camera : .white.opacity(0.92)))
                    .frame(width: isCurrent ? 112 : 88, height: isCurrent ? 112 : 88)
                    .shadow(color: Palette.camera.opacity(0.35), radius: 12, y: 6)
                if step.state == .upcoming {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Palette.camera.opacity(0.8), style: StrokeStyle(lineWidth: 4, dash: [6, 6]))
                        .frame(width: 88, height: 88)
                }
                Image(systemName: "camera.fill")
                    .font(.system(size: isCurrent ? 40 : 32, weight: .black))
                    .foregroundStyle(step.state == .upcoming ? Palette.camera : .white)
                if isCurrent {
                    RoundedRectangle(cornerRadius: 30).stroke(Palette.camera.opacity(0.5), lineWidth: 5)
                        .frame(width: 128, height: 128).scaleEffect(pulse ? 1.1 : 0.96).opacity(pulse ? 0.2 : 0.7)
                }
            }
            VStack(spacing: 3) {
                if isCurrent {
                    Text("いまここ").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.vertical, 4).padding(.horizontal, 12).background(Palette.camera, in: Capsule())
                }
                Text("しゃしんをとる").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white).legible()
                Text("カメラ").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(.vertical, 3).padding(.horizontal, 10).background(Palette.camera, in: Capsule())
            }
        }
    }

    private var currentLabel: some View {
        VStack(spacing: 3) {
            Text("いまここ").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .padding(.vertical, 4).padding(.horizontal, 12).background(accent, in: Capsule())
            Text(step.title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white).legible()
            countPill
        }
    }

    private func titleLabel(_ title: String, badge: String, badgeColor: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundStyle(.white).legible()
            Text(badge).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .padding(.vertical, 3).padding(.horizontal, 10).background(badgeColor, in: Capsule())
        }
    }

    private var countPill: some View {
        Text("\(step.count)こ")
            .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Palette.navy)
            .padding(.vertical, 4).padding(.horizontal, 12).background(.white.opacity(0.92), in: Capsule())
    }
}

// MARK: - 点線パス

struct DottedPath: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for i in 1..<points.count {
            let prev = points[i-1]; let cur = points[i]
            let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
            p.addQuadCurve(to: cur, control: CGPoint(x: prev.x, y: mid.y))
        }
        return p
    }
}

// MARK: - App

@main
struct StepMapSampleApp: App {
    var body: some Scene { WindowGroup { StepMapView() } }
}
