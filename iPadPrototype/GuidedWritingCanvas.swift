import PencilKit
import SwiftUI

enum PracticeMode {
    case practice
    case test
}

struct GuidedWritingCanvas: View {
    @Binding var drawing: PKDrawing
    var mode: PracticeMode
    var guideLabels: [String] = ["Top line", "Mid line", "Base line", "Descender"]
    var sampleText: String?
    var capture: DrawingCapture? = nil

    var body: some View {
        ZStack {
            FourLineGuide(mode: mode, labels: guideLabels)
            if let sampleText {
                Text(sampleText)
                    .font(.system(size: 104, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.30))
                    .offset(y: 22)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .padding(.horizontal, 130)
                    .allowsHitTesting(false)
            }
            PencilCanvasView(drawing: $drawing, capture: capture)
        }
        .frame(minHeight: 285)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }
}

struct FourLineGuide: View {
    var mode: PracticeMode
    var labels: [String] = ["Top line", "Mid line", "Base line", "Descender"]

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let alpha = mode == .practice ? 0.70 : 0.38
            let labelX: CGFloat = 108
            let lineStart: CGFloat = 128
            let lineEnd = width - 24
            let top = height * 0.22
            let mid = height * 0.40
            let baseline = height * 0.66
            let descender = height * 0.84

            Canvas { context, _ in
                drawLabel(labels[safe: 0] ?? "", at: CGPoint(x: labelX, y: top), in: context)
                drawLabel(labels[safe: 1] ?? "", at: CGPoint(x: labelX, y: mid), in: context)
                drawLabel(labels[safe: 2] ?? "", at: CGPoint(x: labelX, y: baseline), in: context)
                drawLabel(labels[safe: 3] ?? "", at: CGPoint(x: labelX, y: descender), in: context)

                var line = Path()
                line.move(to: CGPoint(x: lineStart, y: top))
                line.addLine(to: CGPoint(x: lineEnd, y: top))
                context.stroke(line, with: .color(.blue.opacity(alpha * 0.20)), lineWidth: 1)

                var midLine = Path()
                midLine.move(to: CGPoint(x: lineStart, y: mid))
                midLine.addLine(to: CGPoint(x: lineEnd, y: mid))
                context.stroke(
                    midLine,
                    with: .color(.blue.opacity(alpha * 0.28)),
                    style: StrokeStyle(lineWidth: 1, dash: [10, 10])
                )

                var base = Path()
                base.move(to: CGPoint(x: lineStart, y: baseline))
                base.addLine(to: CGPoint(x: lineEnd, y: baseline))
                context.stroke(base, with: .color(.red.opacity(alpha * 0.90)), lineWidth: 1.5)

                var desc = Path()
                desc.move(to: CGPoint(x: lineStart, y: descender))
                desc.addLine(to: CGPoint(x: lineEnd, y: descender))
                context.stroke(desc, with: .color(.blue.opacity(alpha * 0.20)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawLabel(_ label: String, at point: CGPoint, in context: GraphicsContext) {
        context.draw(
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary),
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
