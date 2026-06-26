import SwiftUI

@main
struct SpellingTrainerApp: App {
    @StateObject private var model = AppModel()
    /// 認証・アクティブ世帯。自動同期のスコープ供給元としてアプリ全体で共有する。
    @StateObject private var session = SyncSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(session)
        }
    }
}

/// ルート。`words` の**自動同期トリガ**をここで束ねる:
/// 起動時／前面化（`scenePhase == .active`）／サインイン・世帯確定（`activeHouseholdID` 変化）。
/// 単語編集後のデバウンス同期は `AppModel.words` 側で発火する。
/// いずれも世帯未選択なら no-op（`AppModel.syncNow` がガード）。
private struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SyncSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                HomeView()
            } else {
                // 初回だけ保護者向けオンボーディング。完了でホームへ切り替わる。
                OnboardingView(session: session)
            }
        }
            .task {
                // 世帯供給元を注入し、認証状態を読み直してから起動時同期。
                // サインイン済みの親のときだけ世帯を返す（古い active ID で no-account 同期を走らせない）。
                model.configureSync { [weak session] in
                    guard let session, session.isSignedIn, !session.isAnonymous else { return nil }
                    return session.activeHouseholdID
                }
                await session.refreshOnAppear()
                await model.syncNow()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await model.syncNow() } }
            }
            .onChange(of: session.activeHouseholdID) { _ in
                Task { await model.syncNow() }
            }
        #if DEBUG
            // 同期バックエンドの疎通用デバッグ導線（製品UIには出さない）。
            .overlay(alignment: .bottomLeading) {
                SyncDebugLauncher()
            }
        #endif
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

// MARK: - 取り込み(OCR)の進捗

/// カメラ取り込みの読み取り進捗。Vision の実進捗を受けつつ、報告が粗い/来ない端末でも
/// バーが止まって見えないよう、時間ベースで 0→0.9 へなめらかにクリープし、完了時に 1.0 にする。
@MainActor
final class ScanProgressModel: ObservableObject {
    @Published private(set) var fraction: Double = 0
    private var ticker: Task<Void, Never>?

    /// 読み取り開始。クリープを始める。
    func start() {
        fraction = 0
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000) // 約0.09秒ごと
                guard let self else { return }
                if self.fraction < 0.9 {
                    // 0.9 へ漸近（残りの 6% ずつ詰める）。遅い端末でも自然に進んで見える。
                    self.fraction += (0.9 - self.fraction) * 0.06
                }
            }
        }
    }

    /// Vision からの実進捗(0...1)。現在値より大きいときだけ反映し、後退させない。
    func report(_ value: Double) {
        guard value.isFinite else { return }
        fraction = max(fraction, min(value, 0.99))
    }

    /// 読み取り完了。100% にしてクリープを止める。
    func finish() {
        ticker?.cancel()
        ticker = nil
        fraction = 1
    }

    /// 失敗・キャンセル時に 0 へ戻す。
    func reset() {
        ticker?.cancel()
        ticker = nil
        fraction = 0
    }
}

/// 取り込み中に出す、パーセンテージ付きの進捗バー。
struct ScanProgressBar: View {
    var fraction: Double
    var label: String
    var tint: Color = Color(red: 0.13, green: 0.34, blue: 0.75)

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int((clamped * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.bold))

            ProgressView(value: clamped)
                .tint(tint)
        }
        .animation(.easeOut(duration: 0.2), value: clamped)
    }
}
