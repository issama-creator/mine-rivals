"""Carefully strip only frame-index digits from vor/p5 sheets. Keeps art intact."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
COLS, ROWS = 6, 4


def crop_to_grid(im: Image.Image) -> tuple[Image.Image, int, int]:
    im = im.convert("RGBA")
    w, h = im.size
    tw, th = (w // COLS) * COLS, (h // ROWS) * ROWS
    if (tw, th) != (w, h):
        im = im.crop((0, 0, tw, th))
    return im, tw // COLS, th // ROWS


def clear_digits(cell: Image.Image) -> Image.Image:
    """Erase soft grey frame indices above the sprite; never touch opaque art."""
    cell = cell.convert("RGBA")
    w, h = cell.size
    pix = cell.load()
    # Numbers live in a thin band above the cart/hat.
    y_limit = max(28, int(h * 0.22))
    for y in range(y_limit):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a < 8 or a >= 170:
                # Opaque pixels are sprite (hat/cart), not digit ink.
                continue
            chroma = max(r, g, b) - min(r, g, b)
            if chroma <= 35:
                pix[x, y] = (0, 0, 0, 0)
    return cell


def edge_key_black(im: Image.Image) -> Image.Image:
    """Transparentize solid black only from sheet edges (bg leftovers)."""
    im = im.convert("RGBA")
    w, h = im.size
    pix = im.load()
    visited = [[False] * w for _ in range(h)]
    stack: list[tuple[int, int]] = []

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = pix[x, y]
        if a < 10:
            return True
        return a > 200 and r <= 6 and g <= 6 and b <= 6

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


def process(src: Path, dests: list[Path], preview: Path | None = None) -> None:
    raw = Image.open(src)
    im, cw, ch = crop_to_grid(raw)
    im = edge_key_black(im)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for row in range(ROWS):
        for col in range(COLS):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            cell = clear_digits(im.crop(box))
            out.paste(cell, (col * cw, row * ch), cell)
    for dest in dests:
        dest.parent.mkdir(parents=True, exist_ok=True)
        out.save(dest)
        print("OK", dest.name, out.size, f"cell {cw}x{ch}")
    if preview is not None:
        frame = out.crop((0, 0, cw, ch))
        bb = frame.getbbox()
        if bb:
            frame = frame.crop(bb)
        preview.parent.mkdir(parents=True, exist_ok=True)
        frame.save(preview)
        print("preview", preview.name)


def main() -> None:
    vors = ROOT / "assets" / "images" / "vors"
    skins = ROOT / "assets" / "images" / "skins"

    vor_src = vors / "vor.png"
    # Prefer a fresh no-bg drop-in if present.
    for alt in ("vor not bgc.png", "vor_not_bgc.png"):
        p = vors / alt
        if p.exists():
            vor_src = p
            break

    process(
        vor_src,
        [vors / "vor.png", vors / "vor_sheet.png"],
    )

    p5 = skins / "p5.png"
    if p5.exists():
        process(p5, [p5], skins / "preview" / "p5.png")


if __name__ == "__main__":
    main()
