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
    private let hitSlop: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, hitSlop)
            .padding(.vertical, hitSlop)
            .contentShape(Rectangle())
            .padding(.horizontal, -hitSlop)
            .padding(.vertical, -hitSlop)
    }
}

extension View {
    func tapFeedback(scale _: CGFloat = 0.965) -> some View {
        modifier(TapFeedbackModifier())
    }
}
