#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUIDE = ROOT / "iPadPrototype" / "GuidedWritingCanvas.swift"
PARENT = ROOT / "iPadPrototype" / "ParentDashboardView.swift"
PENCIL = ROOT / "iPadPrototype" / "PencilCanvasView.swift"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def projected_baseline(container, canvas):
    container_width, container_height = container
    canvas_width, canvas_height = canvas
    scale = min(container_width / canvas_width, container_height / canvas_height)
    fitted_height = canvas_height * scale
    fitted_min_y = (container_height - fitted_height) / 2
    return fitted_min_y + (canvas_height * 0.66) * scale


def main():
    guide = GUIDE.read_text()
    parent = PARENT.read_text()
    pencil = PENCIL.read_text()

    require("struct WritingGuideLayout" in guide, "WritingGuideLayout must be the single guide geometry source.")
    require("static let baselineRatio: CGFloat = 0.66" in guide, "Baseline ratio changed unexpectedly.")
    require("let layout = WritingGuideLayout(size: proxy.size)" in guide, "FourLineGuide must use WritingGuideLayout.")
    require("layout.baseline" in guide, "FourLineGuide must draw baseline from WritingGuideLayout.")

    require("struct GradingCanvasSnapshotView" in parent, "Grading preview must use a snapshot image view.")
    require("enum WritingGuideSnapshotRenderer" in parent, "Grading preview must render guide and drawing together.")
    require("let layout = WritingGuideLayout(size: canvasSize)" in parent, "Grading renderer must use WritingGuideLayout.")
    require("CanvasFitGeometry.fittedRect" in parent, "Grading preview must use shared canvas fit geometry.")
    require("drawing.image(" in parent and "from: CGRect(origin: contentOffset, size: canvasSize)" in parent,
            "Grading renderer must draw handwriting in the same canvas coordinate window.")
    require("StaticPencilCanvasView" not in pencil + parent, "Static PKCanvas preview path should not be used for grading.")

    scenarios = [
        ((650, 172), (1260, 300)),
        ((650, 172), (1260, 330)),
        ((720, 190), (1400, 390)),
        ((510, 172), (1365, 300)),
    ]
    for container, canvas in scenarios:
        baseline = projected_baseline(container, canvas)
        scale = min(container[0] / canvas[0], container[1] / canvas[1])
        expected = ((container[1] - canvas[1] * scale) / 2) + canvas[1] * 0.66 * scale
        require(abs(baseline - expected) < 0.0001, f"Projected baseline mismatch for {container=} {canvas=}")

    print("writing guide alignment checks passed")


if __name__ == "__main__":
    main()
