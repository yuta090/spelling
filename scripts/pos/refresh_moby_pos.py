#!/usr/bin/env python3
"""Moby Part-of-Speech から、同梱辞書（wordbank.sqlite gloss）の各語に
英語の主品詞（noun/verb/adjective）を割り当てた `word_pos.tsv` を再生成する。

- データ出典: Moby Project — Part-of-Speech List（Grady Ward, **パブリックドメイン**）。
  ここでは Kevin Atkinson の en-wl/wordlist ミラーから取得する。
- このスクリプトは**ネットワークを使う**（refresh 時のみ）。生成物 `word_pos.tsv` を
  repo に凍結し、アプリ用 sqlite はそれから `apply_pos_to_wordbank.py` で組む
  （＝ビルド時はネット不要・差分安定）。
- 決定論: 入力（Moby 固定 sha256 ＋ gloss 語）が同じなら出力は同じ。語順は昇順固定。

主品詞ルール（多義語の決定）:
  Moby はコードを主用法順に並べる傾向がある（run=VitN, play=VtiNA, milk=NVitA, big=Av）。
  よって**左から最初に当たる品詞コード**を主品詞にする:
    N / p / h → noun, V / t / i → verb, A → adjective（v=副詞などは無視）。
  さらに固有名詞（大文字始まり）より**小文字見出しを優先**（Happy=N より happy=A!）。

使い方:
  python3 scripts/pos/refresh_moby_pos.py            # ダウンロードして再生成
  python3 scripts/pos/refresh_moby_pos.py --moby-file <path>  # 既存ファイルから
"""
from __future__ import annotations
import argparse
import hashlib
import os
import sqlite3
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
WORDBANK = os.path.join(REPO, "iPadPrototype", "Resources", "wordbank.sqlite")
OUT_TSV = os.path.join(HERE, "word_pos.tsv")

# en-wl/wordlist ミラー（master）。内容が変わったら EXPECTED_SHA256 で気づける。
MOBY_URL = "https://raw.githubusercontent.com/en-wl/wordlist/master/pos/part-of-speech.txt"
EXPECTED_SHA256 = "53ecca51dce90318d67a994aa8b9cd184dc442b65c10f5d87708586bf120b4e9"

NOUN_CODES = set("Nph")
VERB_CODES = set("Vti")
ADJ_CODES = set("A")

_AZ = set("abcdefghijklmnopqrstuvwxyz")


def normalize(word: str) -> str:
    """アプリ側 `normalize`（Models.swift）と同一: 小文字化して a-z だけ残す。
    pos テーブルのキーはこの形にして、アプリの引き方と必ず一致させる。"""
    return "".join(ch for ch in word.lower() if ch in _AZ)


def primary_pos(codes: str) -> str | None:
    """コード列の左から最初に当たる品詞を主品詞として返す。無ければ None。"""
    for ch in codes:
        if ch in NOUN_CODES:
            return "noun"
        if ch in VERB_CODES:
            return "verb"
        if ch in ADJ_CODES:
            return "adjective"
    return None


def load_moby(text: str) -> dict[str, str]:
    """lower(見出し) -> コード列。小文字見出しを優先（固有名詞を避ける）。"""
    low: dict[str, str] = {}
    cap: dict[str, str] = {}
    for line in text.splitlines():
        if "\t" not in line:
            continue
        head, codes = line.split("\t", 1)
        key = head.lower()
        if head == key:
            low.setdefault(key, codes)      # 小文字見出し（普通名詞・動詞など）
        else:
            cap.setdefault(key, codes)      # 大文字始まり（固有名詞）はフォールバック
    merged = dict(cap)
    merged.update(low)                      # 小文字優先で上書き
    return merged


def gloss_words(db_path: str) -> list[str]:
    """gloss の語を**元の表記のまま**昇順で返す（Moby 照合は元表記が当たりやすい）。"""
    con = sqlite3.connect(db_path)
    try:
        rows = con.execute("SELECT DISTINCT word FROM gloss").fetchall()
    finally:
        con.close()
    return sorted({r[0] for r in rows if r[0]})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--moby-file", help="既存の Moby POS ファイル（未指定ならダウンロード）")
    ap.add_argument("--allow-sha-mismatch", action="store_true",
                    help="Moby の sha256 が変わっていても続行（refresh を意図的に更新する時）")
    args = ap.parse_args()

    if args.moby_file:
        with open(args.moby_file, "rb") as f:
            raw = f.read()
    else:
        print(f"downloading Moby POS: {MOBY_URL}")
        with urllib.request.urlopen(MOBY_URL, timeout=60) as resp:
            raw = resp.read()

    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SHA256:
        msg = (f"Moby sha256 mismatch:\n  got      {digest}\n  expected {EXPECTED_SHA256}\n"
               "上流が変わった可能性。中身を確認して EXPECTED_SHA256 を更新するか、"
               "--allow-sha-mismatch で続行。")
        if not args.allow_sha_mismatch:
            print(msg, file=sys.stderr)
            return 2
        print("WARNING: " + msg, file=sys.stderr)

    moby = load_moby(raw.decode("utf-8", errors="replace"))
    words = gloss_words(WORDBANK)

    # キーはアプリと同じ a-z 正規化形。元表記（ハイフン等含む）→ 無ければ正規化形で Moby を引く。
    # 正規化キーが衝突したら昇順で最初の語を採用（決定論）。
    pos_by_key: dict[str, str] = {}
    counts = {"noun": 0, "verb": 0, "adjective": 0}
    for w in words:
        key = normalize(w)
        if not key or key in pos_by_key:
            continue
        codes = moby.get(w.lower()) or moby.get(key)
        if not codes:
            continue
        pos = primary_pos(codes)
        if pos is None:
            continue
        pos_by_key[key] = pos
        counts[pos] += 1

    pairs = sorted(pos_by_key.items())
    with open(OUT_TSV, "w", encoding="utf-8") as f:
        for w, pos in pairs:
            f.write(f"{w}\t{pos}\n")

    total = len(words)
    print(f"gloss words            : {total}")
    print(f"with primary POS       : {len(pairs)} ({100*len(pairs)/total:.1f}%)")
    print(f"  noun / verb / adj    : {counts['noun']} / {counts['verb']} / {counts['adjective']}")
    print(f"wrote                  : {OUT_TSV}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
