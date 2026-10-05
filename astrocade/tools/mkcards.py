#!/usr/bin/env python3
"""mkcards.py -- card art -> assets/cardart.inc (zmac, raw 2bpp).

Card geometry (see README.md): cards are 12x17 pixels on an 8-pixel pitch,
drawn left to right, so a covered card shows its left 8 pixels. Column 0 is
the black seam line that separates overlapping white cards; rank and suit
therefore live inside pixels 1-7. The white body (with its rounded corners)
is painted by code in cards.inc; this file holds only the stamps that need
more than the expander's two colors per blit -- each is raw 2bpp with the
seam column baked in:

  SUITH/D/S/C  12x6, rows 8-13 of the card: suit shape, red or black
  TENR/TENB    12x6, rows 1-6: the "10" rank ("1" and "0" composited from
               the Lynx font BMPs so it matches the other ranks)
  CARDBK       12x17: face-down card, white ring + red lattice
  CHIP         4x5: the bet chip

Pixel values are palette registers: 0 felt, 1 black, 2 red, 3 white.
Output is committed; rerun after art changes (make assets).
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LYNX = os.path.normpath(os.path.join(HERE, "..", "..", "src", "lynx", "4x6"))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "cardart.inc"))

FELT, BLACK, RED, WHITE = 0, 1, 2, 3
GLYPH = {FELT: ".", BLACK: "K", RED: "r", WHITE: " "}

CARD_W, CARD_H = 12, 17


def read_bmp_ink(path: str, w: int, h: int) -> list[list[int]]:
    """Ink flags (1 = black pixel) from a 4bpp black-on-white Windows BMP."""
    with open(path, "rb") as f:
        data = f.read()
    offset = int.from_bytes(data[10:14], "little")
    bw = int.from_bytes(data[18:22], "little")
    bh = int.from_bytes(data[22:26], "little", signed=True)
    bpp = int.from_bytes(data[28:30], "little")
    if (bw, bh, bpp) != (w, h, 4):
        raise SystemExit(f"mkcards: {path}: {bw}x{bh}x{bpp}, want {w}x{h}x4")
    stride = ((bw * 4 + 31) // 32) * 4
    rows = []
    for y in range(h):
        base = offset + (h - 1 - y) * stride
        row = []
        for x in range(w):
            nib = data[base + x // 2] >> 4 if x % 2 == 0 else \
                data[base + x // 2] & 0x0F
            row.append(1 if nib == 0 else 0)
        rows.append(row)
    return rows


# 5-wide suit shapes at card pixels 3-7 (visually centered in the card's
# white, and whole even when the card is half-covered).
SUITS = {
    "SUITH": (RED, [
        ".#.#.",
        "#####",
        "#####",
        ".###.",
        "..#..",
        ".....",
    ]),
    "SUITD": (RED, [
        "..#..",
        ".###.",
        "#####",
        ".###.",
        "..#..",
        ".....",
    ]),
    "SUITS": (BLACK, [
        "..#..",
        ".###.",
        "#####",
        "#####",
        "..#..",
        ".###.",
    ]),
    "SUITC": (BLACK, [
        "..#..",
        ".###.",
        "##.##",
        "#####",
        "..#..",
        ".###.",
    ]),
}


def stamp_rows(color: int, ink_rows: list[list[int]]) -> list[list[int]]:
    """A 12-wide card stamp: seam at 0, ink over white starting at px1."""
    out = []
    for ink in ink_rows:
        row = [BLACK] + [WHITE] * (CARD_W - 1)
        for x, on in enumerate(ink):
            if on:
                row[1 + x] = color
        out.append(row)
    return out


def suit_stamp(color: int, art: list[str]) -> list[list[int]]:
    ink = [[1 if ch == "#" else 0 for ch in (".." + row + "....")]
           for row in art]                      # 5-wide art at px 3-7
    return stamp_rows(color, ink)


def ten_stamp(color: int) -> list[list[int]]:
    """'10' from the font's own 1 and 0 glyphs: 1 at px 1-3, 0 at px 5-7."""
    one = read_bmp_ink(os.path.join(LYNX, "1.bmp"), 4, 6)
    zero = read_bmp_ink(os.path.join(LYNX, "0.bmp"), 4, 6)
    ink = []
    for r1, r0 in zip(one, zero):
        ink.append(r1[:3] + [0] + r0[:3] + [0] * 4)     # glyph ink is cols 0-2
    return stamp_rows(color, ink)


def facedown() -> list[list[int]]:
    rows = []
    for y in range(CARD_H):
        if y in (0, CARD_H - 1):
            rows.append([FELT] + [WHITE] * (CARD_W - 1))    # rounded corner
            continue
        row = [BLACK, WHITE]
        for x in range(2, CARD_W - 1):
            row.append(RED if (x + y) & 1 else WHITE)
        row.append(WHITE)
        rows.append(row)
    return rows


def chip() -> list[list[int]]:
    art = [".##.", "####", "#  #", "####", ".##."]
    lut = {".": FELT, "#": RED, " ": WHITE}
    return [[lut[ch] for ch in row] for row in art]


def pack(rows: list[list[int]]) -> list[int]:
    """2bpp bytes, leftmost pixel in bits 7-6; width must be a multiple of 4."""
    out = []
    for row in rows:
        assert len(row) % 4 == 0, len(row)
        for i in range(0, len(row), 4):
            out.append((row[i] << 6) | (row[i + 1] << 4)
                       | (row[i + 2] << 2) | row[i + 3])
    return out


def emit(lines: list[str], label: str, rows: list[list[int]]) -> int:
    w = len(rows[0])
    lines.append(f"; {label}: {w}x{len(rows)}")
    lines.append(f"{label}:")
    for row, packed in zip(rows, [pack([r])[0:len(r) // 4] for r in rows]):
        assert all(len(r) == w for r in rows)
        vals = ",".join(f"{b:03X}H" for b in packed)
        art = "".join(GLYPH[p] for p in row)
        lines.append(f"        DB      {vals:<20}; {art}")
    return len(rows) * (w // 4)


def main() -> int:
    lines = [
        "; cardart.inc -- raw 2bpp card stamps, GENERATED by tools/mkcards.py",
        "; -- do not edit; rerun `make assets`. Pixel values are palette",
        "; registers (0 felt, 1 black, 2 red, 3 white); leftmost pixel is",
        "; bits 7-6. Proof art: K black, r red, space white, dot felt.",
    ]
    total = 0
    for label, (color, art) in SUITS.items():
        total += emit(lines, label, suit_stamp(color, art))
    total += emit(lines, "TENR", ten_stamp(RED))
    total += emit(lines, "TENB", ten_stamp(BLACK))
    total += emit(lines, "CARDBK", facedown())
    total += emit(lines, "CHIP", chip())
    lines.append("")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("\n".join(lines))
    print(f"mkcards: {total} bytes -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
