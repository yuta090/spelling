import AVFoundation
import Foundation

/// れんしゅうの効果音（同梱 WAV）を鳴らす。
///
/// iPad はハプティクスが効かないので、音が実質唯一の「手触り」チャネル
/// （視覚の押し心地は `tapFeedback` が担当）。素材は `scripts/make_practice_sounds.py` で合成した同梱 WAV。
/// TTS（ほめ言葉の読み上げ）と重ねて鳴らすため、プレイヤーは効果音ごとに分けて保持する。
@MainActor
final class SoundPlayer: ObservableObject {
    enum Effect: String, CaseIterable {
        /// ボタンの「ポン」（テストの回答送りなど）。
        case pop
        /// 中間の回のキラキラ「シャラン」。
        case sparkle
        /// 単語完了のコイン「チャリン」。
        case coin
        /// レア大当たりのジャックポット。
        case rare
        /// セッション完了のファンファーレ。
        case fanfare
    }

    private var players: [Effect: AVAudioPlayer] = [:]

    init() {
        // BGM 等と共存できる ambient。効果音でよそのオーディオを止めない。
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])

        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav",
                                            subdirectory: "sounds") else {
                continue
            }
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = 0.6
                player.prepareToPlay()
                players[effect] = player
            }
        }
    }

    func play(_ effect: Effect) {
        guard let player = players[effect] else {
            return
        }
        player.currentTime = 0
        player.play()
    }
}
