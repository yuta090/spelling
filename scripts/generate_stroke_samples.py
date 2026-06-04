from __future__ import annotations

import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "generated"
SCALE = 4


@dataclass(frozen=True)
class StrokeSample:
    name: str
    word: str
    expected: str
    guide: bool = True
    jitter: int = 0
    rotate: float = 0
    blur: float = 0
    scale: float = 1.0
    y_shift: int = 0


def jittered(value: float, amount: int) -> float:
    return value + (random.random() - 0.5) * amount * 2


def scaled_box(box: tuple[float, float, float, float]) -> tuple[int, int, int, int]:
    return tuple(int(v * SCALE) for v in box)


def draw_line(draw: ImageDraw.ImageDraw, points: list[tuple[float, float]], width: int, jitter: int) -> None:
    actual = [(jittered(x, jitter) * SCALE, jittered(y, jitter) * SCALE) for x, y in points]
    draw.line(actual, fill=(18, 26, 34), width=width * SCALE, joint="curve")


def draw_arc(
    draw: ImageDraw.ImageDraw,
    box: tuple[float, float, float, float],
    start: int,
    end: int,
    width: int,
) -> None:
    draw.arc(scaled_box(box), start=start, end=end, fill=(18, 26, 34), width=width * SCALE)


def draw_ellipse(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], width: int) -> None:
    draw.ellipse(scaled_box(box), outline=(18, 26, 34), width=width * SCALE)


def letter_c(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_arc(draw, (x, base - 95, x + 86, base + 8), 55, 305, width)
    return x + 92


def letter_o(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_ellipse(draw, (x, base - 92, x + 88, base + 5), width)
    return x + 98


def letter_a(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_ellipse(draw, (x, base - 88, x + 78, base + 5), width)
    draw_line(draw, [(x + 78, base - 82), (x + 78, base + 2)], width, jitter)
    return x + 92


def letter_t(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_line(draw, [(x + 46, base - 150), (x + 46, base + 2)], width, jitter)
    draw_line(draw, [(x + 12, base - 94), (x + 86, base - 94)], max(width - 4, 10), jitter)
    return x + 96


def letter_d(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_ellipse(draw, (x, base - 88, x + 82, base + 5), width)
    draw_line(draw, [(x + 82, base - 155), (x + 82, base + 2)], width, jitter)
    return x + 96


def letter_g(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_ellipse(draw, (x, base - 88, x + 82, base + 5), width)
    draw_line(draw, [(x + 78, base - 25), (x + 72, base + 78), (x + 28, base + 66)], width, jitter)
    return x + 98


def letter_m(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_line(
        draw,
        [
            (x + 5, base + 2),
            (x + 5, base - 85),
            (x + 44, base - 45),
            (x + 78, base - 85),
            (x + 114, base + 2),
        ],
        width,
        jitter,
    )
    return x + 130


def letter_r(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_line(draw, [(x + 8, base + 2), (x + 8, base - 86), (x + 52, base - 78)], width, jitter)
    return x + 66


def letter_n(draw: ImageDraw.ImageDraw, x: float, base: float, width: int, jitter: int) -> float:
    draw_line(draw, [(x + 5, base + 2), (x + 5, base - 84), (x + 68, base + 2), (x + 68, base - 84)], width, jitter)
    return x + 84


LETTERS: dict[str, Callable[[ImageDraw.ImageDraw, float, float, int, int], float]] = {
    "a": letter_a,
    "c": letter_c,
    "d": letter_d,
    "g": letter_g,
    "m": letter_m,
    "n": letter_n,
    "o": letter_o,
    "r": letter_r,
    "t": letter_t,
}


def draw_guides(draw: ImageDraw.ImageDraw, width: int, height: int) -> None:
    left = 70 * SCALE
    right = (width - 70) * SCALE
    for y, color, line_width in [
        (82, (210, 221, 230), 2),
        (235, (125, 144, 158), 4),
        (305, (210, 221, 230), 2),
    ]:
        draw.line((left, y * SCALE, right, y * SCALE), fill=color, width=line_width * SCALE)

    x = left
    while x < right:
        draw.line((x, 145 * SCALE, min(x + 18 * SCALE, right), 145 * SCALE), fill=(185, 198, 208), width=2 * SCALE)
        x += 32 * SCALE


def render(sample: StrokeSample) -> Path:
    random.seed(sample.name)
    width, height = 1200, 380
    image = Image.new("RGB", (width * SCALE, height * SCALE), "white")
    draw = ImageDraw.Draw(image)

    if sample.guide:
        draw_guides(draw, width, height)

    base = 235 + sample.y_shift
    letter_width = {
        "cat": 280,
        "cot": 290,
        "dog": 300,
        "rn": 150,
        "m": 130,
    }.get(sample.word, len(sample.word) * 95)
    x = (width - letter_width * sample.scale) / 2

    stroke_width = int(20 * sample.scale)
    for character in sample.word:
        draw_fn = LETTERS[character]
        before = x
        x = draw_fn(draw, x, base, stroke_width, sample.jitter)
        x = before + (x - before) * sample.scale

    image = image.resize((width, height), Image.Resampling.LANCZOS)

    if sample.rotate:
        image = image.rotate(sample.rotate, resample=Image.Resampling.BICUBIC, center=(width // 2, height // 2), fillcolor="white")
    if sample.blur:
        image = image.filter(ImageFilter.GaussianBlur(sample.blur))

    path = OUT / f"{sample.name}.png"
    image.save(path)
    return path


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    samples = [
        StrokeSample("stroke_cat_clean", "cat", "cat"),
        StrokeSample("stroke_cat_no_guide", "cat", "cat", guide=False),
        StrokeSample("stroke_cat_messy", "cat", "cat", jitter=9, rotate=-3.5, blur=0.5),
        StrokeSample("stroke_cat_small", "cat", "cat", scale=0.62),
        StrokeSample("stroke_cot_expected_cat", "cot", "cat", jitter=4),
        StrokeSample("stroke_dog_clean", "dog", "dog", jitter=4),
        StrokeSample("stroke_rn_expected_m", "rn", "m", jitter=2),
        StrokeSample("stroke_m_expected_rn", "m", "rn", jitter=2),
    ]

    manifest = []
    for sample in samples:
        path = render(sample)
        manifest.append(f"{path.name}\t{sample.expected}")

    (OUT / "stroke_manifest.tsv").write_text("\n".join(manifest) + "\n")
    print(f"Generated {len(samples)} stroke samples in {OUT}")


if __name__ == "__main__":
    main()
