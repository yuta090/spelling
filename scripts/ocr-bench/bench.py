#!/usr/bin/env python3
"""
OCR ベンチ — §7 の方法論（同一画像を全候補モデルに横並びで通す）。

測る指標:
  - OCR精度         : predicted_word == ground_truth
  - 誤受理(FA)       : 本当は不正解なのに「正解」と判定（最重要・親の信頼が死ぬ）
  - 誤拒否(FR)       : 本当は正解なのに「不正解」と判定
  - 判読不能の扱い   : legible=false のサンプルで捏造せず「読めない」と返せるか
  - レイテンシ       : 即フィードバックに耐えるか（OpenRouter経由なので上限値の目安）
  - コメント品質     : CSV に出力。安いモデルで足りるかは人手で目視評価

画像ソース:
  - Supabase（推奨）: ocr_bench_samples テーブル + Storage バケット ocr-bench
  - ローカル fallback: ./samples/ ディレクトリ + ./labels.csv

必要な環境変数:
  OPENROUTER_API_KEY                （必須）
  SUPABASE_URL / SUPABASE_SERVICE_KEY（Supabase モード時）

使い方:
  pip install requests
  export OPENROUTER_API_KEY=sk-or-...
  export SUPABASE_URL=https://xxx.supabase.co
  export SUPABASE_SERVICE_KEY=eyJ...        # service_role キー（RLSバイパス）
  python3 bench.py                          # 結果は results-YYYYMMDD-HHMMSS.csv
"""

import base64
import csv
import json
import os
import re
import sys
import time
from datetime import datetime

import requests

# ─── 設定 ─────────────────────────────────────────────────────────────
# 候補モデル。slug は openrouter.ai/models で正確な値と「画像入力対応」を必ず確認。
# 安いモデル優先で。コメント品質も含めてまず安いモデルで足りるか見る（Haiku前提にしない）。
MODELS = [
    "google/gemini-2.5-flash-lite",  # 最安vision $0.10/$0.40
    "openai/gpt-5.4-nano",           # OpenAIの安いvision $0.20/$1.25（無印 gpt-5-nano はvision非対応表記なので不可）
    "anthropic/claude-haiku-4.5",    # vision対応 $1/$5。フォールバック候補。安いモデルで足りれば外す
]

# 各モデルに同じプロンプトを投げる。捏造禁止を強く明示。
SYSTEM_PROMPT = (
    "あなたは日本の子どもの英単語スペル練習を採点します。"
    "画像には手書きの英単語が1つあります。出題語は「{target}」です。\n"
    "ルール:\n"
    "1. 画像に実際に書かれている文字をそのまま読む（推測で補完しない）。\n"
    "2. 読めない／自信が無い場合は legible を false にし、predicted_word は空にする。"
    "それっぽい単語を捏造しない。\n"
    "3. matches_target は『書かれた文字が出題語の正しい綴りか』。\n"
    "4. comment は子向けの短い日本語。正解なら空、間違い/読めない時だけ一言。\n"
    "次のJSONだけを返す（前後に文章を付けない）:\n"
    '{{"predicted_word": "", "legible": true, "matches_target": true, "comment": ""}}'
)

REQUEST_TIMEOUT = 60
# ──────────────────────────────────────────────────────────────────────


