#!/usr/bin/env python3
"""agy で背景画像を「1コール=1枚」で並列生成する(pty 個別割り当て版)。

agy は非TTYだと stdout が消える既知バグがあるため pseudo-TTY が要る。だが
`script -q /dev/null ... &` のようにシェルで背景化すると pty を確保できず
`tcgetattr: Operation not supported on socket` で落ちる。そこで各プロセスに
os.openpty() で個別 pty を割り当て、スレッドで並列実行する(既定 5 並列)。

各 id の生成プロンプトは candidates.csv の art_prompt を使う(末尾に保存指示を付与)。
出力は agy の scratch(~/.gemini/antigravity-cli/scratch) に出るので、生成後に
そこから bg_<id>.png を回収して --out へコピーする。

使い方:
  python3 scripts/gen_agy.py --ids voxelforest voxeldesert ... --out <dir> [-P 5]
  python3 scripts/gen_agy.py --ids-prefix voxel --out <dir>          # voxel* を全部
"""
import argparse
import csv
import os
import pty
import select
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


def _drain(master, buf):
    """master fd に残っている出力を最後まで読み切る。"""
    try:
        while True:
            r, _, _ = select.select([master], [], [], 0.2)
            if not r:
                break
            chunk = os.read(master, 65536)
            if not chunk:
                break
            buf += chunk
    except OSError:
        pass


def _killpg(p):
    """start_new_session=True で起動した子のプロセスグループごと kill する。"""
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            p.kill()
        except OSError:
            pass

HERE = Path(__file__).resolve().parent
SKILL = HERE.parent
CANDIDATES = SKILL / "candidates.csv"
AGY = os.path.expanduser("~/.local/bin/agy")
SCRATCH = Path(os.path.expanduser("~/.gemini/antigravity-cli/scratch"))

# レート制限/quota 枯渇のシグネチャ。agy(=Gemini裏側)はこれらをログに吐く。
RATE_MARKERS = ("429", "RESOURCE_EXHAUSTED", "rate limit", "rate-limit", "ratelimit",
                "quota", "exhausted", "too many requests", "RATE_LIMIT", "overloaded",
                "UNAVAILABLE", "503")


def preflight(timeout_s=60):
    """生成バッチ前に agy の接続/認証を 1 回だけ安く確認する(usage 事前チェック)。
    `agy models` が返れば疎通OK。空/レート制限なら False。"""
    master, slave = pty.openpty()
    buf = bytearray()
    try:
        p = subprocess.Popen([AGY, "models"], stdin=slave, stdout=slave, stderr=slave,
                             start_new_session=True, close_fds=True)
        os.close(slave)
        deadline = time.time() + timeout_s
        while time.time() < deadline and p.poll() is None:
            r, _, _ = select.select([master], [], [], 1.0)
            if r:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
        if p.poll() is None:
            _killpg(p)
        else:
            _drain(master, buf)  # 速い成功で buf が空になる誤判定を防ぐ
        p.wait()
    finally:
        try:
            os.close(master)
        except OSError:
            pass
    txt = bytes(buf).decode("utf-8", "replace")
    low = txt.lower()
    if any(m.lower() in low for m in RATE_MARKERS):
        return False, "rate/quota signature in `agy models`"
    # モデル名が1つでも見えれば疎通OK
    if "gemini" in low or "claude" in low or "gpt" in low:
        return True, "ok"
    return False, "no model list returned (auth/connectivity?)"


def load_prompts(ids=None, prefix=None):
    out = {}
    with open(CANDIDATES, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            i = r["id"]
            if prefix and not i.startswith(prefix):
                continue
            if ids and i not in ids:
                continue
            out[i] = r["art_prompt"]
    return out


def run_one(bid, art_prompt, outdir, timeout_s, results):
    fn = f"bg_{bid}.png"
    prompt = (
        f"{art_prompt}\n\nUse your built-in image_gen tool to generate the above and "
        f"save it in the current directory as a PNG named '{fn}'. After saving, run "
        f"'file {fn}'. Keep the lower-center open and mid-bright; no text or logos."
    )
    args = [AGY, "--dangerously-skip-permissions", "--print-timeout", f"{timeout_s}s", "-p", prompt]
    master, slave = pty.openpty()
    log_path = outdir / f"{bid}.log"
    buf = bytearray()
    try:
        p = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                             cwd=str(outdir), start_new_session=True, close_fds=True)
        os.close(slave)
        deadline = time.time() + timeout_s + 60
        while True:
            if time.time() > deadline:
                _killpg(p)  # 子(image_gen等)ごと止めて scratch 汚染を防ぐ
                break
            r, _, _ = select.select([master], [], [], 1.0)
            if r:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
            if p.poll() is not None:
                # drain remaining
                try:
                    while True:
                        chunk = os.read(master, 65536)
                        if not chunk:
                            break
                        buf += chunk
                except OSError:
                    pass
                break
        p.wait()
    finally:
        try:
            os.close(master)
        except OSError:
            pass
    log_path.write_bytes(bytes(buf))
    results[bid] = p.returncode if 'p' in dir() else -1


