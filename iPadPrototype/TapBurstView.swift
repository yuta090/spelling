import SwiftUI
import SpellingSyncCore

// タップ＝「ポンッと弾けて星が飛び出す」ごほうび演出。
// パーティクルの飛び先は Core の決定論ロジック `TapBurst` が返し、ここは
// 「飛ばして回しながら消す」アニメと、ボタン本体の弾み(pop)だけを担う。
// iOS 16.4 ターゲットのため iOS17専用API（2引数onChange 等）は使わない。

/// タップ位置（ボタン中心）から星/キラキラが放射状に飛び出して消えるオーバーレイ。
struct TapBurstOverlay: View {
    /// タップごとに変える種。配置をばらけさせる。
    var seed: Int
    /// 飛距離の倍率（主役CTAは大きく、選択肢など軽い所は小さく）。
    var reach: CGFloat = 1.0
    /// 飛ばす粒の数。
    var count: Int = 9

    private static let symbols = ["star.fill", "sparkle", "sparkles"]
    // 既存のタップ演出（PracticeButtonTapEffect）と同じ、子ども向けの鮮やかな配色。
    // クリーム色の背景に埋もれないよう、彩度の高い色だけを使う（白/淡黄は使わない）。
    private static let palette: [Color] = [
        Color(red: 0.98, green: 0.52, blue: 0.12),  // オレンジ
        Color(red: 1.0,  green: 0.74, blue: 0.10),  // 金
        Color(red: 0.95, green: 0.34, blue: 0.76),  // ピンク
        Color(red: 0.28, green: 0.64, blue: 0.96),  // 青
        Color(red: 0.24, green: 0.72, blue: 0.35),  // 緑
        Color(red: 0.62, green: 0.42, blue: 0.92)   // 紫
    ]

    @State private var flew = false
    @State private var faded = false

    var body: some View {
        let particles = TapBurst.particles(seed: seed, count: count, reach: Double(reach))
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(particles.enumerated()), id: \.offset) { idx, p in
                    Image(systemName: Self.symbols[p.symbol])
                        .font(.system(size: CGFloat(p.size), weight: .heavy))
                        .foregroundStyle(color(idx))
                        // 淡い色でも輪郭が出るよう、うっすら影を敷く。
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                        .scaleEffect(flew ? 1.1 : 0.45)
                        .rotationEffect(.degrees(flew ? p.rotation : 0))
                        .position(
                            x: proxy.size.width / 2 + (flew ? CGFloat(p.dx) : 0),
                            y: proxy.size.height / 2 + (flew ? CGFloat(p.dy) : 0)
                        )
                        // 飛ぶ＝速めに外へ。途中までははっきり見せたいので movement は easeOut。
                        .animation(.easeOut(duration: 0.55).delay(p.delay), value: flew)
                        // 消える＝飛んでいる間は明るいまま保ち、後半でスッと消す（出オチを防ぐ）。
                        .opacity(faded ? 0 : 1)
                        .animation(.easeIn(duration: 0.28).delay(0.22 + p.delay), value: faded)
                }
            }
        }
        .allowsHitTesting(false)
        // 飾りのキラキラ。消えた後も opacity 0 でビュー階層に残るため、
        // VoiceOver から「星/キラキラ」が見えてフォーカスを乱さないよう隠す。
        .accessibilityHidden(true)
        .onAppear {
            flew = false
            faded = false
            Task { @MainActor in
                await Task.yield()
                flew = true
                faded = true   // opacity アニメに delay があるので、飛びきってから消える。
            }
        }
    }

    private func color(_ idx: Int) -> Color {
        Self.palette[idx % Self.palette.count]
    }
}

private struct TapBurstModifier: ViewModifier {
    var trigger: Int
    var reach: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popScale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(popScale)
            .overlay {
                if trigger > 0 && !reduceMotion {
                    TapBurstOverlay(seed: trigger, reach: reach)
                        .id(trigger)
                }
            }
            // `.task(id:)` は trigger が変わるたびに前回のタスクを自動キャンセルするので、
            // 連打しても「古い戻し処理が新しいタップの最中に popScale=1 にする」事故が起きない。
            .task(id: trigger) {
                guard trigger > 0, !reduceMotion else { return }
                // ポンッ＝素早く膨らんで、低ダンピングのバネで弾みながら戻る。
                withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) {
                    popScale = 1.10
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                // 連打で差し替えられた（キャンセルされた）場合は戻さない＝新しいタップに任せる。
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                    popScale = 1
                }
            }
    }
}

extension View {
    /// タップ演出: `trigger`（タップごとに +1 する整数）が変わるたびに、ボタンがポンッと弾み、
    /// 中心から星/キラキラが放射状に飛び出す。reduceMotion 時は何も起こさない（静かに）。
    /// - Parameters:
    ///   - trigger: 呼び出し側で `@State` の整数を持ち、タップ時に +1 する。
    ///   - reach: 飛距離の倍率（既定 1.0。主役CTAは大きめ、選択肢は小さめ）。
    func tapBurst(trigger: Int, reach: CGFloat = 1.0) -> some View {
        modifier(TapBurstModifier(trigger: trigger, reach: reach))
    }
}
