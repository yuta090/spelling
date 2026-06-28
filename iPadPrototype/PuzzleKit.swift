import SwiftUI
import UIKit

// ことばパズル共通UI基盤。
// ぶんづくり / あなうめ / きいてあなうめ / おとをきいてえらぶ … 全形式で同じ見た目言語を使う。
// 以前は各 View が同一値のパレット（WO/CZ/LC/WL/MX）と bigButton / FlowLayout を個別に複製していた。
// それらをここに一本化し、PuzzleSessionView と各試遊 View が共有する。
// 設計: docs/kotoba-puzzle-spec-2026-06-28.md

// MARK: - 配色（温かいクリーム＋オレンジ）

enum PuzzleTheme {
    static let ink = Color(red: 0.45, green: 0.28, blue: 0.08)
    static let tileFill = Color(red: 1.0, green: 0.97, blue: 0.86)
    static let tileStroke = Color(red: 0.95, green: 0.73, blue: 0.34)
    static let slotStroke = Color(red: 0.90, green: 0.82, blue: 0.66)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let correct = Color(red: 0.30, green: 0.62, blue: 0.28)
    static let retry = Color(red: 0.84, green: 0.36, blue: 0.08)
    static let bg = Color(red: 1.0, green: 0.99, blue: 0.95)
    static let hintFill = Color(red: 1.0, green: 0.98, blue: 0.90)

    static func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - 大ボタン（はじめる / つぎへ / もういちど 等）

struct PuzzlePrimaryButton: View {
    let title: String
    var tint: Color = PuzzleTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 18).fill(tint))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }
}

// MARK: - フィードバック見出し（せいかい / ナイス チャレンジ）

struct PuzzleVerdictLabel: View {
    let isCorrect: Bool

    var body: some View {
        if isCorrect {
            Label("やったね！ せいかい！", systemImage: "star.fill")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.correct)
        } else {
            Label("ナイス チャレンジ！", systemImage: "flame.fill")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(PuzzleTheme.accent)
        }
    }
}

// MARK: - 形式バッジ（ならべかえ / あなうめ …）

struct PuzzleFormatBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(PuzzleTheme.accent))
    }
}

// MARK: - 「きいてみる」カプセルボタン（音声再生）

struct PuzzleListenButton: View {
    var title: String = "きいてみる"
    let action: () -> Void

    var body: some View {
        Button {
            PuzzleTheme.haptic()
            action()
        } label: {
            Label(title, systemImage: "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.accent)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(Capsule().fill(PuzzleTheme.tileFill))
                .overlay(Capsule().stroke(PuzzleTheme.tileStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }
}

// MARK: - 選択肢ボタン（穴埋め・リスニングで共通）

struct PuzzleOptionButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button {
            PuzzleTheme.haptic()
            action()
        } label: {
            Text(text)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(PuzzleTheme.tileFill))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PuzzleTheme.tileStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .tapFeedback(bounce: true)
    }
}

// MARK: - 音ゲート（公共の場対応・セッション冒頭で1回だけ）

struct PuzzleSoundGate: View {
    let onChoose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(systemName: "headphones")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(PuzzleTheme.accent)
            Text("おとを だして いい？")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(PuzzleTheme.ink)
            Text("でんしゃの なかなど しずかな ところでは「おとなし」をえらんでね")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            VStack(spacing: 12) {
                PuzzlePrimaryButton(title: "🔊 おとを だす", tint: PuzzleTheme.accent) { onChoose(true) }
                PuzzlePrimaryButton(title: "🔇 おとなし", tint: PuzzleTheme.ink.opacity(0.7)) { onChoose(false) }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 折り返しレイアウト（タイル並べ用・iOS16+）

struct PuzzleFlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
