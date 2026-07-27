"""Replace shaft BGs + wire p5/p1 skins; delete old skin assets."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "bgc" / "bgc and players"
BGC = ROOT / "assets" / "images" / "bgc"
SKINS = ROOT / "assets" / "images" / "skins"
PREVIEW = SKINS / "preview"
VORS = ROOT / "assets" / "images" / "vors"


def key_white(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    pix = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if r >= 245 and g >= 245 and b >= 245:
                pix[x, y] = (0, 0, 0, 0)
            elif (
                r >= 225
                and g >= 225
                and b >= 225
                and abs(r - g) < 12
                and abs(g - b) < 12
            ):
                pix[x, y] = (0, 0, 0, 0)
    return im


def main() -> None:
    PREVIEW.mkdir(parents=True, exist_ok=True)

    # 1) Replace corridors 1–8; drop old 9–10
    for i in range(1, 9):
        s = SRC / f"{i}.png"
        d = BGC / f"{i}.png"
        im = Image.open(s).convert("RGBA")
        im.save(d, optimize=True)
        print("bgc", i, im.size)
    for i in (9, 10):
        p = BGC / f"{i}.png"
        if p.exists():
            p.unlink()
            print("deleted", p.name)

    # 2) Process p5 / p1 (4×6 top-down sheets)
    for name in ("p5.png", "p1.png"):
        im = key_white(Image.open(SRC / name))
        dest = SKINS / name
        im.save(dest)
        fw, fh = im.size[0] // 4, im.size[1] // 6
        frame = im.crop((0, 0, fw, fh))
        bbox = frame.getbbox()
        if bbox:
            frame = frame.crop(bbox)
        frame.save(PREVIEW / name)
        print("skin", name, im.size, "preview", frame.size)

    # 3) Keep new vor sheet for later (same style as players)
    vor_src = SRC / "vor.png"
    if vor_src.exists():
        im = key_white(Image.open(vor_src))
        im.save(VORS / "vor_sheet.png")
        print("vor_sheet", im.size)

    # 4) Delete old skin assets (keep only p5 / p1)
    keep = {"p5.png", "p1.png"}
    for p in list(SKINS.glob("*.png")) + list(PREVIEW.glob("*.png")):
        if p.name not in keep:
            p.unlink()
            print("del skin", p.relative_to(ROOT))

    # Also remove leftover source sheets under skins/
    for extra in (
        "pers_asset.png",
        "pers_asset1.png",
        "pers_asset_2.png",
    ):
        p = SKINS / extra
        if p.exists():
            p.unlink()
            print("del", extra)

    # 5) Clear nested source folder after copy
    for p in list(SRC.iterdir()):
        if p.is_file():
            p.unlink()
            print("del nested", p.name)
    try:
        SRC.rmdir()
        print("removed folder bgc and players")
    except OSError as e:
        print("folder not empty", e)

    print("DONE")


if __name__ == "__main__":
    main()
