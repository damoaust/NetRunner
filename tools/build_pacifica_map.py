"""Generate a Pacifica Region world-map PNG (80s cyberpunk vibe).

Output:
  C:/Users/mecca/Documents/netrunner-v-0.006/data/world_pacifica_map.png

Style: dark teal ocean, magenta/cyan grid lines, neon-amber continents
roughly tracing Pacifica (west-coast NA + Japan/Korea/Philippines +
Australia). No fonts — pure procedural shapes drawn via Pillow primitives
so it works headless.
"""
from __future__ import annotations

from PIL import Image, ImageDraw, ImageFilter
import math
from pathlib import Path

OUT_PATH = Path(r"C:/Users/mecca/Documents/netrunner-v-0.006/data/world_pacifica_map.png")
W, H = 1280, 720

# 80s cyberpunk palette
OCEAN_TOP   = (4, 12, 22)
OCEAN_BOT   = (0, 36, 56)
GRID_LINE   = (0, 220, 200, 70)
GRID_LINE_M = (240, 60, 180, 80)
WCOAST_F    = (60, 220, 140, 80)
WCOAST_E    = (140, 255, 200, 220)
PAC_RIM_F   = (255, 110, 30, 90)
PAC_RIM_E   = (255, 200, 80, 230)
OCEANIA_F   = (0, 200, 200, 80)
OCEANIA_E   = (0, 255, 240, 220)
HUB_MAJOR   = (255, 240, 80)
HUB_MINOR   = (140, 255, 200)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(min(len(a), len(b))))


def make_canvas():
    img = Image.new("RGBA", (W, H), OCEAN_TOP + (255,))
    grad = Image.new("RGBA", (W, H), OCEAN_TOP + (255,))
    px = grad.load()
    for y in range(H):
        col = lerp(OCEAN_TOP, OCEAN_BOT, y / H)
        for x in range(W):
            px[x, y] = col + (255,)
    img.paste(grad, (0, 0), grad)
    return img


def draw_grid(img: Image.Image):
    draw = ImageDraw.Draw(img, "RGBA")
    for x in range(0, W, 24):
        for y in range(0, H, 6):
            draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=GRID_LINE)
    for y in range(0, H, 28):
        for x in range(0, W, 12):
            draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=GRID_LINE)
    for y in (160, 340, 520):
        draw.line((0, y, W, y), fill=GRID_LINE_M, width=1)


WEST_COAST_USA = [
    (90, 80), (185, 78), (255, 90), (310, 130), (330, 180),
    (300, 230), (235, 245), (175, 250), (130, 230), (95, 200),
    (70, 150), (75, 110),
]
PAC_RIM = [
    (820, 60), (920, 55), (1010, 70), (1080, 100), (1130, 145),
    (1100, 195), (1030, 215), (945, 220), (875, 200), (835, 165),
    (820, 125), (815, 90),
]
JAPAN = [
    (1095, 200), (1145, 215), (1175, 245), (1160, 285), (1115, 305),
    (1075, 290), (1055, 260), (1050, 230), (1075, 210),
]
PHILIPPINES = [
    (1010, 360), (1050, 370), (1075, 405), (1060, 445), (1020, 460),
    (980, 440), (965, 410), (980, 380),
]
OCEANIA_AU = [
    (905, 470), (1010, 460), (1110, 475), (1180, 510), (1190, 565),
    (1130, 615), (1040, 625), (945, 615), (885, 575), (870, 525),
    (880, 495),
]


def draw_land(img, poly, fill, edge):
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow, "RGBA")
    gdraw.polygon(poly, fill=(edge[0], edge[1], edge[2], 90))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=8))
    img.paste(glow, (0, 0), glow)
    draw = ImageDraw.Draw(img, "RGBA")
    draw.polygon(poly, fill=fill)
    draw.line(poly + [poly[0]], fill=edge, width=2, joint="curve")


HUBS = [
    (165, 165, "NIGHT CITY", HUB_MAJOR),
    (120, 130, "CHICAGO",    HUB_MINOR),
    (210, 215, "MEXICO",     HUB_MINOR),
    (1115, 250, "TOKYO",     HUB_MAJOR),
    (1050, 220, "SEOUL",     HUB_MINOR),
    (1015, 410, "MANILA",    HUB_MINOR),
    (1030, 545, "SYDNEY",    HUB_MAJOR),
    (945, 565, "PERTH",      HUB_MINOR),
]


def draw_hub(img, x, y, label, color):
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow, "RGBA")
    gdraw.ellipse((x - 14, y - 14, x + 14, y + 14), fill=(color[0], color[1], color[2], 110))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=5))
    img.paste(glow, (0, 0), glow)
    draw = ImageDraw.Draw(img, "RGBA")
    draw.ellipse((x - 8, y - 8, x + 8, y + 8), outline=color + (255,), width=2)
    draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=color + (255,))
    bx1 = x + 12
    bx2 = bx1 + 90
    by1 = y - 9
    by2 = y + 9
    draw.rectangle((bx1, by1, bx2, by2), fill=(0, 0, 0, 170), outline=color + (255,), width=1)


def draw_scanline_sweep(img, t: float):
    draw = ImageDraw.Draw(img, "RGBA")
    cy = int(H * t)
    for offset in range(-2, 3):
        a = 90 if offset == 0 else 35
        draw.line((0, cy + offset, W, cy + offset), fill=(240, 60, 180, a), width=1)


def add_vignette(img):
    vig = Image.new("L", (W, H), 0)
    v = vig.load()
    cx, cy = W / 2, H / 2
    maxd = math.hypot(cx, cy)
    for y in range(H):
        for x in range(0, W, 4):
            d = math.hypot(x - cx, y - cy) / maxd
            v[x, y] = max(0, min(255, int(255 * d * 1.4)))
    vig = vig.filter(ImageFilter.GaussianBlur(radius=24))
    black = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    img.paste(black, (0, 0), vig)


def main():
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img = make_canvas()
    draw_grid(img)
    draw_scanline_sweep(img, 0.45)

    draw_land(img, WEST_COAST_USA, WCOAST_F, WCOAST_E)
    draw_land(img, PAC_RIM,      PAC_RIM_F, PAC_RIM_E)
    draw_land(img, JAPAN,        PAC_RIM_F, PAC_RIM_E)
    draw_land(img, PHILIPPINES,  PAC_RIM_F, PAC_RIM_E)
    draw_land(img, OCEANIA_AU,   OCEANIA_F, OCEANIA_E)

    for hub in HUBS:
        draw_hub(img, *hub)

    add_vignette(img)

    img.save(OUT_PATH, "PNG", optimize=True)
    print(f"Saved: {OUT_PATH}")
    print(f"Size:  {OUT_PATH.stat().st_size} bytes")


if __name__ == "__main__":
    main()