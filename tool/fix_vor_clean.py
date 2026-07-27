"""Rebuild clean vor.png from vor_sheet: no numbers, transparent BG, 4x6 grid."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "vors" / "vor_sheet.png"
OUT = ROOT / "assets" / "images" / "vors" / "vor.png"
COLS, ROWS = 4, 6


def flood_key_black(im: Image.Image, limit: int = 32) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    pix = im.load()
    visited = [[False] * w for _ in range(h)]
    stack: list[tuple[int, int]] = []

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = pix[x, y]
        if a < 10:
            return True
        return r <= limit and g <= limit and b <= limit

    for x in range(w):
        stack += [(x, 0), (x, h - 1)]
    for y in range(h):
        stack += [(0, y), (w - 1, y)]

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or visited[y][x]:
            continue
        visited[y][x] = True
        if not is_bg(x, y):
            continue
        pix[x, y] = (0, 0, 0, 0)
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return im


def clear_numbers(cell: Image.Image) -> Image.Image:
    """Remove white frame index digits above the sprite."""
    cell = cell.convert("RGBA")
    w, h = cell.size
    pix = cell.load()
    # Numbers sit in the upper ~22% of each cell.
    band = max(18, int(h * 0.22))
    for y in range(band):
        for x in range(w):
            r, g, b, a = pix[x, y]
            bright = (r + g + b) / 3
            # White / light-gray digit ink + soft AA.
            if bright >= 140 and abs(r - g) < 25 and abs(g - b) < 25:
                pix[x, y] = (0, 0, 0, 0)
    return cell


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"missing {SRC}")

    raw = Image.open(SRC).convert("RGBA")
    # Always start from the 4×6 master (ignore broken expanded sheets).
    if raw.size != (1448, 1086):
        raise SystemExit(f"unexpected master size {raw.size}, want 1448x1086")

    raw = flood_key_black(raw)
    w, h = raw.size
    cw, ch = w // COLS, h // ROWS

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for row in range(ROWS):
        for col in range(COLS):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            cell = clear_numbers(raw.crop(box))
            # Second pass: kill leftover black inside cell edges.
            cell = flood_key_black(cell, limit=28)
            out.paste(cell, (col * cw, row * ch), cell)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    # Keep master cleaned too (no numbers).
    out.save(SRC)
    print("OK", OUT, out.size, f"grid {COLS}x{ROWS}")


if __name__ == "__main__":
    main()
