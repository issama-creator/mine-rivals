"""Pin feet to cell floor so sprites sit on the ground anchor."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
COLS, ROWS = 6, 4
ALPHA = 10


def opaque_bbox(cell: Image.Image) -> tuple[int, int, int, int] | None:
    w, h = cell.size
    px = cell.load()
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > ALPHA:
                if x < minx:
                    minx = x
                if y < miny:
                    miny = y
                if x > maxx:
                    maxx = x
                if y > maxy:
                    maxy = y
    if maxy < 0:
        return None
    return minx, miny, maxx, maxy


def shift_cell(cell: Image.Image, dy: int) -> Image.Image:
    w, h = cell.size
    if dy == 0:
        return cell.copy()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if dy > 0:
        src = cell.crop((0, 0, w, h - dy))
        out.paste(src, (0, dy))
    else:
        src = cell.crop((0, -dy, w, h))
        out.paste(src, (0, 0))
    return out


def pin_feet(path: Path) -> None:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    cw, ch = w // COLS, h // ROWS
    # Floor = last pixel row of the cell (anchor.bottomCenter).
    target_bot = ch - 1

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    final_bots: list[int] = []
    for row in range(ROWS):
        for col in range(COLS):
            cell = im.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
            bb = opaque_bbox(cell)
            if bb is None:
                continue
            dy = target_bot - bb[3]
            # Moving down may clip head — prefer feet planted.
            if dy < 0 and bb[1] + dy < 0:
                # Moving up: allow head to clip at top.
                pass
            pinned = shift_cell(cell, dy)
            nbb = opaque_bbox(pinned)
            # Second pass if still short of floor (tall clips).
            if nbb and nbb[3] < target_bot:
                room = nbb[1]
                need = target_bot - nbb[3]
                if need > 0 and room > 0:
                    pinned = shift_cell(pinned, min(room, need))
                    nbb = opaque_bbox(pinned)
            out.paste(pinned, (col * cw, row * ch))
            if nbb:
                final_bots.append(nbb[3])

    out.save(path)
    print(
        path.name,
        "target",
        target_bot,
        "range",
        (max(final_bots) - min(final_bots)) if final_bots else None,
        "bots",
        min(final_bots) if final_bots else None,
        max(final_bots) if final_bots else None,
        "pad",
        (target_bot - max(final_bots)) if final_bots else None,
    )


def main() -> None:
    pin_feet(ROOT / "assets" / "images" / "skins" / "p5.png")
    pin_feet(ROOT / "assets" / "images" / "vors" / "vor.png")


if __name__ == "__main__":
    main()
