import SwiftUI
import UIKit

// ことばパズル共通UI基盤。
// ぶんづくり / あなうめ / きいてあなうめ / おとをきいてえらぶ … 全形式で同じ見た目言語を使う。
// 以前は各 View が同一値のパレット（WO/CZ/LC/WL/MX）と bigButton / FlowLayout を個別に複製していた。
// それらをここに一本化し、PuzzleSessionView と各試遊 View が共有する。
// 設計: docs/kotoba-puzzle-spec-2026-06-28.md
//
// 演出方針（子ども側＝doer）: 大きく・可愛く・即フィードバック。温かいクリーム＋オレンジの
// 配色を軸に、白カードの奥行き・正誤の手触り（緑ポップ/赤シェイク）・星バーストで「ごほうび感」を出す。
// iOS 16.4 ターゲットのため iOS17専用API（PhaseAnimator/symbolEffect/2引数onChange）は使わない。

// MARK: - 配色（温かいクリーム＋オレンジ）

enum PuzzleTheme {
    static let ink = Color(red: 0.45, green: 0.28, blue: 0.08)
    static let tileFill = Color(red: 1.0, green: 0.97, blue: 0.86)
    static let tileStroke = Color(red: 0.95, green: 0.73, blue: 0.34)
    static let slotStroke = Color(red: 0.90, green: 0.82, blue: 0.66)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let correct = Color(red: 0.30, green: 0.62, blue: 0.28)
    static let correctFill = Color(red: 0.38, green: 0.72, blue: 0.34)
    static let retry = Color(red: 0.84, green: 0.36, blue: 0.08)
    static let wrongFill = Color(red: 0.90, green: 0.42, blue: 0.30)
    static let bg = Color(red: 1.0, green: 0.99, blue: 0.95)
    static let hintFill = Color(red: 1.0, green: 0.98, blue: 0.90)

    /// ボタンに使う「上が明るい」やわらかな縦グラデ。
    static func buttonGradient(_ base: Color) -> LinearGradient {
        LinearGradient(colors: [base.opacity(0.92), base],
                       startPoint: .top, endPoint: .bottom)
    }

    @MainActor
    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - シェイク（不正解で左右にフルフル）

/// `amount` を 0→1 にアニメートすると、左右に `shakes` 回ゆれて中央に戻る。
struct PuzzleShakeEffect: GeometryEffect {
    var amount: CGFloat
    var travel: CGFloat = 9
    var shakes: CGFloat = 3

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(amount * .pi * shakes), y: 0))
    }
}

// MARK: - 白カード（出題文などを「浮いた紙」に）

extension View {
    /// やわらかい影＋角丸の白カード。出題文や設問領域を一段持ち上げる。
    func puzzleCard(cornerRadius: CGFloat = 24, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: PuzzleTheme.ink.opacity(0.12), radius: 14, x: 0, y: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PuzzleTheme.tileStroke.opacity(0.35), lineWidth: 1.5)
            )
    }
}

// MARK: - 大ボタン（はじめる / つぎへ / もういちど 等）

struct PuzzlePrimaryButton: View {
    let title: String
    var tint: Color = PuzzleTheme.accent
    let action: () -> Void

    @State private var burst = 0

    var body: some View {
        Button {
            burst += 1
            action()
        } label: {
            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 21)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(PuzzleTheme.buttonGradient(tint))
                        .shadow(color: tint.opacity(0.45), radius: 11, x: 0, y: 7)
                )
                .overlay(
                    // 上ぶちの軽いハイライトでぷっくり見せる
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.40), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
        .tapBurst(trigger: burst, reach: 1.25)
    }
}

// MARK: - フィードバック見出し（せいかい / ナイス チャレンジ）

struct PuzzleVerdictLabel: View {
    let isCorrect: Bool
    @State private var pop = false

    var body: some View {
        label
            // 正解は小さく出てバネで弾けて大きくなる（ごほうび感）。不正解はそのまま。
            .scaleEffect(isCorrect ? (pop ? 1.0 : 0.4) : 1.0)
            .onAppear {
                guard isCorrect else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.42)) { pop = true }
            }
    }

    @ViewBuilder private var label: some View {
        if isCorrect {
            Label("やったね！ せいかい！", systemImage: "star.fill")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.correct)
        } else {
            Label("ナイス チャレンジ！", systemImage: "flame.fill")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.accent)
        }
    }
}

// MARK: - 形式バッジ（ならべかえ / あなうめ …）

