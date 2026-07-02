import PencilKit
import SwiftUI
import UIKit

final class DrawingCapture: ObservableObject {
    var latestDrawing = PKDrawing()
    var latestContentOffset: CGPoint = .zero
}

@MainActor
private func configurePencilCanvas(_ canvas: PKCanvasView, isInputEnabled: Bool) {
    // ダークモードでも線が白に反転しないよう、キャンバスは常にライト外観で描画する
    canvas.overrideUserInterfaceStyle = .light
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    canvas.drawingPolicy = .anyInput
    canvas.isUserInteractionEnabled = isInputEnabled
    canvas.contentInsetAdjustmentBehavior = .never
    canvas.contentInset = .zero
    canvas.scrollIndicatorInsets = .zero
    canvas.bounces = false
    canvas.alwaysBounceHorizontal = false
    canvas.alwaysBounceVertical = false
    canvas.minimumZoomScale = 1
    canvas.maximumZoomScale = 1
    if canvas.zoomScale != 1 {
        canvas.zoomScale = 1
    }
    if canvas.bounds.size.width > 0, canvas.bounds.size.height > 0 {
        canvas.contentSize = canvas.bounds.size
    }
    if canvas.contentOffset != .zero {
        canvas.setContentOffset(.zero, animated: false)
    }
}

private final class FixedCoordinatePKCanvasView: PKCanvasView {
    override func layoutSubviews() {
        let inputEnabled = isUserInteractionEnabled
        super.layoutSubviews()
        configurePencilCanvas(self, isInputEnabled: inputEnabled)
    }
}

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var capture: DrawingCapture? = nil
    var isInputEnabled = true

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, capture: capture)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = FixedCoordinatePKCanvasView()
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: .black, width: 7)
        configurePencilCanvas(canvas, isInputEnabled: isInputEnabled)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.capture = capture
        configurePencilCanvas(uiView, isInputEnabled: isInputEnabled)
        capture?.latestContentOffset = uiView.contentOffset
        if uiView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            uiView.drawing = drawing
            capture?.latestDrawing = drawing
            capture?.latestContentOffset = uiView.contentOffset
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
            capture?.latestContentOffset = canvasView.contentOffset
        }
    }
}

extension PKDrawing {
    enum PreviewHorizontalAlignment {
        case centered
        case leftAnchored
    }

    /// PKDrawing.image(from:scale:) は現在の外観（ダークモード）で色を反転するため、
    /// 白背景に合成する用途では常にライト外観でレンダリングする。
    private func lightModeImage(from rect: CGRect, scale: CGFloat) -> UIImage {
        var rendered = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = image(from: rect, scale: scale)
        }
        return rendered
    }

    func spellingImage(defaultBounds: CGRect, scale: CGFloat = 3) -> UIImage {
        let drawingBounds = bounds.isNull || bounds.isEmpty ? defaultBounds : bounds.insetBy(dx: -90, dy: -70)
        let strokeImage = lightModeImage(from: drawingBounds, scale: scale)
        let renderer = UIGraphicsImageRenderer(size: strokeImage.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: strokeImage.size))
            strokeImage.draw(in: CGRect(origin: .zero, size: strokeImage.size))
        }
    }

    func previewImage(
        scale: CGFloat = 2,
        horizontalPadding: CGFloat = 90,
        topPadding: CGFloat = 170,
        bottomPadding: CGFloat = 210,
        horizontalAlignment: PreviewHorizontalAlignment = .centered,
        minimumAspectRatio: CGFloat? = nil,
        targetAspectRatio: CGFloat? = nil,
        canvasSize: DrawingCanvasSize? = nil,
        rightPadding: CGFloat? = nil
    ) -> UIImage? {
        guard !bounds.isNull, !bounds.isEmpty else {
            return nil
        }

        var drawingBounds: CGRect
        let cropHeight = bounds.height + topPadding + bottomPadding
        switch horizontalAlignment {
        case .centered:
            let cropWidth = max(
                bounds.width + horizontalPadding * 2,
                cropHeight * (minimumAspectRatio ?? 0)
            )
            drawingBounds = CGRect(
                x: bounds.midX - cropWidth / 2,
                y: bounds.minY - topPadding,
                width: cropWidth,
                height: cropHeight
            )
        case .leftAnchored:
            let left = bounds.minX - horizontalPadding
            let naturalWidth = bounds.maxX + (rightPadding ?? horizontalPadding) - left
            let cropWidth = max(
                naturalWidth,
                cropHeight * (minimumAspectRatio ?? 0)
            )
            drawingBounds = CGRect(
                x: left,
                y: bounds.minY - topPadding,
                width: cropWidth,
                height: cropHeight
            )
        }

        let resolvedTargetAspectRatio = targetAspectRatio ?? canvasSize?.aspectRatio.map { CGFloat($0) }
        if let resolvedTargetAspectRatio, resolvedTargetAspectRatio > 0 {
            drawingBounds = drawingBounds.expanded(toAspectRatio: resolvedTargetAspectRatio, horizontalAlignment: horizontalAlignment)
        }

        let strokeImage = lightModeImage(from: drawingBounds, scale: scale)
        let renderer = UIGraphicsImageRenderer(size: strokeImage.size)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: strokeImage.size))
            strokeImage.draw(in: CGRect(origin: .zero, size: strokeImage.size))
        }
    }
}

private extension CGRect {
    func expanded(toAspectRatio targetAspectRatio: CGFloat, horizontalAlignment: PKDrawing.PreviewHorizontalAlignment) -> CGRect {
        guard width > 0, height > 0 else {
            return self
        }

        let currentAspectRatio = width / height
        if currentAspectRatio < targetAspectRatio {
            let newWidth = height * targetAspectRatio
            let extraWidth = newWidth - width
            switch horizontalAlignment {
            case .centered:
                return CGRect(x: minX - extraWidth / 2, y: minY, width: newWidth, height: height)
            case .leftAnchored:
                return CGRect(x: minX, y: minY, width: newWidth, height: height)
            }
        }

        let newHeight = width / targetAspectRatio
        let extraHeight = newHeight - height
        return CGRect(x: minX, y: minY - extraHeight / 2, width: width, height: newHeight)
    }
}
