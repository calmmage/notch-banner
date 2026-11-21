#!/usr/bin/env python3
"""Generate a crisp pixel-art NotchBanner icon (PNG + macOS .icns)."""
from pathlib import Path
import struct, subprocess, tempfile, zlib

ROOT = Path(__file__).resolve().parent.parent / "assets"
ROOT.mkdir(parents=True, exist_ok=True)

# 16x16 pixel-art velvet theater curtain hanging from a black MacBook notch
PALETTE = {
    ".": (13, 15, 21, 255),     # dark obsidian bg
    "k": (0, 0, 0, 255),        # notch black
    "d": (56, 9, 20, 255),      # deep velvet shadow
    "r": (112, 20, 38, 255),    # rich garnet velvet
    "h": (162, 42, 62, 255),    # grazing velvet nap highlight
    "g": (232, 198, 124, 255),  # antique gold braid
    "b": (175, 136, 70, 255),   # dark gold stitch
}
GRID = [
    "...kkkkkkkkkk...",
    "...kkkkkkkkkk...",
    "..bggggggggggb..",
    "..grhddrhdrrdg..",
    "..grhddrhdrrdg..",
    "..grhddrhdrrdg..",
    "..grhddrhdrhdg..",
    "..grddhrhddrgg..",
    "..grddhrhddrgg..",
    "..gdrdhrhddrbg..",
    "..gdrhhrddhrbg..",
    "..gdrhhrddhrbg..",
    "..gbbbbbbbbbbg..",
    "...gggg..gggg...",
    "....bb....bb....",
    "................",
]

def write_png(path: Path, pixels: bytes, w: int, h: int):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + pixels[y * w * 4:(y + 1) * w * 4] for y in range(h))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)

def render_size(size: int) -> bytes:
    scale = size // 16
    out = bytearray(size * size * 4)
    for gy, row in enumerate(GRID):
        for gx, ch in enumerate(row):
            rgba = PALETTE[ch]
            for dy in range(scale):
                y = gy * scale + dy
                for dx in range(scale):
                    x = gx * scale + dx
                    # Rounded macOS icon corners
                    rx, ry = min(x, size - 1 - x), min(y, size - 1 - y)
                    rad = size * 0.22
                    if rx < rad and ry < rad and (rad - rx) ** 2 + (rad - ry) ** 2 > rad ** 2:
                        continue
                    o = (y * size + x) * 4
                    out[o:o + 4] = bytes(rgba)
    return bytes(out)

write_png(ROOT / "icon.png", render_size(512), 512, 512)
with tempfile.TemporaryDirectory() as td:
    iconset = Path(td) / "AppIcon.iconset"
    iconset.mkdir()
    for sz in [16, 32, 64, 128, 256, 512]:
        write_png(iconset / f"icon_{sz}x{sz}.png", render_size(sz), sz, sz)
        if sz <= 512:
            write_png(iconset / f"icon_{sz}x{sz}@2x.png", render_size(sz * 2), sz * 2, sz * 2)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ROOT / "icon.icns")], check=True)
print("Generated assets/icon.png and assets/icon.icns")