struct PuzzleFormatBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(PuzzleTheme.buttonGradient(PuzzleTheme.accent))
                    .shadow(color: PuzzleTheme.accent.opacity(0.35), radius: 5, x: 0, y: 3)
            )
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 「きいてみる」カプセルボタン（音声再生）

struct PuzzleListenButton: View {
    var title: String = "きいてみる"
    let action: () -> Void

    /// 「押してね」と気づけるよう、待機中はゆっくり脈打つ。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var burst = 0

    var body: some View {
        Button {
            PuzzleTheme.haptic()
            burst += 1
            action()
        } label: {
            Label(title, systemImage: "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.accent)
                .padding(.horizontal, 26).padding(.vertical, 14)
                .background(
                    Capsule().fill(PuzzleTheme.tileFill)
                        .shadow(color: PuzzleTheme.accent.opacity(0.22), radius: 7, x: 0, y: 4)
                )
                .overlay(Capsule().stroke(PuzzleTheme.tileStroke, lineWidth: 2.5))
                .scaleEffect(pulse ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
        .tapBurst(trigger: burst, reach: 0.9)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - 選択肢ボタン（穴埋め・リスニングで共通）

/// 選択肢の見た目状態。回答後に「自分が選んだ・正解・はずれ」を色と動きで伝える。
enum PuzzleOptionResult: Equatable {
    case idle           // 未回答（押せる）
    case correctChosen  // 自分が選んで正解（緑にポップ＋✓）
    case wrongChosen    // 自分が選んではずれ（赤くシェイク＋✗）
    case revealCorrect  // はずれたとき、正解を緑で開示
    case dimmed         // 回答後の関係ない選択肢（うすく）
}

struct PuzzleOptionButton: View {
    let text: String
    var result: PuzzleOptionResult = .idle
    var action: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake: CGFloat = 0
    @State private var pop: CGFloat = 1
    @State private var shine: CGFloat = -1.3   // -1.3=画面外左, 1.3=画面外右（キラッの位置）
    @State private var burst = 0

    private var interactive: Bool { result == .idle }

    var body: some View {
        Button {
            guard interactive else { return }
            PuzzleTheme.haptic()
            burst += 1                     // 選んだ瞬間に軽く星がはじける（タップの手応え）
            action()
        } label: {
            HStack(spacing: 10) {
                Text(text)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(foreground)
                if let mark = trailingMark {
                    Image(systemName: mark)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(fill)
                    .shadow(color: shadowColor, radius: 8, x: 0, y: 5)
            )
            .overlay(shineOverlay)   // はずれた時、正解だけ「キラッ」と斜めに光が走る
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(stroke, lineWidth: 2.5)
            )
            .scaleEffect(pop)
            .modifier(PuzzleShakeEffect(amount: shake))
            .opacity(result == .dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: interactive)
        .tapBurst(trigger: burst, reach: 0.75)
        .allowsHitTesting(interactive)   // 回答後は無反応の当たり判定を消す（VoiceOver/Switch対策）
        .task(id: result) { animate(for: result) }
    }

    /// 正解を開示するときに走る斜めのハイライト（キラッ）。それ以外では出さない。
    @ViewBuilder private var shineOverlay: some View {
        if result == .revealCorrect {
            GeometryReader { geo in
                let w = geo.size.width
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.32)
                    .rotationEffect(.degrees(22))
                    .offset(x: shine * w)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private func animate(for r: PuzzleOptionResult) {
        // Reduce Motion 時は動きを出さず、色と✓✗だけで結果を伝える。
        guard !reduceMotion else { pop = 1; shake = 0; shine = -1.3; return }
        switch r {
        case .correctChosen:
            // ぷるんと一回り大きくなって落ち着く（自分で当てた時はバーストも出る）
            withAnimation(.spring(response: 0.30, dampingFraction: 0.40)) { pop = 1.12 }
        case .wrongChosen:
            shake = 0
            withAnimation(.easeInOut(duration: 0.45)) { shake = 1 }
        case .revealCorrect:
            // 「これが正解だよ」と一目で分かるよう、軽く持ち上げて斜めのキラッを2回走らせる
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { pop = 1.05 }
            shine = -1.3
            withAnimation(.easeInOut(duration: 0.85).delay(0.15).repeatCount(2, autoreverses: false)) {
                shine = 1.3
            }
        case .idle:
            // もういちど＝状態リセット
            pop = 1; shake = 0; shine = -1.3
        case .dimmed:
            break
        }
    }

    private var trailingMark: String? {
        switch result {
        case .correctChosen, .revealCorrect: return "checkmark.circle.fill"
        case .wrongChosen: return "xmark.circle.fill"
        default: return nil
        }
    }

    private var foreground: Color {
        switch result {
        case .correctChosen, .revealCorrect, .wrongChosen: return .white
        default: return PuzzleTheme.ink
        }
    }

    private var fill: AnyShapeStyle {
        switch result {
        case .correctChosen, .revealCorrect:
            return AnyShapeStyle(PuzzleTheme.buttonGradient(PuzzleTheme.correctFill))
        case .wrongChosen:
            return AnyShapeStyle(PuzzleTheme.buttonGradient(PuzzleTheme.wrongFill))
        default:
            return AnyShapeStyle(PuzzleTheme.tileFill)
        }
    }

    private var stroke: Color {
        switch result {
        case .correctChosen, .revealCorrect: return .white.opacity(0.5)
        case .wrongChosen: return .white.opacity(0.5)
        default: return PuzzleTheme.tileStroke
        }
    }

    private var shadowColor: Color {
        switch result {
        case .correctChosen, .revealCorrect: return PuzzleTheme.correct.opacity(0.4)
        case .wrongChosen: return PuzzleTheme.retry.opacity(0.4)
        default: return PuzzleTheme.ink.opacity(0.10)
        }
    }
}

// MARK: - 星バースト（正解・クリアのごほうび演出）

/// 正解の瞬間に弾ける、多層の祝福演出（“脳汁”級）。
/// ①中心グローの閃光 ②多色シンボルがスピンしながら放射状に飛散 ③紙吹雪が舞い落ちる。
/// 表示された瞬間に一回きり走る（条件付き挿入で「正解になった時」に出す）。
struct PuzzleCelebration: View {
    var pieces: Int = 16
    var radius: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = false
    @State private var fall = false
    @State private var glow = false

    private let palette: [Color] = [
        PuzzleTheme.accent,
        PuzzleTheme.correct,
        PuzzleTheme.tileStroke,
        Color(red: 0.98, green: 0.45, blue: 0.55),   // ピンク
        Color(red: 0.40, green: 0.62, blue: 0.95),   // 水色
    ]
    private let symbols = ["star.fill", "sparkles", "circle.fill", "heart.fill", "seal.fill"]

    /// index ベースの決定論的な擬似乱数（0..1）。粒ごとに方向・大きさ・回転をばらけさせる。
    private func rnd(_ i: Int, _ salt: Double) -> Double {
        let v = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return v - floor(v)
    }

    var body: some View {
        if reduceMotion {
            // モーション控えめ：飛び散らさず、静止の星3つでさりげなく祝う。
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "star.fill").foregroundStyle(PuzzleTheme.accent)
                }
            }
            .font(.system(size: 26, weight: .black))
            .allowsHitTesting(false)
        } else {
            burst
        }
    }

    private var burst: some View {
        ZStack {
            // ① 中心グロー：パッと光って大きく広がりながら消える。
            Circle()
                .fill(RadialGradient(colors: [PuzzleTheme.accent.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: radius))
                .scaleEffect(glow ? 1.9 : 0.2)
                .opacity(glow ? 0 : 0.9)

            // ② 放射状バースト：多色のシンボルが回転しながら外へ飛び散って消える。
            ForEach(0..<pieces, id: \.self) { i in burstPiece(i) }

            // ③ 紙吹雪：上からくるくる舞い落ちる短冊。
            ForEach(0..<pieces, id: \.self) { i in confettiPiece(i) }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { glow = true }
            withAnimation(.easeOut(duration: 0.9)) { go = true }
            withAnimation(.easeIn(duration: 1.5)) { fall = true }
        }
    }

    // 型推論を軽くするため、粒ごとの値はここで CGFloat/Double を明示して組む。
    private func burstPiece(_ i: Int) -> some View {
        let angle: Double = Double(i) / Double(pieces) * 2 * .pi + rnd(i, 1) * 0.5
        let dist: CGFloat = radius * CGFloat(0.65 + 0.55 * rnd(i, 2))
        let dotSize: CGFloat = 16 + CGFloat(rnd(i, 3)) * 18
        let rot: Double = rnd(i, 4) * 540 - 270
        let dx: CGFloat = CGFloat(cos(angle)) * dist
        let dy: CGFloat = CGFloat(sin(angle)) * dist
        return Image(systemName: symbols[i % symbols.count])
            .font(.system(size: dotSize, weight: .black))
            .foregroundStyle(palette[i % palette.count])
            .rotationEffect(.degrees(go ? rot : 0))
            .offset(x: go ? dx : 0, y: go ? dy : 0)
            .scaleEffect(go ? 0.3 : 1.4)
            .opacity(go ? 0 : 1)
    }

    private func confettiPiece(_ i: Int) -> some View {
        let x: CGFloat = CGFloat(rnd(i, 5) * 2 - 1) * radius
        let rot: Double = rnd(i, 6) * 720 - 360
        let downY: CGFloat = radius * 1.7
        let upY: CGFloat = -radius * 0.5
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(palette[(i + 2) % palette.count])
            .frame(width: 8, height: 14)
            .rotationEffect(.degrees(fall ? rot : 0))
            .offset(x: x, y: fall ? downY : upY)
            .opacity(fall ? 0 : 1)
    }
}

// MARK: - すすみ具合バー（ドット → ぷっくりピル）

/// 何問中いまどこか。済みは塗り、現在は脈打つ、これからは薄い。
struct PuzzleProgressBar: View {
    let total: Int
    let current: Int   // 0-based
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    Capsule()
                        .fill(i <= current ? PuzzleTheme.accent : PuzzleTheme.slotStroke.opacity(0.4))
                        .frame(width: i == current ? 22 : 12, height: 10)
                        .scaleEffect(i == current && pulse ? 1.12 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: current)
                }
            }
            Spacer(minLength: 8)
            Text("\(min(current + 1, total)) / \(total)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink.opacity(0.7))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - 選択肢ボタン（穴埋め・リスニングで共通）旧シンプル版は上の result 対応版に統合済み

// MARK: - 音ゲートのヘッドフォン演出（拡縮＋背景の波紋リップル）

/// ヘッドフォンがふわっと拡縮し、背景から水紋のようなリングが広がって消える。
/// 「音」を連想させるリッチな待機アニメ（音ゲート上部に置く）。
struct SoundGatePulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var ripple = false

    private let ripples = 3
    private let base: CGFloat = 150

    var body: some View {
        ZStack {
            // 背景の波紋：内側から外へ広がりながら薄くなる輪。少しずつ遅らせて連続させる。
            // Reduce Motion 時は波紋を出さない（高モーションのため）。
            if !reduceMotion {
                ForEach(0..<ripples, id: \.self) { i in
                    Circle()
                        .stroke(PuzzleTheme.accent.opacity(0.45), lineWidth: 3)
                        .frame(width: base, height: base)
                        .scaleEffect(ripple ? 2.2 : 0.7)
                        .opacity(ripple ? 0 : 0.55)
                        .animation(
                            .easeOut(duration: 2.4)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.8),
                            value: ripple
                        )
                }
            }
            // ヘッドフォン本体：やわらかく呼吸するように拡縮（Reduce Motion 時は静止）。
            Image(systemName: "headphones")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(PuzzleTheme.accent)
                .padding(28)
                .background(
                    Circle().fill(PuzzleTheme.tileFill)
                        .shadow(color: PuzzleTheme.accent.opacity(0.3), radius: 14, x: 0, y: 7)
                )
                .scaleEffect(reduceMotion ? 1.0 : (breathe ? 1.08 : 0.95))
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
        }
        .frame(height: 300)
        .onAppear {
            guard !reduceMotion else { return }
            breathe = true; ripple = true
        }
    }
}

// MARK: - 音ゲート（公共の場対応・セッション冒頭で1回だけ）

struct PuzzleSoundGate: View {
    let onChoose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            SoundGatePulse()
            Text("おとを だして いい？")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
            Text("でんしゃの なかなど しずかな ところでは「おとなし」をえらんでね")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            VStack(spacing: 12) {
                PuzzlePrimaryButton(title: "🔊 おとを だす", tint: PuzzleTheme.accent) { onChoose(true) }
                PuzzlePrimaryButton(title: "🔇 おとなし", tint: PuzzleTheme.ink.opacity(0.7)) { onChoose(false) }
            }
            .frame(maxWidth: 360)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 折り返しレイアウト（タイル並べ用・iOS16+）

struct PuzzleFlowLayout: Layout {
    var spacing: CGFloat = 10

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
