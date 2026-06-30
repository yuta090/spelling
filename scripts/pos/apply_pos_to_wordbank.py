#!/usr/bin/env python3
"""凍結済み `word_pos.tsv` を読み、wordbank.sqlite に `pos` テーブルを作る。

- **ネットワーク不要**（refresh とは分離）。ビルド/再生成はこれだけで完結。
- `pos(word TEXT PRIMARY KEY, pos TEXT NOT NULL)` を drop→create→insert（語昇順）→ VACUUM。
  キーは小文字（アプリ側も lower(word) で引く）。差分が安定するよう昇順固定。
- 値は "noun" / "verb" / "adjective"（StarterSpellingFrames の allowedPOS と一致）。

使い方:
  python3 scripts/pos/apply_pos_to_wordbank.py
"""
from __future__ import annotations
import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
WORDBANK = os.path.join(REPO, "iPadPrototype", "Resources", "wordbank.sqlite")
IN_TSV = os.path.join(HERE, "word_pos.tsv")

ALLOWED = {"noun", "verb", "adjective"}


def load_pairs(path: str) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    with open(path, encoding="utf-8") as f:
        for ln, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line:
                continue
            word, _, pos = line.partition("\t")
            if pos not in ALLOWED:
                raise ValueError(f"{path}:{ln}: 不正な品詞 {pos!r}")
            pairs.append((word.lower(), pos))
    pairs.sort()
    return pairs


def main() -> int:
    pairs = load_pairs(IN_TSV)
    con = sqlite3.connect(WORDBANK)
    try:
        con.execute("DROP TABLE IF EXISTS pos")
        con.execute("CREATE TABLE pos(word TEXT PRIMARY KEY, pos TEXT NOT NULL)")
        con.executemany("INSERT OR REPLACE INTO pos(word, pos) VALUES (?, ?)", pairs)
        con.commit()
        con.execute("VACUUM")
        con.commit()
        n = con.execute("SELECT COUNT(*) FROM pos").fetchone()[0]
    finally:
        con.close()
    print(f"pos rows written: {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
