#!/usr/bin/env python3
"""spec.json + candidates.csv から、背景の生成プロンプトを組み立てて表示する。

house_style と『中央オープン』原則を毎回再掲し、candidates.csv の1行(concept/art_prompt)を差し込む。

使い方:
  python3 build_prompt.py --id sample_zoo                 # image 用(codex/agy)
  python3 build_prompt.py --id sample_zoo --mode procedural  # procedural(SwiftUI著作ブリーフ)
  python3 build_prompt.py --list                          # candidates 一覧
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


def build_image(spec, row):
    hs = spec["house_style"]
    must = "\n".join(f"- {m}" for m in hs["must"])
    ng = "\n".join(f"- {n}" for n in hs["ng"])
    art = (row.get("art_prompt") or "").strip()
    return f"""子ども向けアプリのホーム背景を1枚描いて、PNGファイルとして保存して。これは『舞台/遠景』で、あとでアプリが中央にキャラクターを乗せる。

【シーン】{row['ja_name']} ({row['en_name']})
{row.get('concept','')}

【英語プロンプト(これを主に使う)】
{art}

【画風(必須)】{hs['summary']}
{must}

【中央オープン原則(最重要)】{hs['center_open_rule']}

【禁止】
{ng}

【キャンバス】{spec['canvas']['aspect']}。最終は {spec['canvas']['ship_size']} にリサイズするので、4:3 横長で大きめに生成して。完全不透過のフルフレーム(透過しない・背景の抜けを作らない)。
保存後に 'file <name>.png' で寸法を報告して。"""


def build_procedural(spec, row):
    p = spec["procedural"]
    conv = "\n".join(f"- {c}" for c in p["convention"])
    hs = spec["house_style"]
    return f"""SpellingTrainer のホーム背景を SwiftUI 手続き描画(procedural)で1つ追加する。出荷画像ではなくコードで描くシーン。

【シーン】{row['ja_name']} ({row['en_name']})
{row.get('concept','')}

【対象】{p['target']}

【画風】{hs['summary']}
【中央オープン原則(最重要)】{hs['center_open_rule']}

【規約(必須)】
{conv}

色は candidates.csv で決めた skyTop/skyBottom/groundPrimary/groundSecondary/accent を使う(下記参照)。固定色を焼き込まない。
出力: 追加する HomeBackgroundScene の case 名、HomeBackgroundScenery への描画分岐(Swiftコード)、proceduralThemes に足す HomeBackgroundTheme(...) 行。"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id")
    ap.add_argument("--mode", choices=["image", "procedural"], default="image")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    rows = load_candidates()

    if args.list:
        for r in rows:
            print(f"{r['id']:18} {r['ja_name']:10} {r['en_name']:18} render={r.get('render','?')}")
        return
    if not args.id:
        raise SystemExit("--id か --list を指定")

    row = find(rows, args.id)
    if args.mode == "procedural":
        print(build_procedural(spec, row))
    else:
        print(build_image(spec, row))


if __name__ == "__main__":
    main()
