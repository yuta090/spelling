import PencilKit
import SwiftUI

enum PracticeMode {
    case practice
    case test
}

struct GuidedWritingCanvas: View {
    @Binding var drawing: PKDrawing
    var mode: PracticeMode

    var body: some View {
        ZStack {
            FourLineGuide(mode: mode)
            PencilCanvasView(drawing: $drawing)
        }
        .frame(minHeight: 260)
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

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let alpha = mode == .practice ? 0.70 : 0.38
            let top = height * 0.22
            let mid = height * 0.40
            let baseline = height * 0.66
            let descender = height * 0.84

            Canvas { context, _ in
                var line = Path()
                line.move(to: CGPoint(x: 24, y: top))
                line.addLine(to: CGPoint(x: width - 24, y: top))
                context.stroke(line, with: .color(.blue.opacity(alpha * 0.20)), lineWidth: 1)

                var midLine = Path()
                midLine.move(to: CGPoint(x: 24, y: mid))
                midLine.addLine(to: CGPoint(x: width - 24, y: mid))
                context.stroke(
                    midLine,
                    with: .color(.blue.opacity(alpha * 0.28)),
                    style: StrokeStyle(lineWidth: 1, dash: [10, 10])
                )

                var base = Path()
                base.move(to: CGPoint(x: 24, y: baseline))
                base.addLine(to: CGPoint(x: width - 24, y: baseline))
                context.stroke(base, with: .color(.gray.opacity(alpha)), lineWidth: 2)

                var desc = Path()
                desc.move(to: CGPoint(x: 24, y: descender))
                desc.addLine(to: CGPoint(x: width - 24, y: descender))
                context.stroke(desc, with: .color(.blue.opacity(alpha * 0.20)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
