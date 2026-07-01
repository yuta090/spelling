#!/usr/bin/env python3
"""spec.json + candidates.csv から、生成プロンプトを組み立てて表示する。

house_style を毎回再掲し、candidates.csv の1行(concept/色)を差し込む。
agy(explore=白背景) と codex(finalize=マゼンタ背景) で背景指示だけ切り替える。

使い方:
  python3 build_prompt.py --id sample_hamster                 # explore 用(白背景)
  python3 build_prompt.py --id sample_hamster --mode finalize # finalize 用(マゼンタ背景)
  python3 build_prompt.py --list                              # candidates 一覧
"""
import argparse
import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SPEC = ROOT / "spec.json"
CSV = ROOT / "candidates.csv"


def load_candidates():
    with open(CSV, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def find(rows, cid):
    for r in rows:
        if r["id"] == cid:
            return r
    raise SystemExit(f"id not found: {cid}. 一覧は --list")


def build(spec, row, mode):
    hs = spec["house_style"]
    must = "\n".join(f"- {m}" for m in hs["must"])
    ng = "\n".join(f"- {n}" for n in hs["ng"])
    if mode == "finalize":
        bg = f"背景は {spec['finalize_image']['chroma_key']} のマゼンタ単色べた塗り(後でクロマキー透過する)。被写体にマゼンタを使わない。"
    else:
        bg = f"背景は {spec['explore']['background']}。"

    return f"""かわいい子ども向けマスコットキャラを1体だけ描いて、PNGファイルとして保存して。

【キャラ】{row['ja_name']} ({row['en_name']})
{row['concept']}

【配色】
- 主役色 primary: {row['primary_hex']}
- 補助色 secondary: {row['secondary_hex']}
- 差し色 accent: {row['accent_hex']}

【画風(必須)】{hs['summary']}
{must}

【禁止】
{ng}

【背景】{bg}
【キャンバス】1:1 の正方形・大きめ(1024程度)。
{spec['house_style']['palette_rule']}"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id")
    ap.add_argument("--mode", choices=["explore", "finalize"], default="explore")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    rows = load_candidates()

    if args.list:
        for r in rows:
            print(f"{r['id']:24} {r['ja_name']:8} {r['en_name']:12} variations={r.get('variations','?')}")
        return
    if not args.id:
        raise SystemExit("--id か --list を指定")

    print(build(spec, find(rows, args.id), args.mode))


if __name__ == "__main__":
    main()
