import PencilKit
import SwiftUI

enum PracticeMode {
    case practice
    case test
}

struct WritingGuideLayout: Equatable {
    static let topRatio: CGFloat = 0.22
    static let midRatio: CGFloat = 0.40
    static let baselineRatio: CGFloat = 0.66
    static let descenderRatio: CGFloat = 0.84

    var size: CGSize

    var top: CGFloat {
        size.height * Self.topRatio
    }

    var mid: CGFloat {
        size.height * Self.midRatio
    }

    var baseline: CGFloat {
        size.height * Self.baselineRatio
    }

    var descender: CGFloat {
        size.height * Self.descenderRatio
    }

    func lineStart(for mode: PracticeMode) -> CGFloat {
        mode == .practice ? 46 : 128
    }

    func lineEnd(for mode: PracticeMode) -> CGFloat {
        size.width - (mode == .practice ? 46 : 24)
    }

    var practiceBandRect: CGRect {
        CGRect(
            x: 26,
            y: top - 22,
            width: max(size.width - 52, 0),
            height: descender - top + 44
        )
    }

    var sampleTextFontSize: CGFloat {
        min(max(size.height * 0.35, 58), 158)
    }

    var sampleTextYOffset: CGFloat {
        size.height * 0.073
    }
}

struct CanvasFitGeometry {
    static func fittedRect(in containerSize: CGSize, canvasSize: CGSize) -> CGRect {
        guard containerSize.width > 0,
              containerSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return .zero
        }

        let scale = scale(in: containerSize, canvasSize: canvasSize)
        let size = CGSize(
            width: canvasSize.width * scale,
            height: canvasSize.height * scale
        )

        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func scale(in containerSize: CGSize, canvasSize: CGSize) -> CGFloat {
        guard containerSize.width > 0,
              containerSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return 1
        }

        return min(
            containerSize.width / canvasSize.width,
            containerSize.height / canvasSize.height
        )
    }
}

struct GuidedWritingCanvas: View {
    /// お手本文字の通常時の濃さ。
    static let sampleTextBaseOpacity: Double = 0.30

    @Binding var drawing: PKDrawing
    var mode: PracticeMode
    var guideLabels: [String] = ["Top line", "Mid line", "Base line", "Descender"]
    var sampleText: String?
    var capture: DrawingCapture? = nil
    var isInputEnabled = true
    var minimumHeight: CGFloat = 285
    /// お手本文字の濃さ。なぞり練習で文字をゆっくり消すときは親側でアニメーションさせる。
    /// ※ フェードを親の状態として持つことで、消す/戻す（`.id` 付け替え）でフェードが
    ///    巻き戻らないようにしている。
    var sampleTextOpacity: Double = GuidedWritingCanvas.sampleTextBaseOpacity

    var body: some View {
        ZStack {
            FourLineGuide(mode: mode, labels: guideLabels)
            if let sampleText {
                GeometryReader { proxy in
                    let layout = WritingGuideLayout(size: proxy.size)

                    Text(sampleText)
                        .font(.system(size: layout.sampleTextFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.black.opacity(sampleTextOpacity))
                        .offset(y: layout.sampleTextYOffset)
                        .minimumScaleFactor(0.35)
                        .lineLimit(1)
                        .padding(.horizontal, mode == .practice ? 80 : 130)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                }
            }
            PencilCanvasView(drawing: $drawing, capture: capture, isInputEnabled: isInputEnabled)
        }
        .frame(minHeight: minimumHeight)
        .background(canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if mode == .test {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            }
        }
        .shadow(color: mode == .practice ? Color(red: 0.42, green: 0.48, blue: 0.66).opacity(0.10) : .clear, radius: 14, x: 0, y: 8)
    }

    private var canvasBackground: some View {
        Group {
            if mode == .practice {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.99, blue: 0.94),
                        Color(red: 0.96, green: 0.99, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.white
            }
        }
    }
}

struct FourLineGuide: View {
    var mode: PracticeMode
    var labels: [String] = ["Top line", "Mid line", "Base line", "Descender"]

    var body: some View {
        GeometryReader { proxy in
            let layout = WritingGuideLayout(size: proxy.size)
            let alpha = mode == .practice ? 0.70 : 0.38
            let labelX: CGFloat = 108
            let lineStart = layout.lineStart(for: mode)
            let lineEnd = layout.lineEnd(for: mode)

            Canvas { context, _ in
                if mode == .practice {
                    context.fill(
                        Path(roundedRect: layout.practiceBandRect, cornerRadius: 24),
                        with: .color(Color(red: 0.92, green: 0.97, blue: 1.0).opacity(0.52))
                    )

                    drawGuideLine(from: lineStart, to: lineEnd, y: layout.top, color: .blue.opacity(0.06), width: 1, in: &context)
                    drawGuideLine(from: lineStart, to: lineEnd, y: layout.mid, color: .blue.opacity(0.13), width: 1, dash: [8, 14], in: &context)
                    drawGuideLine(from: lineStart, to: lineEnd, y: layout.baseline, color: .red.opacity(0.46), width: 2.4, in: &context)
                    drawGuideLine(from: lineStart, to: lineEnd, y: layout.descender, color: .blue.opacity(0.07), width: 1, in: &context)
                } else {
                    drawLabel(labels[safe: 0] ?? "", at: CGPoint(x: labelX, y: layout.top), in: context)
                    drawLabel(labels[safe: 1] ?? "", at: CGPoint(x: labelX, y: layout.mid), in: context)
                    drawLabel(labels[safe: 2] ?? "", at: CGPoint(x: labelX, y: layout.baseline), in: context)
                    drawLabel(labels[safe: 3] ?? "", at: CGPoint(x: labelX, y: layout.descender), in: context)

                    var line = Path()
                    line.move(to: CGPoint(x: lineStart, y: layout.top))
                    line.addLine(to: CGPoint(x: lineEnd, y: layout.top))
                    context.stroke(line, with: .color(.blue.opacity(alpha * 0.20)), lineWidth: 1)

                    var midLine = Path()
                    midLine.move(to: CGPoint(x: lineStart, y: layout.mid))
                    midLine.addLine(to: CGPoint(x: lineEnd, y: layout.mid))
                    context.stroke(
                        midLine,
                        with: .color(.blue.opacity(alpha * 0.28)),
                        style: StrokeStyle(lineWidth: 1, dash: [10, 10])
                    )

                    var base = Path()
                    base.move(to: CGPoint(x: lineStart, y: layout.baseline))
                    base.addLine(to: CGPoint(x: lineEnd, y: layout.baseline))
                    context.stroke(base, with: .color(.red.opacity(alpha * 0.90)), lineWidth: 1.5)

                    var desc = Path()
                    desc.move(to: CGPoint(x: lineStart, y: layout.descender))
                    desc.addLine(to: CGPoint(x: lineEnd, y: layout.descender))
                    context.stroke(desc, with: .color(.blue.opacity(alpha * 0.20)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawGuideLine(
        from start: CGFloat,
        to end: CGFloat,
        y: CGFloat,
        color: Color,
        width: CGFloat,
        dash: [CGFloat] = [],
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: CGPoint(x: start, y: y))
        path.addLine(to: CGPoint(x: end, y: y))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash)
        )
    }

    private func drawLabel(_ label: String, at point: CGPoint, in context: GraphicsContext) {
        context.draw(
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary),
            at: point,
            anchor: .trailing
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
