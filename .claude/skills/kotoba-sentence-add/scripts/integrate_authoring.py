#!/usr/bin/env python3
"""agy が生成した候補JSONを person_templates.authoring.json に「追記のみ」で足す。

sentence-bank-build と PersonTemplateAuthoring の両方がデコードできるよう、plain レコード
（slots空・en=fallbackEn・ja=fallbackJa・category=daily）に整えてから足す。既存行は無変更
（差分を追記のみに保ち決定論を守る）。ID衝突は -2/-3… の suffix で回避。

必須フィールド検査: fallbackEn/fallbackJa 非空・grammar は GrammarPoint の rawValue・
gradeBand は 1..5。満たさない候補は skip して報告（黙って落とさない）。

使い方: python3 integrate_authoring.py <agy_out.json> <authoring_path> [category]
"""
import json
import re
import sys

VALID_GRAMMAR = {"presentSimple", "beVerb", "demonstratives", "articles",
                 "canModal", "pronouns", "plurals",
                 # 中学年以降（tier b/c/d）で使う上位段階も許可（ceiling は build 側で判定）
                 "presentContinuous", "negation", "yesNoQuestion", "beVerbPast",
                 "frequencyAdverb", "pastSimple", "comparativeEr", "imperative",
                 "whQuestion", "willGoingTo", "shouldModal", "passiveVoice",
                 "infinitive", "indirectSpeech", "haveToNeedTo", "gerund", "presentPerfect"}


def main():
    agy_path, auth_path = sys.argv[1], sys.argv[2]
    category = sys.argv[3] if len(sys.argv) > 3 else "daily"
    new = json.load(open(agy_path, encoding="utf-8"))
    auth_txt = open(auth_path, encoding="utf-8").read().rstrip()
    assert auth_txt.endswith("]"), "authoring is not a JSON array"
    existing = json.loads(auth_txt)
    existing_ids = {r["id"] for r in existing}

    def uniq(base):
        i, n = base, 2
        while i in existing_ids:
            i = f"{base}-{n}"
            n += 1
        existing_ids.add(i)
        return i

    full, skipped = [], []
    for r in new:
        fe = r.get("fallbackEn") or []
        fj = (r.get("fallbackJa") or "").strip()
        g = r.get("grammar")
        gb = r.get("gradeBand")
        if not fe or not fj:
            skipped.append((r.get("id"), "empty en/ja")); continue
        if g not in VALID_GRAMMAR:
            skipped.append((r.get("id"), f"bad grammar {g}")); continue
        if gb not in (1, 2, 3, 4, 5):
            skipped.append((r.get("id"), f"bad gradeBand {gb}")); continue
        rid = uniq(re.sub(r"[^a-z0-9-]", "", (r.get("id") or "gen").lower()) or "gen")
        full.append({
            "id": rid, "category": category, "grammar": g, "gradeBand": gb,
            "contentLemmas": [], "slots": [],
            "en": fe, "ja": fj, "fallbackEn": fe, "fallbackJa": fj,
        })

    head = auth_txt[:-1].rstrip()
    if head.endswith(","):
        head = head[:-1]
    blocks = []
    for r in full:
        s = json.dumps(r, ensure_ascii=False, indent=2)
        s = "\n".join("  " + ln for ln in s.split("\n"))
        blocks.append(s)
    open(auth_path, "w", encoding="utf-8").write(head + ",\n" + ",\n".join(blocks) + "\n]\n")
    print(f"追記: {len(full)}件  スキップ: {len(skipped)}  (総数 {len(existing)+len(full)})")
    for i, why in skipped:
        print("  skip:", i, why)


if __name__ == "__main__":
    main()
