import AVFoundation
import Foundation

@MainActor
final class SpeechPlayer: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String = "en-US", rate: Float = 0.42) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        synthesizer.speak(utterance)
    }
}
