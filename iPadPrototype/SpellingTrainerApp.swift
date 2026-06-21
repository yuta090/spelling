import SwiftUI

@main
struct SpellingTrainerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
        }
    }
}

private struct TapFeedbackModifier: ViewModifier {
    var pressedScale: CGFloat = 0.965
    var bounce: Bool = false

    private let hitSlop: CGFloat = 10
    @State private var isPressed = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let expanded = content
            .padding(.horizontal, hitSlop)
            .padding(.vertical, hitSlop)
            .contentShape(Rectangle())
            .padding(.horizontal, -hitSlop)
            .padding(.vertical, -hitSlop)

        if bounce {
            expanded
                .scaleEffect(isPressed ? pressedScale : 1)
                // 押し込みは素早く、離すと低ダンピングのバネで 1.0 を行き過ぎてプルルンと戻る
                .animation(
                    isPressed
                        ? .easeOut(duration: 0.10)
                        : .spring(response: 0.32, dampingFraction: 0.40),
                    value: isPressed
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPressed { isPressed = true }
                        }
                        .onEnded { _ in
                            isPressed = false
                        }
                )
        } else {
            expanded
        }
    }
}

extension View {
    func tapFeedback(scale: CGFloat = 0.965, bounce: Bool = false) -> some View {
        modifier(TapFeedbackModifier(pressedScale: scale, bounce: bounce))
    }
}

// MARK: - アニメ風アイリス・トランジション（丸い枠が萎む／開く）

/// 画面遷移を「黒い円が萎んで全黒 → 画面切替 → 円が開いて新画面」で包むコントローラ。
final class IrisController: ObservableObject {
    /// 1 = 完全に開いた状態（透明・全部見える）、0 = 完全に閉じた状態（全黒）。
    @Published var progress: CGFloat = 1
    /// オーバーレイを表示してタップを遮断している間 true。
    @Published var isActive = false

    var duration: Double = 0.42

    /// `swap` の前後を黒いアイリスで包んで遷移する。
    /// - Parameter animated: false（Reduce Motion 等）なら即座に `swap` のみ実行。
    func cover(animated: Bool = true, swap: @escaping () -> Void) {
        guard animated else {
            swap()
            return
        }
        // 多重起動を防ぐ（遷移中は受け付けない）。
        guard !isActive else {
            swap()
            return
        }

        isActive = true
        progress = 1

        // 1) 黒い円が萎んで全黒へ。
        withAnimation(.easeInOut(duration: duration), {
            self.progress = 0
        }, completion: { [weak self] in
            guard let self else { return }

            // 2) 全黒の間に、アニメ無効で実際の画面切替を行う。
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, swap)

            // 3) 円が開いて新画面が現れる。
            withAnimation(.easeInOut(duration: self.duration), {
                self.progress = 1
            }, completion: { [weak self] in
                self?.isActive = false
            })
        })
    }
}

/// 全画面の黒い矩形に円形の穴を空けた形。半径が小さいほど画面が黒く覆われる。
private struct IrisHoleShape: Shape {
    var radius: CGFloat
    var center: CGPoint

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(radius, AnimatablePair(center.x, center.y)) }
        set {
            radius = newValue.first
            center = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let r = max(radius, 0)
        path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        return path
    }
}

/// `IrisController` を購読して全画面に被さるアイリス・オーバーレイ。
struct IrisTransitionOverlay: View {
    @ObservedObject var controller: IrisController

    var body: some View {
        GeometryReader { geo in
            // 画面の隅まで覆える半径（少し余裕を持たせる）。
            let maxRadius = hypot(geo.size.width, geo.size.height) / 2 * 1.08
            IrisHoleShape(
                radius: controller.progress * maxRadius,
                center: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            )
            .fill(Color.black, style: FillStyle(eoFill: true))
        }
        .ignoresSafeArea()
        .allowsHitTesting(controller.isActive)
        .opacity(controller.isActive ? 1 : 0)
        .animation(nil, value: controller.isActive)
    }
}
