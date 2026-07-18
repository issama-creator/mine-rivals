"""Re-slice kristales → transparent object-only crops."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(r"c:\Users\islam\Desktop\mine riv\mineriv\assets\images\kristales")
OUT = ROOT / "crops"
OUT.mkdir(exist_ok=True)


def is_baked_checker_bg(r: int, g: int, b: int, a: int) -> bool:
    """White / light-gray checkerboard baked as opaque pixels."""
    if a < 8:
        return True
    mx, mn = max(r, g, b), min(r, g, b)
    sat = mx - mn
    # Light gray / white desaturated = sheet bg
    if sat <= 22 and mn >= 175:
        return True
    if sat <= 30 and mn >= 205:
        return True
    # Mid checker gray (~190–210)
    if sat <= 16 and 165 <= mn <= 230:
        return True
    return False


def is_black_bg(r: int, g: int, b: int, a: int) -> bool:
    if a < 8:
        return True
    if r <= 30 and g <= 30 and b <= 30:
        return True
    mx, mn = max(r, g, b), min(r, g, b)
    if mx <= 38 and mx - mn <= 10:
        return True
    return False


def key_out(img: Image.Image, mode: str) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            kill = (
                is_baked_checker_bg(r, g, b, a)
                if mode == "checker"
                else is_black_bg(r, g, b, a)
            )
            if kill:
                px[x, y] = (0, 0, 0, 0)
    return img


def detect_mode(img: Image.Image) -> str:
    """checker = baked light bg; alpha = already transparent / dark sheet."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    samples = [
        px[2, 2],
        px[w - 3, 2],
        px[2, h - 3],
        px[w - 3, h - 3],
        px[w // 2, 2],
        px[w // 2, h - 3],
    ]
    light = 0
    trans = 0
    for r, g, b, a in samples:
        if a < 20:
            trans += 1
        elif is_baked_checker_bg(r, g, b, a):
            light += 1
    if light >= 3:
        return "checker"
    if trans >= 3:
        return "alpha"
    # fallback: look at corner average
    r, g, b, a = samples[0]
    if a > 200 and min(r, g, b) > 160:
        return "checker"
    return "alpha"


def tight_crop(tile: Image.Image, pad: int = 2) -> Image.Image:
    tile = tile.convert("RGBA")
    bbox = tile.getbbox()
    if not bbox:
        return tile
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(tile.size[0], x1 + pad)
    y1 = min(tile.size[1], y1 + pad)
    return tile.crop((x0, y0, x1, y1))


def normalize(tile: Image.Image, max_side: int = 256) -> Image.Image:
    mw = max(tile.size)
    if mw <= 1:
        return tile
    if mw > max_side:
        scale = max_side / mw
        tile = tile.resize(
            (max(1, int(tile.size[0] * scale)), max(1, int(tile.size[1] * scale))),
            Image.Resampling.LANCZOS,
        )
    return tile


def cells_grid(img: Image.Image, cols: int, rows: int) -> list[Image.Image]:
    w, h = img.size
    out = []
    for r in range(rows):
        for c in range(cols):
            x0 = int(c * w / cols)
            y0 = int(r * h / rows)
            x1 = int((c + 1) * w / cols)
            y1 = int((r + 1) * h / rows)
            out.append(img.crop((x0, y0, x1, y1)))
    return out


def process_tile(tile: Image.Image, mode: str) -> Image.Image:
    if mode == "checker":
        tile = key_out(tile, "checker")
    else:
        # already alpha or dark sheet — still strip residual black
        tile = key_out(tile, "alpha")
    return normalize(tight_crop(tile))


def save_corridor(cid: int, tiles: list[Image.Image]):
    for i, tile in enumerate(tiles[:3]):
        path = OUT / f"c{cid}_{i}.png"
        tile.save(path, optimize=True)
        # verify
        px = tile.load()
        r, g, b, a = px[0, 0]
        print(f"  c{cid}_{i}.png {tile.size} corner_a={a}")


def main():
    for p in OUT.glob("*.png"):
        p.unlink()

    # 1–3,5: baked checkerboard sheets
    for n, cols in [(1, 3), (2, 3), (3, 3), (5, 5)]:
        img = Image.open(ROOT / f"{n}.png").convert("RGBA")
        mode = detect_mode(img)
        print(f"{n}.png mode={mode} size={img.size}")
        # key whole sheet first for cleaner cell edges
        if mode == "checker":
            img = key_out(img, "checker")
        cells = cells_grid(img, cols, 1)
        if n == 5:
            picks = [cells[0], cells[2], cells[4]]
        else:
            picks = cells[:3]
        save_corridor(n, [process_tile(t, mode) for t in picks])

    # 4: true alpha, 4 cells — pick 0,2,3
    img = Image.open(ROOT / "4.png").convert("RGBA")
    mode = detect_mode(img)
    print(f"4.png mode={mode}")
    cells = cells_grid(img, 4, 1)
    save_corridor(4, [process_tile(t, mode) for t in (cells[0], cells[2], cells[3])])

    # 6: 2x4 black/alpha
    img = Image.open(ROOT / "6.png").convert("RGBA")
    mode = detect_mode(img)
    print(f"6.png mode={mode}")
    g = cells_grid(img, 4, 2)
    save_corridor(6, [process_tile(t, mode) for t in (g[0], g[3], g[6])])

    # 7-8
    img = Image.open(ROOT / "7-8.png").convert("RGBA")
    mode = detect_mode(img)
    print(f"7-8.png mode={mode}")
    g = cells_grid(img, 4, 2)
    save_corridor(7, [process_tile(t, mode) for t in (g[0], g[2], g[3])])
    save_corridor(8, [process_tile(t, mode) for t in (g[4], g[5], g[7])])

    # 9-10
    img = Image.open(ROOT / "9-10.png").convert("RGBA")
    mode = detect_mode(img)
    print(f"9-10.png mode={mode}")
    g = cells_grid(img, 4, 2)
    save_corridor(9, [process_tile(t, mode) for t in (g[0], g[1], g[3])])
    save_corridor(10, [process_tile(t, mode) for t in (g[4], g[6], g[7])])

    # Final audit
    bad = 0
    for p in sorted(OUT.glob("*.png")):
        img = Image.open(p).convert("RGBA")
        px = img.load()
        w, h = img.size
        corner = px[0, 0]
        # sample edge
        edge_opaque_light = 0
        for x in range(0, w, max(1, w // 10)):
            r, g, b, a = px[x, 0]
            if a > 200 and min(r, g, b) > 175 and max(r, g, b) - min(r, g, b) < 25:
                edge_opaque_light += 1
        if corner[3] > 200 and min(corner[:3]) > 175:
            bad += 1
            print("BAD corner", p.name, corner)
        elif edge_opaque_light >= 3:
            bad += 1
            print("BAD edge", p.name, edge_opaque_light)
    print("done", len(list(OUT.glob('*.png'))), "bad", bad)


if __name__ == "__main__":
    main()
