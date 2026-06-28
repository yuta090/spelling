import AVFoundation
import Foundation

@MainActor
final class SpeechPlayer: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String = "en-US", rate: Float = 0.42) {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        synthesizer.speak(utterance)
    }

    /// 再生中の読み上げを止める。リスニング穴埋めで「設問中は無音」を守るため、
    /// 問題を進める/やり直すとき・画面を閉じるときに呼ぶ。
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
