"""Fix p5/p1/vor sheets: true 6×4 grid, strip numbers, transparent BG."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
COLS, ROWS = 6, 4
TARGET_W, TARGET_H = 1446, 1084  # exact 241×271 cells


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


def to_grid(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    if im.size != (TARGET_W, TARGET_H):
        # Center-crop / pad to exact grid.
        canvas = Image.new("RGBA", (TARGET_W, TARGET_H), (0, 0, 0, 255))
        src = im
        # Scale minimally if far off, else center paste.
        if abs(src.size[0] - TARGET_W) > 8 or abs(src.size[1] - TARGET_H) > 8:
            src = src.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
            canvas = src
        else:
            ox = (TARGET_W - src.size[0]) // 2
            oy = (TARGET_H - src.size[1]) // 2
            canvas.paste(src, (ox, oy))
        im = canvas
    return im


def clear_numbers(cell: Image.Image) -> Image.Image:
    cell = cell.convert("RGBA")
    w, h = cell.size
    pix = cell.load()
    wipe = max(22, int(h * 0.14))
    for y in range(wipe):
        for x in range(w):
            pix[x, y] = (0, 0, 0, 0)
    # Extra: kill leftover white digit ink a bit lower.
    for y in range(wipe, int(h * 0.22)):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a > 0 and (r + g + b) / 3 > 150 and abs(r - g) < 30:
                pix[x, y] = (0, 0, 0, 0)
    return cell


def process_sheet(src: Path, dest: Path, preview: Path | None = None) -> None:
    raw = to_grid(Image.open(src))
    raw = flood_key_black(raw)
    w, h = raw.size
    cw, ch = w // COLS, h // ROWS
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for row in range(ROWS):
        for col in range(COLS):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            cell = clear_numbers(raw.crop(box))
            cell = flood_key_black(cell, limit=28)
            out.paste(cell, (col * cw, row * ch), cell)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    if preview is not None:
        frame = out.crop((0, 0, cw, ch))
        bbox = frame.getbbox()
        if bbox:
            frame = frame.crop(bbox)
        preview.parent.mkdir(parents=True, exist_ok=True)
        frame.save(preview)
    print("OK", dest.name, out.size, f"cell {cw}x{ch}")


def soft_loop_bg(path: Path, band: int = 48) -> None:
    """Crossfade top/bottom edge so vertical tiling seam is softer."""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    band = min(band, h // 8)
    top = im.crop((0, 0, w, band))
    bot = im.crop((0, h - band, w, h))
    out = im.copy()
    for y in range(band):
        t = (y + 0.5) / band  # 0 at top edge → 1 inward
        # Top rows: blend toward bottom content
        row_top = Image.blend(
            top.crop((0, y, w, y + 1)),
            bot.crop((0, y, w, y + 1)),
            1.0 - t,
        )
        out.paste(row_top, (0, y))
        # Bottom rows: blend toward top content
        row_bot = Image.blend(
            bot.crop((0, y, w, y + 1)),
            top.crop((0, y, w, y + 1)),
            t,
        )
        out.paste(row_bot, (0, h - band + y))
    out.save(path)
    print("seam", path.name)


def main() -> None:
    skins = ROOT / "assets" / "images" / "skins"
    preview = skins / "preview"
    vors = ROOT / "assets" / "images" / "vors"
    bgc = ROOT / "assets" / "images" / "bgc"

    for name in ("p5.png", "p1.png"):
        process_sheet(skins / name, skins / name, preview / name)

    # Vor uses same sheet layout as players.
    vor_src = vors / "vor_sheet.png"
    if not vor_src.exists():
        vor_src = vors / "vor.png"
    process_sheet(vor_src, vors / "vor.png")
    process_sheet(vor_src, vors / "vor_sheet.png")

    for i in range(1, 9):
        p = bgc / f"{i}.png"
        if p.exists():
            soft_loop_bg(p, band=56)


if __name__ == "__main__":
    main()