def load_dotenv():
    """同ディレクトリの .env を読む（python-dotenv不要の簡易ローダ）。既存の環境変数は上書きしない。"""
    p = os.path.join(os.path.dirname(__file__), ".env")
    if not os.path.exists(p):
        return
    with open(p, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def norm(s: str) -> str:
    return re.sub(r"\s+", "", (s or "").strip().lower())


def b64_data_url(image_bytes: bytes, path: str) -> str:
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    mime = {"jpg": "jpeg", "jpeg": "jpeg", "png": "png", "webp": "webp", "gif": "gif"}.get(ext, "png")
    return f"data:image/{mime};base64,{base64.b64encode(image_bytes).decode()}"


# ─── サンプル取得 ─────────────────────────────────────────────────────
def load_samples_supabase():
    url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_KEY"]
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    # ラベル済み（ground_truth が入っている）行だけを対象にする。未ラベルの収集行は除外。
    r = requests.get(
        f"{url}/rest/v1/ocr_bench_samples",
        params={
            "select": "id,storage_path,target,ground_truth,legible",
            "ground_truth": "not.is.null",
        },
        headers=headers, timeout=REQUEST_TIMEOUT,
    )
    r.raise_for_status()
    rows = r.json()
    if not rows:
        print("⚠ ラベル済みサンプルが0件。Supabaseで ground_truth / legible を埋めてから再実行してください。")
    samples = []
    for row in rows:
        obj = requests.get(
            f"{url}/storage/v1/object/ocr-bench/{row['storage_path']}",
            headers=headers, timeout=REQUEST_TIMEOUT,
        )
        obj.raise_for_status()
        samples.append({
            "id": row["id"],
            "path": row["storage_path"],
            "target": row["target"],
            "label_kind": "ground_truth",
            "ground_truth": row["ground_truth"],
            "legible_truth": bool(row["legible"]),
            "image": obj.content,
        })
    return samples


def load_samples_local():
    # ./samples + ./labels.csv。2 形式に両対応:
    #  (1) 親判定ラベル形式（暫定A・アプリのデバッグ書き出し）:
    #      filename,target,verdict(correct/incorrect/unreviewed),recognized_text,mode,source,date
    #      → label_kind="verdict"。unreviewed はラベル無しなので除外。
    #  (2) 旧 ground_truth 形式: path,target,ground_truth,legible → label_kind="ground_truth"。
    base = os.path.join(os.path.dirname(__file__), "samples")
    csv_path = os.path.join(os.path.dirname(__file__), "labels.csv")
    samples = []
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        cols = reader.fieldnames or []
        verdict_mode = "verdict" in cols
        for row in reader:
            fname = (row.get("filename") or row.get("path") or "").strip()
            if not fname:
                continue
            p = os.path.join(base, fname)
            if verdict_mode:
                v = (row.get("verdict") or "").strip().lower()
                if v not in ("correct", "incorrect"):
                    continue  # unreviewed 等は真値ラベルが無いので対象外
                with open(p, "rb") as img:
                    samples.append({
                        "id": fname, "path": fname, "target": row["target"],
                        "label_kind": "verdict",
                        "verdict_correct": (v == "correct"),
                        "recognized_text": (row.get("recognized_text") or ""),
                        "image": img.read(),
                    })
            else:
                with open(p, "rb") as img:
                    samples.append({
                        "id": fname, "path": fname, "target": row["target"],
                        "label_kind": "ground_truth",
                        "ground_truth": row.get("ground_truth", ""),
                        "legible_truth": (row.get("legible", "true") or "true").strip().lower() != "false",
                        "image": img.read(),
                    })
    return samples


# ─── 1リクエスト ─────────────────────────────────────────────────────
def call_model(model: str, sample: dict) -> dict:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT.format(target=sample["target"])},
            {"role": "user", "content": [
                {"type": "text", "text": f"出題語: {sample['target']}"},
                {"type": "image_url", "image_url": {"url": b64_data_url(sample["image"], sample["path"])}},
            ]},
        ],
        "max_tokens": 200,
    }
    t0 = time.time()
    r = requests.post(
        "https://openrouter.ai/api/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {os.environ['OPENROUTER_API_KEY']}",
            "Content-Type": "application/json",
            "X-Title": "spelling-ocr-bench",
        },
        json=payload, timeout=REQUEST_TIMEOUT,
    )
    latency_ms = int((time.time() - t0) * 1000)
    r.raise_for_status()
    body = r.json()
    text = body["choices"][0]["message"]["content"]
    usage = body.get("usage", {}) or {}
    parsed = parse_json_lenient(text)
    return {
        "latency_ms": latency_ms,
        "raw": text,
        "predicted_word": parsed.get("predicted_word", ""),
        "legible": bool(parsed.get("legible", True)),
        "matches_target": bool(parsed.get("matches_target", False)),
        "comment": parsed.get("comment", ""),
        "prompt_tokens": usage.get("prompt_tokens", ""),
        "completion_tokens": usage.get("completion_tokens", ""),
    }


def parse_json_lenient(text: str) -> dict:
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text, re.S)
        if m:
            try:
                return json.loads(m.group(0))
            except Exception:
                pass
    return {}


# ─── 実行 ─────────────────────────────────────────────────────────────
def main():
    load_dotenv()
    if "OPENROUTER_API_KEY" not in os.environ:
        sys.exit("OPENROUTER_API_KEY を設定してください（.env か export で）")

    if os.environ.get("SUPABASE_URL") and os.environ.get("SUPABASE_SERVICE_KEY"):
        print("Supabase からサンプル取得中...")
        samples = load_samples_supabase()
    else:
        print("ローカル(./samples + labels.csv)からサンプル取得中...")
        samples = load_samples_local()
    print(f"{len(samples)} サンプル / {len(MODELS)} モデル = {len(samples) * len(MODELS)} 呼び出し")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = os.path.join(os.path.dirname(__file__), f"results-{stamp}.csv")
    rows = []
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "model", "sample_id", "target", "label_kind",
            "ground_truth", "legible_truth", "verdict_correct", "recognized_text",
            "predicted_word", "legible", "matches_target", "comment",
            "latency_ms", "prompt_tokens", "completion_tokens", "error",
        ])
        for s in samples:
            for model in MODELS:
                try:
                    res = call_model(model, s)
                    err = ""
                except Exception as e:  # 1件失敗しても続行
                    res = {"latency_ms": "", "predicted_word": "", "legible": "",
                           "matches_target": "", "comment": "", "prompt_tokens": "",
                           "completion_tokens": ""}
                    err = str(e)[:200]
                w.writerow([
                    model, s["id"], s["target"], s.get("label_kind", ""),
                    s.get("ground_truth", ""), s.get("legible_truth", ""),
                    s.get("verdict_correct", ""), s.get("recognized_text", ""),
                    res["predicted_word"], res["legible"], res["matches_target"], res["comment"],
                    res["latency_ms"], res["prompt_tokens"], res["completion_tokens"], err,
                ])
                rows.append({"model": model, "sample": s, "res": res, "err": err})
                print(f"  {model:32s} {s['id']:20s} {'OK' if not err else 'ERR:'+err}")

    summarize(rows)
    print(f"\n明細: {out_path}")


