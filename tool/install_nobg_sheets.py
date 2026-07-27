"""Install no-bg sheets → p5/p1/p2/vor as clean 6×4 grids."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SKINS = ROOT / "assets" / "images" / "skins"
PREVIEW = SKINS / "preview"
VORS = ROOT / "assets" / "images" / "vors"

COLS, ROWS = 6, 4
TARGET_W, TARGET_H = 1278, 960  # 213×240 cells


def clear_numbers(cell: Image.Image) -> Image.Image:
    cell = cell.convert("RGBA")
    w, h = cell.size
    pix = cell.load()
    wipe = max(18, int(h * 0.10))
    for y in range(wipe):
        for x in range(w):
            r, g, b, a = pix[x, y]
            # Kill faint grey frame digits; keep opaque cart pixels.
            if a < 40:
                pix[x, y] = (0, 0, 0, 0)
            elif a < 200 and abs(r - g) < 25 and abs(g - b) < 25 and r > 80:
                pix[x, y] = (0, 0, 0, 0)
            elif y < wipe // 2 and a < 220 and (r + g + b) / 3 > 90:
                # Top strip: digits only, cart starts lower.
                if abs(r - g) < 35 and abs(g - b) < 35:
                    pix[x, y] = (0, 0, 0, 0)
    return cell


def ensure_edge_transparent(im: Image.Image) -> Image.Image:
    """Keep artist alpha; just clear leftover solid black near edges."""
    im = im.convert("RGBA")
    w, h = im.size
    pix = im.load()
    visited = [[False] * w for _ in range(h)]
    stack: list[tuple[int, int]] = []

    def is_key(x: int, y: int) -> bool:
        r, g, b, a = pix[x, y]
        if a < 12:
            return True
        return a > 200 and r <= 8 and g <= 8 and b <= 8

    for x in range(w):
        stack += [(x, 0), (x, h - 1)]
    for y in range(h):
        stack += [(0, y), (w - 1, y)]

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or visited[y][x]:
            continue
        visited[y][x] = True
        if not is_key(x, y):
            continue
        pix[x, y] = (0, 0, 0, 0)
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return im


def process(src: Path, dest: Path, preview: Path | None = None) -> None:
    im = Image.open(src).convert("RGBA")
    # Exact 6×4 crop from top-left (2px trim on right of 1280).
    im = im.crop((0, 0, TARGET_W, TARGET_H))
    im = ensure_edge_transparent(im)
    cw, ch = TARGET_W // COLS, TARGET_H // ROWS
    out = Image.new("RGBA", (TARGET_W, TARGET_H), (0, 0, 0, 0))
    for row in range(ROWS):
        for col in range(COLS):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            cell = clear_numbers(im.crop(box))
            out.paste(cell, (col * cw, row * ch), cell)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    if preview is not None:
        frame = out.crop((0, 0, cw, ch))
        bb = frame.getbbox()
        if bb:
            frame = frame.crop(bb)
        preview.parent.mkdir(parents=True, exist_ok=True)
        frame.save(preview)
    print("OK", dest.relative_to(ROOT), out.size, f"cell {cw}x{ch}")


def main() -> None:
    mapping = [
        (SKINS / "p5nbgc.png", SKINS / "p5.png", PREVIEW / "p5.png"),
        (SKINS / "pers_no_bgc.png", SKINS / "p1.png", PREVIEW / "p1.png"),
        (SKINS / "pers2nobgc.png", SKINS / "p2.png", PREVIEW / "p2.png"),
    ]
    for src, dest, prev in mapping:
        if not src.exists():
            # Fallbacks for alternate names.
            alts = {
                "p5.png": [SKINS / "p5nbgc.png", SKINS / "pers1_no_bgc.png"],
                "p1.png": [SKINS / "pers_no_bgc.png", SKINS / "pers1_no_bgc.png"],
                "p2.png": [SKINS / "pers2nobgc.png"],
            }
            for alt in alts.get(dest.name, []):
                if alt.exists():
                    src = alt
                    break
        if not src.exists():
            raise SystemExit(f"missing source for {dest.name}")
        process(src, dest, prev)

    vor_src = VORS / "vor not bgc.png"
    if not vor_src.exists():
        vor_src = VORS / "vor_not_bgc.png"
    if not vor_src.exists():
        raise SystemExit("missing vor no-bg sheet")
    process(vor_src, VORS / "vor.png")
    process(vor_src, VORS / "vor_sheet.png")

    # Remove raw drop-ins so Flutter only sees canonical names.
    leftovers = [
        SKINS / "p5nbgc.png",
        SKINS / "pers_no_bgc.png",
        SKINS / "pers1_no_bgc.png",
        SKINS / "pers2nobgc.png",
        VORS / "vor not bgc.png",
    ]
    for p in leftovers:
        if p.exists():
            p.unlink()
            print("rm", p.name)


if __name__ == "__main__":
    main()
