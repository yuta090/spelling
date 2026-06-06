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
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isTouching = false

    var scale: CGFloat = 0.965

    private var isPressed: Bool {
        isEnabled && isTouching
    }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion || !isPressed ? 1 : scale)
            .brightness(isPressed ? -0.045 : 0)
            .animation(.snappy(duration: 0.10, extraBounce: 0.02), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouching) { _, state, _ in
                        state = true
                    }
            )
    }
}

extension View {
    func tapFeedback(scale: CGFloat = 0.965) -> some View {
        modifier(TapFeedbackModifier(scale: scale))
    }
}
