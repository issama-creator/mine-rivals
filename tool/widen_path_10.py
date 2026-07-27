"""Widen the central stone path in corridor BGs by ~10%."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BGC = ROOT / "assets" / "images" / "bgc"

# Measured mid-path band ≈ 0.344…0.667 (width ~0.323).
OLD_L, OLD_R = 0.344, 0.667
NEW_L, NEW_R = 0.328, 0.683  # ~10% wider (~0.355)


def src_x(nx: float) -> float:
    if nx <= NEW_L:
        t = nx / NEW_L if NEW_L > 0 else 0.0
        return t * OLD_L
    if nx >= NEW_R:
        t = (nx - NEW_R) / (1.0 - NEW_R) if NEW_R < 1 else 0.0
        return OLD_R + t * (1.0 - OLD_R)
    t = (nx - NEW_L) / (NEW_R - NEW_L)
    return OLD_L + t * (OLD_R - OLD_L)


def widen(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    src = im.load()
    out = Image.new("RGBA", (w, h))
    dst = out.load()
    # Precompute column map.
    map_x = [0] * w
    map_f = [0.0] * w
    for x in range(w):
        sx = src_x(x / max(1, w - 1)) * (w - 1)
        x0 = int(sx)
        map_x[x] = x0
        map_f[x] = sx - x0
    for x in range(w):
        x0 = map_x[x]
        x1 = min(w - 1, x0 + 1)
        f = map_f[x]
        inv = 1.0 - f
        for y in range(h):
            p0 = src[x0, y]
            p1 = src[x1, y]
            dst[x, y] = tuple(int(a * inv + b * f + 0.5) for a, b in zip(p0, p1))
    return out


def main() -> None:
    for i in range(1, 9):
        p = BGC / f"{i}.png"
        if not p.exists():
            continue
        im = widen(Image.open(p))
        im.save(p)
        print("OK", p.name, im.size)


if __name__ == "__main__":
    main()
