#!/usr/bin/env python3
"""wordbank.sqlite の `pos` テーブルのカナリア検証（再生成の事故検知）。

- 主要な定番語の主品詞が期待どおりか。
- カバー率が想定レンジか（劣化検知）。
- 値が {noun,verb,adjective} のみ・キーは小文字。
"""
from __future__ import annotations
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
WORDBANK = os.path.join(REPO, "iPadPrototype", "Resources", "wordbank.sqlite")

EXPECT = {
    "apple": "noun", "milk": "noun", "book": "noun", "dog": "noun", "ball": "noun",
    "run": "verb", "jump": "verb", "swim": "verb", "eat": "verb", "play": "verb",
    "happy": "adjective", "sad": "adjective", "big": "adjective", "tall": "adjective",
}
MIN_ROWS = 30000        # 33k 前後を想定（割り込んだら劣化）
ALLOWED = {"noun", "verb", "adjective"}


def main() -> int:
    con = sqlite3.connect(WORDBANK)
    try:
        rows = con.execute("SELECT word, pos FROM pos").fetchall()
    finally:
        con.close()

    errors: list[str] = []
    by_word = dict(rows)

    if len(rows) < MIN_ROWS:
        errors.append(f"pos 行数が少ない: {len(rows)} < {MIN_ROWS}")

    for w, want in EXPECT.items():
        got = by_word.get(w)
        if got != want:
            errors.append(f"{w}: 期待 {want} だが {got}")

    for w, p in rows:
        if p not in ALLOWED:
            errors.append(f"不正な品詞値: {w!r} -> {p!r}")
            break
        if w != w.lower():
            errors.append(f"キーが小文字でない: {w!r}")
            break

    if errors:
        print("POS 検証 NG:", file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        return 1
    print(f"POS 検証 OK（{len(rows)} 行・主要語一致）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
