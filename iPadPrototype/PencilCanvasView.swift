import PencilKit
import SwiftUI
import UIKit

final class DrawingCapture: ObservableObject {
    var latestDrawing = PKDrawing()
}

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var capture: DrawingCapture? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, capture: capture)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 7)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.capture = capture
        if uiView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            uiView.drawing = drawing
            capture?.latestDrawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var capture: DrawingCapture?

        init(drawing: Binding<PKDrawing>, capture: DrawingCapture?) {
            _drawing = drawing
            self.capture = capture
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
            capture?.latestDrawing = canvasView.drawing
        }
    }
}

extension PKDrawing {
    func spellingImage(defaultBounds: CGRect, scale: CGFloat = 3) -> UIImage {
        let drawingBounds = bounds.isNull || bounds.isEmpty ? defaultBounds : bounds.insetBy(dx: -90, dy: -70)
        let strokeImage = image(from: drawingBounds, scale: scale)
        let renderer = UIGraphicsImageRenderer(size: strokeImage.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: strokeImage.size))
            strokeImage.draw(in: CGRect(origin: .zero, size: strokeImage.size))
        }
    }

    func previewImage(
        scale: CGFloat = 2,
        horizontalPadding: CGFloat = 80,
        topPadding: CGFloat = 90,
        bottomPadding: CGFloat = 150
    ) -> UIImage? {
        guard !bounds.isNull, !bounds.isEmpty else {
            return nil
        }

        let drawingBounds = CGRect(
            x: bounds.minX - horizontalPadding,
            y: bounds.minY - topPadding,
            width: bounds.width + horizontalPadding * 2,
            height: bounds.height + topPadding + bottomPadding
        )
        let strokeImage = image(from: drawingBounds, scale: scale)
        let renderer = UIGraphicsImageRenderer(size: strokeImage.size)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: strokeImage.size))
            strokeImage.draw(in: CGRect(origin: .zero, size: strokeImage.size))
        }
    }
}
