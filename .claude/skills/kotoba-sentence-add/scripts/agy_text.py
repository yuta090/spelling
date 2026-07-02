#!/usr/bin/env python3
"""agy でテキスト(JSON候補文)を「安定して」生成する pty ラッパ。

なぜ必要か（大量生成の安定化）:
- agy は非TTYだと stdout が消える既知バグがある（`> file` や `| pipe` で 0 バイトになる）。
  → 各プロセスに os.openpty() で pty を割り当てて読む（画像側 gen_agy.py と同じ作法）。
- 生 print モード（フラグ無し）は実タスクで許可待ちハングや 5 分タイムアウトが頻発する。
  → **--sandbox（端末/ツール制限）で動かす**。ツールを使わない純テキスト生成なので
    --dangerously-skip-permissions は不要で、Claude Code の auto-mode 安全分類器にも
    ブロックされない（＝Claude が自動で回せる）。
- 出力は最後に一括フラッシュされる。pty で最後まで読み切ってから返す。

実測: Gemini 3.1 Pro (High) で 20 語/バッチ ≈ 66 秒・安定。10k 一括はダメ（小バッチで）。

使い方:
  python3 agy_text.py <prompt_file> ["Model Name"] [timeout_s] > out.json
既定モデル = "Gemini 3.1 Pro (High)"（品質・速度のバランス良）。
"""
import os
import pty
import select
import signal
import subprocess
import sys
import time

AGY = os.path.expanduser("~/.local/bin/agy")


def run(prompt, model, timeout_s):
    args = [AGY, "--sandbox", "--print-timeout", f"{timeout_s}s", "--model", model, "-p", prompt]
    master, slave = pty.openpty()
    buf = bytearray()
    p = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                         start_new_session=True, close_fds=True)
    os.close(slave)
    deadline = time.time() + timeout_s + 30
    try:
        while True:
            if time.time() > deadline:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except OSError:
                    pass
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
    return bytes(buf).decode("utf-8", "replace")


if __name__ == "__main__":
    pf = sys.argv[1]
    model = sys.argv[2] if len(sys.argv) > 2 else "Gemini 3.1 Pro (High)"
    timeout_s = int(sys.argv[3]) if len(sys.argv) > 3 else 240
    prompt = open(pf, encoding="utf-8").read()
    t0 = time.time()
    out = run(prompt, model, timeout_s)
    sys.stderr.write(f"[agy_text] {time.time()-t0:.1f}s, {len(out)} bytes\n")
    sys.stdout.write(out)
