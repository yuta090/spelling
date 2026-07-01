#!/usr/bin/env python3
"""作りたいホーム背景が、既存カタログ(scripts/backgrounds.csv)と被っていないか調べる。

既存(アプリの本物)を参照して、id / 日本語名 / 英語名 で
完全一致・部分一致・似た名前(あいまい一致)を報告する。

使い方:
  python3 check_duplicate.py どうぶつえん            # 1件チェック
  python3 check_duplicate.py zoo どうぶつえん library  # 複数まとめて
  python3 check_duplicate.py --category nature        # そのカテゴリの既存一覧
  python3 check_duplicate.py --all                    # 全件(カテゴリ別)
"""
import argparse
import csv
import sys
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path


def find_catalog():
    """skill からリポジトリの scripts/backgrounds.csv を上方向に探す。"""
    here = Path(__file__).resolve()
    for base in here.parents:
        cand = base / "scripts" / "backgrounds.csv"
        if cand.exists() and cand.name == "backgrounds.csv":
            return cand
    raise SystemExit("backgrounds.csv が見つからない（リポジトリ内で実行して）")


def norm(s: str) -> str:
    return unicodedata.normalize("NFKC", (s or "").strip()).lower()


def ratio(a: str, b: str) -> float:
    return SequenceMatcher(None, norm(a), norm(b)).ratio()


def load(catalog):
    with open(catalog, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def check_one(rows, query):
    q = norm(query)
    exact, contains, fuzzy = [], [], []
    for r in rows:
        fields = {r.get("id", ""), r.get("ja_name", ""), r.get("en_name", "")}
        nf = {norm(x) for x in fields}
        if q in nf:
            exact.append(r)
            continue
        if any(q and (q in x or x in q) for x in nf):
            contains.append(r)
            continue
        best = max(ratio(query, x) for x in fields)
        if best >= 0.7:
            fuzzy.append((best, r))
    fuzzy.sort(reverse=True)

    print(f"\n■ 『{query}』")
    if exact:
        for r in exact:
            print(f"  ⛔ 既に存在: id={r['id']}  {r['ja_name']}/{r['en_name']}  ({r['category']}, render={r.get('render','?')})")
    if contains:
        for r in contains:
            print(f"  ⚠ 名前が近い: id={r['id']}  {r['ja_name']}/{r['en_name']}  ({r['category']})")
    for sc, r in fuzzy[:5]:
        print(f"  ・似てるかも({sc:.0%}): id={r['id']}  {r['ja_name']}/{r['en_name']}  ({r['category']})")
    if not exact and not contains and not fuzzy:
        print("  ✅ 新規（既存と被りなし）")
    return bool(exact)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("queries", nargs="*")
    ap.add_argument("--category")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()

    catalog = find_catalog()
    rows = load(catalog)
    print(f"既存背景: {len(rows)}種  ({catalog})")

    if args.all or args.category:
        from collections import defaultdict
        by = defaultdict(list)
        for r in rows:
            by[r["category"]].append(r)
        cats = [args.category] if args.category else sorted(by)
        for c in cats:
            items = by.get(c, [])
            print(f"\n[{c}] {len(items)}種")
            print("  " + " / ".join(f"{r['ja_name']}({r['en_name']})" for r in items))
        return

    if not args.queries:
        raise SystemExit("チェックしたい名前を渡すか、--all / --category を指定")

    any_dup = False
    for q in args.queries:
        any_dup |= check_one(rows, q)
    print()
    sys.exit(1 if any_dup else 0)  # 重複があれば exit 1


if __name__ == "__main__":
    main()
