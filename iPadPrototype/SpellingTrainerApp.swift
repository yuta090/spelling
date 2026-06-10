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
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
    }
}

extension View {
    func tapFeedback(scale _: CGFloat = 0.965) -> some View {
        modifier(TapFeedbackModifier())
    }
}
