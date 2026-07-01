#!/usr/bin/env python3
"""作りたい『なかま』が、既存173種(scripts/characters.csv)と被っていないか調べる。

既存カタログ(アプリの本物)を参照して、id / 日本語名 / 英語名 で
完全一致・部分一致・似た名前(あいまい一致)を報告する。

使い方:
  python3 check_duplicate.py ハムスター            # 1件チェック
  python3 check_duplicate.py seal あざらし penguin  # 複数まとめて
  python3 check_duplicate.py --category animal      # そのカテゴリの既存一覧を見る
  python3 check_duplicate.py --all                  # 全件(カテゴリ別)
  python3 check_duplicate.py --tag sea,fish         # タグで絞り込み(複数=AND)
  python3 check_duplicate.py --tags                 # 付いている全タグを件数つきで一覧
"""
import argparse
import csv
import sys
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path


def find_catalog():
    """skill からリポジトリの scripts/characters.csv を上方向に探す。"""
    here = Path(__file__).resolve()
    for base in here.parents:
        cand = base / "scripts" / "characters.csv"
        if cand.exists() and cand != here:  # skill 自身の candidates.csv ではない
            # characters.csv であることを確認
            if cand.name == "characters.csv":
                return cand
    raise SystemExit("characters.csv が見つからない（リポジトリ内で実行して）")


def norm(s: str) -> str:
    return unicodedata.normalize("NFKC", (s or "").strip()).lower()


def ratio(a: str, b: str) -> float:
    return SequenceMatcher(None, norm(a), norm(b)).ratio()


def load(catalog):
    with open(catalog, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def tags_of(r) -> list:
    return [t for t in (r.get("tags") or "").split(";") if t]


def check_one(rows, query):
    q = norm(query)
    exact, contains, fuzzy = [], [], []
    for r in rows:
        fields = {r["id"], r["ja_name"], r["en_name"]}
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
            tg = ";".join(tags_of(r))
            print(f"  ⛔ 既に存在: id={r['id']}  {r['ja_name']}/{r['en_name']}  ({r['category']}, style={r['style']}){'  [' + tg + ']' if tg else ''}")
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
    ap.add_argument("--tag", help="このタグを持つなかまを一覧（カンマ区切りで AND）")
    ap.add_argument("--tags", action="store_true", help="付いている全タグを件数つきで一覧")
    ap.add_argument("--catalog", help="characters.csv のパスを明示（既定は上方向に自動探索）")
    args = ap.parse_args()

    catalog = Path(args.catalog) if args.catalog else find_catalog()
    rows = load(catalog)
    print(f"既存なかま: {len(rows)}種  ({catalog})")

    if args.tags:
        from collections import Counter
        c = Counter(t for r in rows for t in tags_of(r))
        if not c:
            print("（tags 列が空。characters.csv に tags が無いかも）")
            return
        print(f"\nタグ一覧（{len(c)}種）:")
        for t, n in sorted(c.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"  {n:3d}  {t}")
        return

    if args.tag:
        want = [norm(t) for t in args.tag.split(",") if t.strip()]
        hits = [r for r in rows if all(w in {norm(x) for x in tags_of(r)} for w in want)]
        print(f"\nタグ [{', '.join(want)}] を持つなかま: {len(hits)}種")
        for r in hits:
            print(f"  id={r['id']}  {r['ja_name']}/{r['en_name']}  ({r['category']})  [{';'.join(tags_of(r))}]")
        return

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
