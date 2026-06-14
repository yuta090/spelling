#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SESSION = ROOT / "iPadPrototype" / "SpellingSessionView.swift"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def function_body(source: str, name: str) -> str:
    marker = f"private func {name}"
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[brace:index + 1]
    raise AssertionError(f"Could not parse {name}")


def main():
    source = SESSION.read_text()
    clear_body = function_body(source, "clearCanvas()")
    undo_body = function_body(source, "undoLastStroke()")
    tick_body = function_body(source, "tickTimer()")
    check_body = function_body(source, "checkAnswer()")

    require("resetTimer()" not in clear_body, "Clear must not reset the test timer.")
    require("startTimerIfNeeded()" not in clear_body, "Clear must not restart the test timer.")
    require("resetTimer()" not in undo_body, "Undo must not reset the test timer.")
    require("startTimerIfNeeded()" not in undo_body, "Undo must not restart the test timer.")
    require("decision == nil" not in tick_body, "Timer must keep counting while rewrite feedback is shown.")
    require("decision != .timeExpired" in tick_body, "Timer should only stop counting after time expired.")

    stop_index = check_body.index("stopTimer()")
    no_ink_index = check_body.index("guard hasInk(submittedDrawing)")
    require(stop_index > no_ink_index, "No-ink rewrite must not stop the timer before feedback.")

    print("test timer rewrite checks passed")


if __name__ == "__main__":
    main()
