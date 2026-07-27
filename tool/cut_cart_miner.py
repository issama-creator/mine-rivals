"""Remove near-white background from cart miner sprite sheet."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "skins" / "pers_asset.png"
DEST = ROOT / "assets" / "images" / "skins" / "cart_miner.png"
PREVIEW = ROOT / "assets" / "images" / "skins" / "preview" / "cart_miner.png"


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    pix = im.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            # Near-white / light gray sheet background
            if r >= 245 and g >= 245 and b >= 245:
                pix[x, y] = (0, 0, 0, 0)
            elif r >= 230 and g >= 230 and b >= 230 and abs(r - g) < 8 and abs(g - b) < 8:
                pix[x, y] = (0, 0, 0, 0)

    DEST.parent.mkdir(parents=True, exist_ok=True)
    im.save(DEST)
    # Preview = first frame (5 cols x 4 rows)
    fw, fh = w // 5, h // 4
    frame = im.crop((0, 0, fw, fh))
    # Trim empty
    bbox = frame.getbbox()
    if bbox:
        frame = frame.crop(bbox)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    frame.save(PREVIEW)
    print("saved", DEST, im.size, "preview", PREVIEW, frame.size)


if __name__ == "__main__":
    main()
