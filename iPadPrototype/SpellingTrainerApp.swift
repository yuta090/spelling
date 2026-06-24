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
@MainActor
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
        animateProgress(to: 0) { [weak self] in
            guard let self else { return }

            // 2) 全黒の間に、アニメ無効で実際の画面切替を行う。
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, swap)

            // 3) 円が開いて新画面が現れる。
            self.animateProgress(to: 1) { [weak self] in
                self?.isActive = false
            }
        }
    }

    /// `progress` をアニメーションで変化させ、完了後に `completion` を呼ぶ。
    /// iOS 17 は標準の completion を、iOS 16 は同じ duration 後のディレイで代替する。
    private func animateProgress(to target: CGFloat, completion: @escaping () -> Void) {
        if #available(iOS 17.0, *) {
            withAnimation(.easeInOut(duration: duration)) {
                self.progress = target
            } completion: {
                completion()
            }
        } else {
            withAnimation(.easeInOut(duration: duration)) {
                self.progress = target
            }
            let delayNanoseconds = UInt64(duration * 1_000_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                completion()
            }
        }
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

// MARK: - iOS 16 互換シム
// iOS 17 専用 API（ContentUnavailableView / 2引数 onChange / scrollBounceBehavior）を
// 16 でも使える形に置き換える。見た目・挙動は iOS 17 版と同等。

/// `ContentUnavailableView`(iOS 17+) の代替。空状態の表示に使う。
/// 呼び出しは `EmptyStateView("タイトル", systemImage: "...", description: Text("..."))`。
struct EmptyStateView: View {
    private let title: String
    private let systemImage: String
    private let description: Text?

    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if let description {
                description
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
    }
}

extension View {
    /// 2引数 `onChange(of:){ _, new in }`(iOS 17+) の代替。新しい値だけを渡す。
    /// `initial: true` で表示時にも一度実行する（iOS 17 の initial 相当）。
    @ViewBuilder
    func onValueChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (V) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value, initial: initial) { _, newValue in
                action(newValue)
            }
        } else {
            self.modifier(LegacyOnChange(value: value, initial: initial, action: action))
        }
    }

    /// `scrollBounceBehavior(.basedOnSize)`(iOS 16.4+) を 16.0 でも安全に呼ぶ。
    @ViewBuilder
    func scrollBounceBasedOnSizeCompat() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

private struct LegacyOnChange<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if initial {
                    action(value)
                }
            }
            // iOS 17 で deprecated だが、この分岐は iOS 16 でのみ実行される。
            .onChange(of: value) { newValue in
                action(newValue)
            }
    }
}
