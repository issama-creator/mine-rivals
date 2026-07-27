"""Strip baked foot shadows and plant boot soles on the cell floor."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
COLS, ROWS = 6, 4
ALPHA = 10


def is_baked_shadow(r: int, g: int, b: int, a: int) -> bool:
    if a < ALPHA:
        return False
    # Soft near-black / deep brown oval under feet — not boot leather.
    if r + g + b > 95:
        return False
    # Boot leather is usually warmer / higher R than pure shadow.
    if r > 55 and r > g + 8 and r > b + 8:
        return False
    return True


def opaque_bbox(cell: Image.Image) -> tuple[int, int, int, int] | None:
    w, h = cell.size
    px = cell.load()
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > ALPHA:
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)
    if maxy < 0:
        return None
    return minx, miny, maxx, maxy


def boot_bottom(cell: Image.Image) -> int | None:
    """Lowest row with enough non-shadow opaque pixels (actual soles)."""
    w, h = cell.size
    px = cell.load()
    for y in range(h - 1, -1, -1):
        boots = 0
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= ALPHA:
                continue
            if not is_baked_shadow(r, g, b, a):
                boots += 1
        if boots >= 4:
            return y
    return None


def strip_shadow_and_plant(path: Path) -> None:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    cw, ch = w // COLS, h // ROWS
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pads: list[int] = []

    for row in range(ROWS):
        for col in range(COLS):
            cell = im.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
            px = cell.load()
            # Clear baked oval under / around feet.
            for y in range(ch):
                for x in range(cw):
                    r, g, b, a = px[x, y]
                    if is_baked_shadow(r, g, b, a):
                        # Only strip in the lower third so cart/clothes stay.
                        if y >= int(ch * 0.62):
                            px[x, y] = (0, 0, 0, 0)

            foot = boot_bottom(cell)
            bb = opaque_bbox(cell)
            if foot is None or bb is None:
                out.paste(cell, (col * cw, row * ch))
                continue

            target = ch - 1
            dy = target - foot
            shifted = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            if dy >= 0:
                src = cell.crop((0, 0, cw, ch - dy)) if dy else cell
                if dy:
                    shifted.paste(src, (0, dy), src)
                else:
                    shifted = cell.copy()
            else:
                src = cell.crop((0, -dy, cw, ch))
                shifted.paste(src, (0, 0), src)

            out.paste(shifted, (col * cw, row * ch), shifted)
            nbb = opaque_bbox(shifted)
            if nbb:
                pads.append(ch - 1 - nbb[3])

    out.save(path)
    print(
        path.name,
        "frames",
        COLS * ROWS,
        "pad_after",
        (min(pads), max(pads)) if pads else None,
    )


def main() -> None:
    # Start from last committed art, then plant — avoids compounding edits.
    import subprocess

    for rel in ("assets/images/skins/p5.png", "assets/images/vors/vor.png"):
        subprocess.check_call(["git", "checkout", "HEAD", "--", rel])
    # Re-apply prior foot pin baseline first? Better: strip+plant from clean.
    strip_shadow_and_plant(ROOT / "assets" / "images" / "skins" / "p5.png")
    strip_shadow_and_plant(ROOT / "assets" / "images" / "vors" / "vor.png")


if __name__ == "__main__":
    main()
