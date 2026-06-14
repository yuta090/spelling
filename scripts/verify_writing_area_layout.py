#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "iPadPrototype" / "Models.swift"
GUIDED = ROOT / "iPadPrototype" / "GuidedWritingCanvas.swift"
SESSION = ROOT / "iPadPrototype" / "SpellingSessionView.swift"
PARENT = ROOT / "iPadPrototype" / "ParentDashboardView.swift"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    models = MODELS.read_text()
    guided = GUIDED.read_text()
    session = SESSION.read_text()
    parent = PARENT.read_text()

    require("return 0.66" in models, "Compact writing area must be visibly smaller.")
    require("return 1.28" in models and "return 1.55" in models, "Large sizes must create a visible difference.")
    require("var usesTwoColumnPracticeLayout: Bool" in models, "Compact two-column layout flag is missing.")
    require("self == .compact" in models, "Only compact size should enable two-column practice.")

    require("var minimumHeight: CGFloat = 285" in guided, "GuidedWritingCanvas must keep a default fallback height.")
    require(".frame(minHeight: minimumHeight)" in guided, "GuidedWritingCanvas must honor caller-provided minimum height.")
    require("sampleTextFontSize" in guided and "size.height * 0.35" in guided,
            "Model-word font size must scale with the actual canvas height.")

    require("usesCompactPracticeGrid" in session, "SpellingSessionView must branch for compact practice.")
    require("CompactPracticeWritingCell" in session, "Compact practice writing cell is missing.")
    require("LazyVGrid(columns: compactPracticeGridColumns" in session, "Compact practice must use a two-column grid.")
    require("minimumHeight: 0" in session, "Session canvases must be allowed to shrink below the old fixed minimum.")
    require("saveCompactPracticeDrawings" in session, "Compact practice drawings must be saved per word.")
    require("canvasSize: compactPracticeCanvasSize(for: word.id)" in session,
            "Compact practice must save each cell's actual canvas size.")
    require("model.awardPracticeCoins(AppModel.practiceCoinReward * completedWords)" in session,
            "Compact practice should reward every completed word in the batch.")

    require("書く欄の高さと、お手本の文字サイズ" in parent,
            "Parent settings copy must describe the real size behavior.")

    print("writing area layout checks passed")


if __name__ == "__main__":
    main()