def summarize(rows):
    print("\n=== サマリ（§7 指標） ===")
    by_model = {}
    for r in rows:
        by_model.setdefault(r["model"], []).append(r)

    header = f"{'model':32s} {'n':>3} {'OCR精度':>7} {'誤受理':>6} {'誤拒否':>6} {'判読不能検出':>10} {'捏造':>5} {'遅延ms':>7}"
    print(header)
    def truth_correct_of(s):
        if s.get("label_kind") == "verdict":
            return bool(s["verdict_correct"])               # 親判定（correct/incorrect）
        return norm(s.get("ground_truth", "")) == norm(s["target"])  # 旧: 実際に書かれた文字==出題語

    for model, rs in by_model.items():
        ok = [r for r in rs if not r["err"]]
        n = len(ok)
        if n == 0:
            print(f"{model:32s} {'全件エラー'}")
            continue
        # OCR精度・判読不能は「正確な綴り/legible 真値」がある ground_truth 形式のみ算出。
        gt_rows = [r for r in ok if r["sample"].get("label_kind") == "ground_truth"]
        ocr_hit = sum(1 for r in gt_rows
                      if norm(r["res"]["predicted_word"]) == norm(r["sample"].get("ground_truth", "")))
        illeg = [r for r in gt_rows if not r["sample"].get("legible_truth", True)]
        illeg_detected = sum(1 for r in illeg if r["res"]["legible"] is False)
        fabricate = sum(1 for r in illeg if r["res"]["legible"] is True)  # 読めないのに読めた=捏造
        fa = fr = 0
        for r in ok:
            truth_correct = truth_correct_of(r["sample"])
            says_correct = r["res"]["matches_target"] is True
            if (not truth_correct) and says_correct:
                fa += 1
            if truth_correct and (not says_correct):
                fr += 1
        lat = [r["res"]["latency_ms"] for r in ok if isinstance(r["res"]["latency_ms"], int)]
        avg_lat = int(sum(lat) / len(lat)) if lat else 0
        ocr_str = f"{ocr_hit / len(gt_rows):.0%}" if gt_rows else "-"
        illeg_str = f"{illeg_detected}/{len(illeg)}" if illeg else "-"
        print(f"{model:32s} {n:>3} {ocr_str:>7} {fa:>6} {fr:>6} {illeg_str:>10} {fabricate:>5} {avg_lat:>7}")

    # 親判定ラベル形式のときは、ローカルOCR(recognized_text)のベースラインFA/FRも出す（AIが勝るか比較）。
    verdict_samples = {r["sample"]["id"]: r["sample"]
                       for r in rows if r["sample"].get("label_kind") == "verdict"}
    if verdict_samples:
        b_fa = b_fr = 0
        for s in verdict_samples.values():
            local_correct = norm(s.get("recognized_text", "")) == norm(s["target"])
            tc = bool(s["verdict_correct"])
            if (not tc) and local_correct:
                b_fa += 1
            if tc and (not local_correct):
                b_fr += 1
        print(f"\nローカルOCRベースライン（recognized_text vs 親判定 / n={len(verdict_samples)}）: "
              f"誤受理={b_fa} 誤拒否={b_fr} ← AIモデルのFA/FRがこれを下回れば導入価値あり")

    print("\n注意:")
    print("  - 誤受理(FA)が最重要。0 が理想。1つでも出るモデルは本番では危険。")
    print("  - 親判定ラベル形式（暫定A）では FA/FR を親の正誤で測る。OCR精度/判読不能は '-'（綴り真値が無いため）。")
    print("  - 捏造列が0でないモデルは『きれいに書こう』導線が誤発火しない前提を満たさない。")
    print("  - コメント品質は CSV の comment 列を目視評価（安いモデルで足りるかの判定）。")
    print("  - レイテンシは OpenRouter 経由の上限値。最終候補は各社直APIで再計測。")


if __name__ == "__main__":
    main()
