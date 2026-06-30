import Foundation

/// ボタンの「押し心地」（押し込み→離す）の見た目パラメータを計算する純ロジック。
///
/// 方針: iPad には Taptic Engine が無くハプティクス（`UIImpactFeedbackGenerator`）が
/// 実質効かないため、押し心地は「縮む・少し沈む・影が弱まる」という *視覚* で表現する。
/// View 側は押下状態(`pressed`)と `reduceMotion` を渡すだけにし、スケール／沈み量／影の
/// 倍率はここで決める（アニメーションのカーブは SwiftUI 側の責務として残す）。
public enum PressFeel {

    /// 押し込みの深さ。`primary`=主要CTA（はじめる／つぎへ等・深い）、`subtle`=一般タップ（控えめ）。
    public enum Depth {
        case primary
        case subtle
    }

    /// 押下時の見た目。`rest`（非押下）は scale=1 / yOffset=0。
    public struct State: Equatable, Sendable {
        /// 拡大率（1=原寸）。押下で 1 未満になり「縮む」。
        public let scale: Double
        /// 下方向へ沈む量（pt、+で下）。押下で正になり「沈む」。
        public let yOffset: Double

        public init(scale: Double, yOffset: Double) {
            self.scale = scale
            self.yOffset = yOffset
        }
    }

    /// 非押下（通常時）の見た目。
    public static let rest = State(scale: 1, yOffset: 0)

    /// 押下状態に応じた見た目。
    /// - Parameters:
    ///   - pressed: 指が触れて押し込まれているか。
    ///   - depth: 押し込みの深さ（主要CTA か 一般タップ か）。
    ///   - reduceMotion: アクセシビリティの「視差効果を減らす」。true のときは押しても動かさない。
    /// - Returns: 押下中の見た目。非押下／reduceMotion 時は `rest`。
    public static func state(pressed: Bool, depth: Depth, reduceMotion: Bool = false) -> State {
        guard pressed, !reduceMotion else { return rest }
        switch depth {
        case .primary:
            // 主要CTA: しっかり縮んで沈む＝「カチッと押した」物理感。
            return State(scale: 0.95, yOffset: 3)
        case .subtle:
            // 一般タップ: 触れた手応えだけ伝わる控えめな押し込み。
            return State(scale: 0.975, yOffset: 1)
        }
    }
}
