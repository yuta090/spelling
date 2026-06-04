from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "generated"


FONT_CANDIDATES = {
    "arial": [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ],
    "comic": [
        "/System/Library/Fonts/Supplemental/Comic Sans MS.ttf",
        "/System/Library/Fonts/Supplemental/ChalkboardSE.ttc",
    ],
    "bradley": [
        "/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf",
        "/System/Library/Fonts/Noteworthy.ttc",
    ],
    "marker": [
        "/System/Library/Fonts/MarkerFelt.ttc",
        "/System/Library/Fonts/Supplemental/Chalkboard.ttc",
    ],
}


@dataclass(frozen=True)
class Sample:
    name: str
    word: str
    expected: str
    font_key: str
    font_size: int = 150
    guide: bool = True
    opacity: int = 245
    blur: float = 0.0
    x_shift: int = 0
    y_shift: int = 0
    rotate: float = 0.0
    thin: bool = False


def font_path(font_key: str) -> str:
    for candidate in FONT_CANDIDATES[font_key]:
        if Path(candidate).exists():
            return candidate
    return FONT_CANDIDATES["arial"][0]


def draw_dashed_line(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], fill: tuple[int, int, int], width: int) -> None:
    x1, y1, x2, y2 = xy
    dash = 18
    gap = 14
    x = x1
    while x < x2:
        draw.line((x, y1, min(x + dash, x2), y2), fill=fill, width=width)
        x += dash + gap


def render_sample(sample: Sample) -> Path:
    width, height = 1200, 380
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)

    left = 70
    right = width - 70
    top_line = 82
    mid_line = 145
    baseline = 235
    descender = 305

    if sample.guide:
        draw.line((left, top_line, right, top_line), fill=(210, 221, 230), width=2)
        draw_dashed_line(draw, (left, mid_line, right, mid_line), fill=(185, 198, 208), width=2)
        draw.line((left, baseline, right, baseline), fill=(125, 144, 158), width=4)
        draw.line((left, descender, right, descender), fill=(210, 221, 230), width=2)

    font = ImageFont.truetype(font_path(sample.font_key), sample.font_size)
    bbox = draw.textbbox((0, 0), sample.word, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = max(left + 20, (width - text_w) // 2 + sample.x_shift)
    y = baseline - text_h - 6 + sample.y_shift
    fill = (18, 26, 34, sample.opacity)

    text_layer = Image.new("RGBA", (width, height), (255, 255, 255, 0))
    text_draw = ImageDraw.Draw(text_layer)
    text_draw.text((x, y), sample.word, font=font, fill=fill)

    if sample.thin:
        alpha = text_layer.getchannel("A").filter(ImageFilter.MinFilter(3))
        text_layer.putalpha(alpha)

    if sample.rotate:
        text_layer = text_layer.rotate(sample.rotate, resample=Image.Resampling.BICUBIC, center=(width // 2, height // 2))

    image = Image.alpha_composite(image.convert("RGBA"), text_layer).convert("RGB")

    if sample.blur:
        image = image.filter(ImageFilter.GaussianBlur(sample.blur))

    path = OUT / f"{sample.name}.png"
    image.save(path)
    return path


def samples() -> Iterable[Sample]:
    yield Sample("cat_arial_guide", "cat", "cat", "arial", guide=True)
    yield Sample("cat_arial_no_guide", "cat", "cat", "arial", guide=False)
    yield Sample("cat_comic_guide", "cat", "cat", "comic", guide=True)
    yield Sample("cat_bradley_guide", "cat", "cat", "bradley", guide=True)
    yield Sample("cat_marker_guide", "cat", "cat", "marker", guide=True)
    yield Sample("cot_expected_cat", "cot", "cat", "bradley", guide=True)
    yield Sample("cut_expected_cat", "cut", "cat", "comic", guide=True)
    yield Sample("dog_guide", "dog", "dog", "bradley", guide=True)
    yield Sample("school_guide", "school", "school", "comic", guide=True, font_size=130)
    yield Sample("friend_guide", "friend", "friend", "marker", guide=True, font_size=125)
    yield Sample("cat_small", "cat", "cat", "bradley", guide=True, font_size=88)
    yield Sample("cat_light", "cat", "cat", "bradley", guide=True, opacity=120)
    yield Sample("cat_blur", "cat", "cat", "bradley", guide=True, blur=1.4)
    yield Sample("cat_shifted_low", "cat", "cat", "bradley", guide=True, y_shift=75)
    yield Sample("cat_rotated", "cat", "cat", "bradley", guide=True, rotate=-4.5)
    yield Sample("cta_expected_cat", "cta", "cat", "bradley", guide=True)
    yield Sample("kat_expected_cat", "kat", "cat", "comic", guide=True)
    yield Sample("ca_expected_cat", "ca", "cat", "bradley", guide=True)
    yield Sample("frend_expected_friend", "frend", "friend", "marker", guide=True, font_size=125)
    yield Sample("freind_expected_friend", "freind", "friend", "comic", guide=True, font_size=125)
    yield Sample("skool_expected_school", "skool", "school", "bradley", guide=True, font_size=130)
    yield Sample("zyla_nonce_word", "zyla", "zyla", "bradley", guide=True, font_size=135)
    yield Sample("rn_expected_m", "rn", "m", "arial", guide=True, font_size=150)
    yield Sample("m_expected_rn", "m", "rn", "arial", guide=True, font_size=150)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for sample in samples():
        path = render_sample(sample)
        manifest.append(f"{path.name}\t{sample.expected}")
    (OUT / "manifest.tsv").write_text("\n".join(manifest) + "\n")
    print(f"Generated {len(manifest)} samples in {OUT}")


if __name__ == "__main__":
    main()
