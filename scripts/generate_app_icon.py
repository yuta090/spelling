#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "iPadPrototype" / "Assets.xcassets" / "AppIcon.appiconset"

SIZES = {
    "Icon-20.png": 20,
    "Icon-20@2x.png": 40,
    "Icon-29.png": 29,
    "Icon-29@2x.png": 58,
    "Icon-40.png": 40,
    "Icon-40@2x.png": 80,
    "Icon-76.png": 76,
    "Icon-76@2x.png": 152,
    "Icon-83.5@2x.png": 167,
    "Icon-1024.png": 1024,
}


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rounded_rectangle(draw: ImageDraw.ImageDraw, rect, radius, fill):
    draw.rounded_rectangle(rect, radius=radius, fill=fill)


def draw_icon(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGB", (size, size), (245, 251, 255))
    draw = ImageDraw.Draw(image)

    # Background keeps enough contrast against the pencil and the large ABC text.
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(245 - 25 * t)
        g = int(251 - 21 * t)
        b = int(255 - 7 * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b))

    rounded_rectangle(
        draw,
        (int(80 * scale), int(90 * scale), int(944 * scale), int(934 * scale)),
        int(180 * scale),
        (255, 255, 255),
    )
    rounded_rectangle(
        draw,
        (int(124 * scale), int(134 * scale), int(900 * scale), int(890 * scale)),
        int(150 * scale),
        (224, 242, 255),
    )

    # Soft notebook lines.
    for offset, color in [
        (330, (187, 219, 253)),
        (500, (255, 157, 164)),
        (670, (187, 219, 253)),
    ]:
        y = int(offset * scale)
        draw.line([(int(188 * scale), y), (int(838 * scale), y)], fill=color, width=max(2, int(8 * scale)))

    text = "ABC"
    text_font = font(max(12, int(236 * scale)))
    bbox = draw.textbbox((0, 0), text, font=text_font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = int((size - text_w) / 2)
    y = int(318 * scale - text_h / 2)
    draw.text((x + int(8 * scale), y + int(10 * scale)), text, font=text_font, fill=(126, 155, 188))
    draw.text((x, y), text, font=text_font, fill=(18, 72, 157))

    # Pencil with stronger contrast than the previous pale icon.
    pencil = [
        (int(310 * scale), int(710 * scale)),
        (int(684 * scale), int(336 * scale)),
        (int(778 * scale), int(430 * scale)),
        (int(404 * scale), int(804 * scale)),
    ]
    draw.polygon(pencil, fill=(252, 180, 43))
    draw.line(
        [pencil[0], pencil[1], pencil[2], pencil[3], pencil[0]],
        fill=(142, 91, 12),
        width=max(2, int(12 * scale)),
    )
    ferrule = [
        (int(684 * scale), int(336 * scale)),
        (int(728 * scale), int(292 * scale)),
        (int(822 * scale), int(386 * scale)),
        (int(778 * scale), int(430 * scale)),
    ]
    draw.polygon(ferrule, fill=(42, 111, 210))
    tip = [
        (int(278 * scale), int(836 * scale)),
        (int(310 * scale), int(710 * scale)),
        (int(404 * scale), int(804 * scale)),
    ]
    draw.polygon(tip, fill=(102, 70, 38))
    draw.polygon(
        [
            (int(278 * scale), int(836 * scale)),
            (int(292 * scale), int(782 * scale)),
            (int(332 * scale), int(822 * scale)),
        ],
        fill=(30, 31, 36),
    )

    if size < 80:
        return image.resize((size, size), Image.Resampling.LANCZOS)
    return image


def main():
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    for name, size in SIZES.items():
        draw_icon(size).save(ICON_DIR / name)
    print(f"generated {len(SIZES)} app icon files in {ICON_DIR}")


if __name__ == "__main__":
    main()
