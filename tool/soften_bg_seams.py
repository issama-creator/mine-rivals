"""Stronger vertical loop soft-seam for all corridor BGs."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BGC = ROOT / "assets" / "images" / "bgc"


def soft_loop(im: Image.Image, band: int = 140) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    band = min(band, h // 5)
    top = im.crop((0, 0, w, band))
    bot = im.crop((0, h - band, w, h))
    out = im.copy()
    for y in range(band):
        t = (y + 0.5) / band
        # Smoothstep — strongest blend right at the tile edge.
        ease = t * t * (3 - 2 * t)
        row_top = Image.blend(
            top.crop((0, y, w, y + 1)),
            bot.crop((0, y, w, y + 1)),
            1.0 - ease,
        )
        out.paste(row_top, (0, y))
        row_bot = Image.blend(
            bot.crop((0, y, w, y + 1)),
            top.crop((0, y, w, y + 1)),
            ease,
        )
        out.paste(row_bot, (0, h - band + y))
    return out


def main() -> None:
    for i in range(1, 9):
        p = BGC / f"{i}.png"
        if not p.exists():
            continue
        im = soft_loop(Image.open(p), band=150)
        im.save(p)
        print("seam", p.name)


if __name__ == "__main__":
    main()
