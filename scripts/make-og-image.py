#!/usr/bin/env python3
"""Draw the link-preview image, site/assets/og-image.png.

LinkedIn and others show og:image with no caption, so it is deliberately not a face
(docs/decisions.md #24): just initials, name and domain. Needs Pillow and DejaVu Sans.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1200, 630
BG, FG, MUTED, ACCENT = "#161615", "#ececea", "#a3a39d", "#8fb0ff"
FONTS = Path("/usr/share/fonts/truetype/dejavu")
OUT = Path(__file__).resolve().parent.parent / "site" / "assets" / "og-image.png"


def main() -> None:
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    bold = str(FONTS / "DejaVuSans-Bold.ttf")
    regular = str(FONTS / "DejaVuSans.ttf")

    # Monogram in an accent ring on the left, name and domain on the right.
    cx, cy, r = 300, HEIGHT // 2, 170
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=ACCENT, width=10)
    draw.text((cx, cy), "HA", font=ImageFont.truetype(bold, 140), fill=ACCENT, anchor="mm")

    draw.text((540, cy - 20), "Henry Ashton", font=ImageFont.truetype(bold, 72), fill=FG, anchor="ls")
    draw.text((540, cy + 50), "henryashton.dev", font=ImageFont.truetype(regular, 40), fill=MUTED, anchor="ls")

    image.save(OUT, optimize=True)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
