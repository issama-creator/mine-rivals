"""Clean vor sprite sheet: remove frame numbers, key black BG, smooth cycle."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "vors" / "vor_sheet.png"
ALT = ROOT / "assets" / "images" / "vors" / "vor.png"
OUT = ROOT / "assets" / "images" / "vors" / "vor.png"
META = ROOT / "assets" / "images" / "vors" / "vor_meta.txt"
COLS, ROWS = 4, 6


def flood_key_black(im: Image.Image, limit: int = 28) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    pix = im.load()
    visited = [[False] * w for _ in range(h)]
    stack: list[tuple[int, int]] = []

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = pix[x, y]
        if a < 8:
            return True
        return r <= limit and g <= limit and b <= limit

    for x in range(w):
        stack.append((x, 0))
        stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y))
        stack.append((w - 1, y))

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or visited[y][x]:
            continue
        visited[y][x] = True
        if not is_bg(x, y):
            continue
        pix[x, y] = (0, 0, 0, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return im


def clear_number_band(cell: Image.Image, band_frac: float = 0.20) -> Image.Image:
    cell = cell.convert("RGBA")
    w, h = cell.size
    pix = cell.load()
    band = max(16, int(h * band_frac))
    for y in range(band):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if r >= 180 and g >= 180 and b >= 180:
                pix[x, y] = (0, 0, 0, 0)
    return cell


def mean_abs_diff(a: Image.Image, b: Image.Image) -> float:
    aa = a.resize((64, 32), Image.Resampling.BILINEAR).convert("L")
    bb = b.resize((64, 32), Image.Resampling.BILINEAR).convert("L")
    pa, pb = list(aa.getdata()), list(bb.getdata())
    return sum(abs(x - y) for x, y in zip(pa, pb)) / len(pa)


def blend(a: Image.Image, b: Image.Image, t: float) -> Image.Image:
    return Image.blend(a.convert("RGBA"), b.convert("RGBA"), t)


def main() -> None:
    # Prefer previously cleaned sheet if present; else raw.
    src = SRC if SRC.exists() else ALT
    raw = Image.open(src).convert("RGBA")
    # If already transparent, still clear numbers on cells.
    if raw.getextrema()[3][0] == 255:
        raw = flood_key_black(raw)
    else:
        # Re-key lightly in case numbers sit on black
        raw = flood_key_black(raw)

    w, h = raw.size
    # Original master is always 4×6 @ 1448×1086
    if h > 2000:
        # Already expanded smooth sheet — reload original dimensions from vor_sheet
        # before first expand if needed. Re-open SRC after we keep a backup path.
        pass

    # Use a 4×6 crop layout based on expected cell size from original.
    # If sheet was already expanded, regenerate from vor_sheet only.
    if (w, h) != (1448, 1086) and SRC.exists():
        # Re-read SRC — may already be cleaned 4×6
        probe = Image.open(SRC).convert("RGBA")
        if probe.size == (1448, 1086):
            raw = flood_key_black(probe)
            w, h = raw.size

    cw, ch = w // COLS, h // ROWS
    cells: list[Image.Image] = []
    for row in range(ROWS):
        for col in range(COLS):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            cells.append(clear_number_band(raw.crop(box)))

    # Pick unique poses (MAD threshold — near-duplicates collapse).
    unique: list[Image.Image] = [cells[0]]
    for cell in cells[1:]:
        if min(mean_abs_diff(cell, u) for u in unique) > 6.5:
            unique.append(cell)

    print(f"cells={len(cells)} unique={len(unique)}")

    # If still too many, sample evenly to ~6 key poses.
    if len(unique) > 8:
        step = max(1, len(cells) // 6)
        unique = [cells[i] for i in range(0, len(cells), step)][:6]
        print(f"resampled unique={len(unique)}")

    # Smooth cycle with 2 in-betweens between each pose (+ ping-pong feel).
    n = len(unique)
    smooth: list[Image.Image] = []
    order = list(range(n)) + list(range(n - 2, 0, -1))  # 0..n-1..1
    if len(order) < 2:
        order = [0]
    for i in range(len(order)):
        a = unique[order[i]]
        b = unique[order[(i + 1) % len(order)]]
        smooth.append(a)
        smooth.append(blend(a, b, 0.35))
        smooth.append(blend(a, b, 0.70))

    while len(smooth) % 4 != 0:
        smooth.append(smooth[0])

    out_cols = 4
    out_rows = len(smooth) // out_cols
    out = Image.new("RGBA", (cw * out_cols, ch * out_rows), (0, 0, 0, 0))
    for i, cell in enumerate(smooth):
        row, col = i // out_cols, i % out_cols
        out.paste(cell, (col * cw, row * ch), cell)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)

    # Cleaned 4×6 master without numbers (for re-runs)
    master = Image.new("RGBA", (cw * COLS, ch * ROWS), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        row, col = i // COLS, i % COLS
        master.paste(cell, (col * cw, row * ch), cell)
    master.save(SRC)

    META.write_text(f"columns={out_cols}\nrows={out_rows}\nframes={len(smooth)}\n")
    print("saved", OUT, out.size, f"frames={len(smooth)} grid={out_cols}x{out_rows}")
    print("saved cleaned master", SRC, master.size)


if __name__ == "__main__":
    main()
