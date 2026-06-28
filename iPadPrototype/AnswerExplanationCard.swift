import SwiftUI
import SpellingSyncCore

// 答え合わせ後／ヒントの「説明」を1枚で見せる共通カード。
// 仕様: docs/answer-explanation-spec-2026-06-28.md（§3 表示ルール・§6 共有カード）。
// 入力は純粋モデル `AnswerExplanation` 1つだけ。ロジックは持たず、表示ルールだけを担う。
// つづり練習・文法クイズ・今後のクイズで同じカードを共有する（見た目言語を増やさない）。
//
// §3 表示ルール（nil の節は描画しない）：
//   wasCorrect == true  → 正解文（「できたね！」）＋意味。解説は出さない。
//   wasCorrect == false → 正解文（「せいかいは…」）＋意味＋解説＋なかま。
//   wasCorrect == nil   → 閲覧/タップ。意味は出す。解説・なかまは任意。

struct AnswerExplanationCard: View {
    let explanation: AnswerExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let headline = explanation.headline, !headline.isEmpty {
                Label(headline, systemImage: headlineIcon)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AEC.accent)
            }

            if let correctText = explanation.correctText, !correctText.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if let label = correctLabel {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(correctText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AEC.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let meaning = explanation.meaningJa, !meaning.isEmpty {
                Text(meaning)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // §3: 正解時は detail を出さない（呼び出し側に頼らずカード自身で契約を守る）。
            if explanation.wasCorrect != true, let detail = explanation.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AEC.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !explanation.chips.isEmpty {
                CardFlow(spacing: 8) {
                    ForEach(explanation.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AEC.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AEC.tileFill))
                            .overlay(Capsule().stroke(AEC.tileStroke, lineWidth: 1.5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(AEC.hintFill))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AEC.tileStroke, lineWidth: 1.5))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    /// 正解文の上に付ける小さなラベル。正誤で言い回しを変える（前向きに）。
    /// nil（閲覧/タップ）は見出しなしで素の情報を出す。
    private var correctLabel: String? {
        guard let wasCorrect = explanation.wasCorrect else { return nil }
        return wasCorrect ? "できたね！" : "せいかいは…"
    }

    private var headlineIcon: String {
        explanation.wasCorrect == true ? "star.fill" : "lightbulb.fill"
    }
}

// MARK: - 配色（WordOrderingView の温かいパレットに合わせる。WO は private のためカード内に複製）

private enum AEC {
    static let ink = Color(red: 0.45, green: 0.28, blue: 0.08)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let tileFill = Color(red: 1.0, green: 0.97, blue: 0.86)
    static let tileStroke = Color(red: 0.95, green: 0.73, blue: 0.34)
    static let hintFill = Color(red: 1.0, green: 0.98, blue: 0.90)
}

// MARK: - なかまチップ用の折り返しレイアウト（カード内自己完結）

/// 子要素を左上から詰めて横幅を超えたら折り返す素朴なフロー。チップが増えても崩れないように。
private struct CardFlow: Layout {
    var spacing: CGFloat = 8

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

#if DEBUG
#Preview("不正解") {
    AnswerExplanationCard(explanation: AnswerExplanation(
        wasCorrect: false,
        headline: "be動詞",
        correctText: "This is a pen.",
        meaningJa: "これはペンです。",
        detail: "「〜は…です」は be動詞（is/am/are）でつなぐよ。",
        chips: []
    ))
    .padding()
}

#Preview("正解") {
    AnswerExplanationCard(explanation: AnswerExplanation(
        wasCorrect: true,
        headline: "be動詞",
        correctText: "This is a pen.",
        meaningJa: "これはペンです。"
    ))
    .padding()
}
#endif
