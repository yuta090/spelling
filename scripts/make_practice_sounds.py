#!/usr/bin/env python3
"""れんしゅう用の効果音（WAV）を合成する。

外部素材を使わず、正弦波＋倍音＋エンベロープだけで「子ども向けの明るい音」を作る。
決定論（乱数なし）なので再実行しても同じバイト列になり、git 差分が安定する。

出力先: iPadPrototype/Resources/sounds/
  pop.wav      ボタンの「ポン」
  sparkle.wav  中間の回のキラキラ「シャラン」
  coin.wav     単語完了のコイン「チャリン」
  rare.wav     レア大当たりのジャックポット
  fanfare.wav  セッション完了のファンファーレ

使い方: python3 scripts/make_practice_sounds.py
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT_DIR = Path(__file__).resolve().parent.parent / "iPadPrototype" / "Resources" / "sounds"


def silence(duration):
    return [0.0] * int(RATE * duration)


def tone(freq, duration, *, volume=1.0, attack=0.004, decay=None, harmonics=(1.0, 0.35, 0.12), glide_to=None):
    """1音を合成する。harmonics は基音からの倍音の強さ。glide_to でピッチを滑らせる。"""
    n = int(RATE * duration)
    if decay is None:
        decay = duration
    samples = []
    for i in range(n):
        t = i / RATE
        f = freq if glide_to is None else freq + (glide_to - freq) * (t / duration)
        phase = 2 * math.pi * f * t
        v = sum(h * math.sin(phase * (k + 1)) for k, h in enumerate(harmonics))
        env = min(1.0, t / attack) * math.exp(-t / (decay * 0.35))
        samples.append(v * env * volume)
    return samples


def mix(base, overlay, at):
    """overlay を base の at 秒目に重ねる（必要なら base を伸ばす）。"""
    start = int(RATE * at)
    end = start + len(overlay)
    if end > len(base):
        base = base + [0.0] * (end - len(base))
    for i, s in enumerate(overlay):
        base[start + i] += s
    return base


def write_wav(name, samples, peak=0.7):
    """正規化して 16bit mono WAV に書き出す。端は 5ms フェードでクリック音を防ぐ。"""
    fade = int(RATE * 0.005)
    for i in range(min(fade, len(samples))):
        samples[i] *= i / fade
        samples[-1 - i] *= i / fade
    top = max(abs(s) for s in samples) or 1.0
    scale = peak / top
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * scale * 32767))))
            for s in samples
        )
        w.writeframes(frames)
    print(f"wrote {path.relative_to(OUT_DIR.parent.parent.parent)} ({len(samples) / RATE:.2f}s)")


# 音名 → 周波数（A4=440）
def note(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semitone = names[name[0]] + (1 if "#" in name else 0)
    octave = int(name[-1])
    return 440.0 * (2 ** ((semitone + (octave - 4) * 12) / 12))


def make_pop():
    # 短いピッチ下降＝「ポンッ」。
    return tone(700, 0.09, glide_to=340, decay=0.09, harmonics=(1.0, 0.2))


def make_sparkle():
    # 上昇アルペジオ＋わずかなデチューンのきらめき。
    out = silence(0.42)
    for i, n in enumerate(["C6", "E6", "G6", "C7"]):
        f = note(n)
        t = i * 0.07
        out = mix(out, tone(f, 0.22, volume=0.8, decay=0.18, harmonics=(1.0, 0.25)), t)
        out = mix(out, tone(f * 1.006, 0.22, volume=0.25, decay=0.18, harmonics=(1.0,)), t)
    return out


def make_coin():
    # 定番の2音「チャリン」（B5 → E6）。
    out = silence(0.24)
    out = mix(out, tone(note("B5"), 0.06, volume=0.9, decay=0.08), 0.0)
    out = mix(out, tone(note("E6"), 0.20, volume=1.0, decay=0.20), 0.055)
    return out


def make_rare():
    # 大当たり：駆け上がるアルペジオ→頂点でロングトーン＋きらめき。
    out = silence(0.95)
    run = ["C5", "E5", "G5", "C6", "E6", "G6"]
    for i, n in enumerate(run):
        out = mix(out, tone(note(n), 0.14, volume=0.7, decay=0.12), i * 0.055)
    top = 0.33
    out = mix(out, tone(note("C7"), 0.55, volume=1.0, decay=0.5), top)
    out = mix(out, tone(note("E7"), 0.45, volume=0.4, decay=0.4), top + 0.05)
    out = mix(out, tone(note("G7"), 0.35, volume=0.25, decay=0.35), top + 0.10)
    return out


def make_fanfare():
    # 完了ファンファーレ：G4 C5 E5 → Cメジャー和音。
    out = silence(1.1)
    for i, n in enumerate(["G4", "C5", "E5"]):
        out = mix(out, tone(note(n), 0.16, volume=0.8, decay=0.14), i * 0.12)
    chord_at = 0.38
    for n, v in [("C5", 0.9), ("E5", 0.7), ("G5", 0.6), ("C6", 0.5)]:
        out = mix(out, tone(note(n), 0.65, volume=v, decay=0.6), chord_at)
    return out


if __name__ == "__main__":
    write_wav("pop.wav", make_pop())
    write_wav("sparkle.wav", make_sparkle())
    write_wav("coin.wav", make_coin())
    write_wav("rare.wav", make_rare())
    write_wav("fanfare.wav", make_fanfare())
