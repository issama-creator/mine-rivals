"""Cut the middle diamond from assets/1.png; remove white/checkerboard bg."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "1.png"
DEST = ROOT / "assets" / "images" / "items" / "diamond.png"


def is_bg(r: int, g: int, b: int) -> bool:
    diff = max(abs(r - g), abs(g - b), abs(r - b))
    # Near-white / light gray checker cells
    if diff <= 12 and r >= 210 and g >= 210 and b >= 210:
        return True
    if diff <= 10 and 150 <= r <= 210 and 150 <= g <= 210 and 150 <= b <= 210:
        return True
    return False


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    pix = im.load()

    # Content bbox
    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, _ = pix[x, y]
            if not is_bg(r, g, b):
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)

    # Three crystals side-by-side — take middle third of content.
    cw = maxx - minx + 1
    third = cw // 3
    # Slight overlap trim so neighbors don't bleed in
    x0 = minx + third + int(third * 0.06)
    x1 = minx + 2 * third - int(third * 0.06)
    y0, y1 = miny, maxy
    print("content", minx, miny, maxx, maxy, "mid crop", x0, y0, x1, y1)

    crop = im.crop((x0, y0, x1 + 1, y1 + 1))
    cw, ch = crop.size
    cp = crop.load()
    for y in range(ch):
        for x in range(cw):
            r, g, b, _ = cp[x, y]
            if is_bg(r, g, b):
                cp[x, y] = (0, 0, 0, 0)
            else:
                cp[x, y] = (r, g, b, 255)

    # Keep largest blob only (drop edge scraps from neighbors)
    visited = [[False] * cw for _ in range(ch)]
    dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    best_area = 0
    best_pixels: list[tuple[int, int]] = []
    for y in range(ch):
        for x in range(cw):
            if cp[x, y][3] == 0 or visited[y][x]:
                continue
            stack = [(y, x)]
            visited[y][x] = True
            pixels = [(y, x)]
            while stack:
                cy, cx = stack.pop()
                for dy, dx in dirs:
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < ch and 0 <= nx < cw and not visited[ny][nx] and cp[nx, ny][3]:
                        visited[ny][nx] = True
                        stack.append((ny, nx))
                        pixels.append((ny, nx))
            if len(pixels) > best_area:
                best_area = len(pixels)
                best_pixels = pixels

    keep = set(best_pixels)
    for y in range(ch):
        for x in range(cw):
            if (y, x) not in keep:
                cp[x, y] = (0, 0, 0, 0)

    bbox = crop.getbbox()
    if bbox:
        crop = crop.crop(bbox)

    # Soft edge cleanup: kill near-white leftovers on border
    cw, ch = crop.size
    cp = crop.load()
    for y in range(ch):
        for x in range(cw):
            r, g, b, a = cp[x, y]
            if a and is_bg(r, g, b):
                cp[x, y] = (0, 0, 0, 0)

    bbox = crop.getbbox()
    if bbox:
        crop = crop.crop(bbox)

    DEST.parent.mkdir(parents=True, exist_ok=True)
    crop.save(DEST)
    print("saved", DEST, crop.size, "pixels", best_area)


if __name__ == "__main__":
    main()