def collect(bid, outdir, since):
    fn = f"bg_{bid}.png"
    if not SCRATCH.exists():
        return None
    # 正確名 bg_<id>.png を最優先。無ければ id を名前に含む png のみ拾う。
    # ★ id 非依存の「最新 png」フォールバックはしない(並列/再試行で別 id の画像を
    #    誤回収するため。codex レビュー指摘)。生成プロンプトで保存名を明示しているので
    #    通常は正確名でヒットする。外れたら MISS にして再試行へ回す。
    cands = [c for c in SCRATCH.rglob(fn) if c.stat().st_mtime >= since]
    if not cands:
        cands = [c for c in SCRATCH.rglob(f"*{bid}*.png") if c.stat().st_mtime >= since]
    if cands:
        dst = outdir / fn
        shutil.copy2(sorted(cands, key=lambda c: c.stat().st_mtime)[-1], dst)
        return dst
    return None


def log_has_rate_limit(bid, outdir):
    lp = outdir / f"{bid}.log"
    if not lp.exists():
        return False
    try:
        low = lp.read_text("utf-8", "replace").lower()
    except OSError:
        return False
    return any(m.lower() in low for m in RATE_MARKERS)


def run_batch(prompts, parallel, outdir, timeout_s):
    """指定 prompts を parallel 並列で生成し (ok, miss, rate) の id リストを返す。"""
    since = time.time()
    results = {}
    sem = threading.Semaphore(parallel)
    threads = []

    def worker(bid, ap_):
        with sem:
            print(f"  ▶ start {bid}")
            run_one(bid, ap_, outdir, timeout_s, results)
            print(f"  ■ done  {bid} (rc={results.get(bid)})")

    for bid, ap_ in prompts.items():
        t = threading.Thread(target=worker, args=(bid, ap_))
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

    print("=== collecting from scratch ===")
    ok, miss, rate = [], [], []
    for bid in prompts:
        got = collect(bid, outdir, since)
        if got:
            ok.append(bid)
            print(f"  OK   {bid} -> {got}")
        else:
            miss.append(bid)
            if log_has_rate_limit(bid, outdir):
                rate.append(bid)
                print(f"  RATE {bid} (rate/quota signature; log: {outdir / (bid + '.log')})")
            else:
                print(f"  MISS {bid} (log: {outdir / (bid + '.log')})")
    return ok, miss, rate


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="*", default=[])
    ap.add_argument("--ids-prefix", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("-P", "--parallel", type=int, default=5)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--no-preflight", action="store_true", help="事前の agy 疎通/usage チェックを省略")
    ap.add_argument("--retries", type=int, default=1, help="MISS/レート制限分を低並列で再試行する回数")
    ap.add_argument("--backoff", type=int, default=30, help="再試行前の待機秒(レート制限回復待ち)")
    args = ap.parse_args()

    prompts = load_prompts(ids=set(args.ids) or None, prefix=args.ids_prefix or None)
    if not prompts:
        raise SystemExit("対象 id が candidates.csv に無い")
    outdir = Path(args.out).expanduser().resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    if not os.path.exists(AGY):
        raise SystemExit(f"agy not found: {AGY}")

    if not args.no_preflight:
        print("=== preflight: agy 疎通/usage チェック ===")
        alive, why = preflight()
        print(f"  preflight: {'OK' if alive else 'NG'} ({why})")
        if not alive:
            print("  agy が応答しない/レート制限の可能性。--no-preflight で強行可。中止。")
            sys.exit(3)

    parallel = max(1, args.parallel)
    print(f"agy 並列生成: {len(prompts)} 件 / 並列 {parallel} / timeout {args.timeout}s")
    ok, miss, rate = run_batch(prompts, parallel, outdir, args.timeout)

    # MISS/レート制限分は並列を半分に落として自動再試行(usage 配慮のバックオフ)
    attempt = 0
    while miss and attempt < args.retries:
        attempt += 1
        parallel = max(1, parallel // 2)
        wait = args.backoff if rate else 5
        print(f"=== retry {attempt}/{args.retries}: {len(miss)}件 を 並列{parallel} で再試行"
              f" (rate={len(rate)} → {wait}s 待機) ===")
        time.sleep(wait)
        retry_prompts = {k: prompts[k] for k in miss}
        rok, miss, rate = run_batch(retry_prompts, parallel, outdir, args.timeout)
        ok.extend(rok)

    print(f"done. ok={len(ok)} miss={len(miss)} {('MISS=' + ','.join(miss)) if miss else ''}")
    sys.exit(0 if not miss else 2)


if __name__ == "__main__":
    main()
