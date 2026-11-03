#!/usr/bin/env python3
"""离线预览圆屏主页（需 Pillow，仅 PC 用，不参与固件编译）。

几何与颜色必须与 src/pages/HomePage.h 保持一致。
输出到 scripts/preview/*.png
"""
import math
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W = H = 466
CX = 233
BASE_Y = 352
GRACE_H = 168
GRACE_AMP = 12
DUST_TOP = 300
DUST_N = 34
FONT = "C:/Windows/Fonts/consola.ttf"

H_AMBER = 0xFE0B
H_HOLY = 0xFEF2
H_PALE = 0xFF9A
H_DUST = 0xFDEB
H_SOIL = 0x528C
H_SOIL_D = 0x31A6
H_STONE = 0x2945
H_CARD = 0x10A3
H_CARD_ED = 0x39E7
H_SPECTRAL = 0x7BEF
H_SPECTRAL_HI = 0xEFFF
C_WHITE = 0xFFFF
C_GREY = 0x7BEF
C_GREEN = 0x07E0


def rgb565(c):
    return (((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31)


def hdim(c, k):
    k = max(0, min(32, int(k)))
    r, g, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
    return ((r * k >> 5) << 11) | ((g * k >> 5) << 5) | (b * k >> 5)


def hmix(c, a):
    return hdim(c, int(a * 32 + 0.5))


class Scene:
    def __init__(self):
        self.img = Image.new("RGB", (W, H), (0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def rect(self, x, y, w, h, c):
        self.d.rectangle([x, y, x + w - 1, y + h - 1], fill=rgb565(c))

    def ellipse(self, x, y, rx, ry, c):
        self.d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=rgb565(c))

    def ellipse_line(self, x, y, rx, ry, c):
        self.d.ellipse([x - rx, y - ry, x + rx, y + ry], outline=rgb565(c))

    def disc(self, x, y, r, c):
        self.d.ellipse([x - r, y - r, x + r, y + r], fill=rgb565(c))


_HDR = (Path(__file__).resolve().parent.parent /
        "firmware/boards/175/MotoNav/resources/HomeSprites.h").read_text(encoding="utf-8")


def _grab(name):
    w = int(re.search(rf"#define {name}_W (\d+)", _HDR).group(1))
    h = int(re.search(rf"#define {name}_H (\d+)", _HDR).group(1))
    x = int(re.search(rf"#define {name}_X (-?\d+)", _HDR).group(1))
    y = int(re.search(rf"#define {name}_Y (-?\d+)", _HDR).group(1))
    pal = [int(v, 16) for v in re.findall(
        r"0x([0-9A-Fa-f]{4})", _HDR[_HDR.index(f"{name}_PAL[16]"):].split(";")[0])]
    body = _HDR[_HDR.index(f"{name}_BITS["):]
    body = body[body.index("{") + 1:body.index("};")]
    data = bytes(int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{2})", body))
    stride = (w + 1) // 2
    img = Image.new("L", (w, h), 0)
    px = img.load()
    for row in range(h):
        for col in range(w):
            b = data[row * stride + (col >> 1)]
            px[col, row] = (b >> 4) & 0x0F if col % 2 == 0 else b & 0x0F
    return img, x, y, pal


_M, _MX, _MY, _MPAL = _grab("TORRENT")


def blit4bpp(s, img, pal, ox, oy, a=1.0, reveal=1.0):
    px = img.load()
    k = max(0, min(32, int(a * 32)))
    rows = img.size[1] if reveal >= 1.0 else int(img.size[1] * reveal)
    skip = img.size[1] - rows
    for yy in range(skip, img.size[1]):
        for xx in range(img.size[0]):
            v = px[xx, yy]
            if v:
                s.img.putpixel((ox + xx, oy + yy), rgb565(hdim(pal[v], k)))


def grace_ground(s, breath):
    for i in range(22):
        f = i / 22.0
        w = int(120 * (1 - f * f))
        if w <= 0:
            break
        s.rect(CX - w, 344 + i, w * 2, 1, hdim(H_AMBER, int(7 * (1 - f) * breath)))
    pebbles = [(70, 384, 10, 4, 12), (112, 394, 8, 3, 10), (156, 386, 7, 3, 11),
               (300, 390, 9, 4, 12), (344, 382, 8, 3, 11), (388, 392, 7, 3, 10),
               (198, 400, 11, 4, 12), (262, 396, 9, 4, 11)]
    for (x, y, rx, ry, k) in pebbles:
        s.ellipse(x, y, rx, ry, hdim(H_STONE, k))


def grace_mound(s):
    s.ellipse(CX, 352, 30, 10, H_SOIL_D)
    s.ellipse(CX, 350, 22, 7, H_SOIL)
    s.ellipse(CX, 348, 13, 4, hdim(H_HOLY, 20))


def grace_ring(s, breath):
    s.ellipse(CX, 356, 48, 10, hdim(H_AMBER, int(4 * breath)))
    s.ellipse_line(CX, 356, 60, 15, hdim(H_HOLY, int(10 * breath)))
    s.ellipse_line(CX, 356, 50, 12, hdim(H_HOLY, int(17 * breath)))
    s.ellipse_line(CX, 356, 40, 10, hdim(H_HOLY, int(8 * breath)))


def grace_pulse(s, now, boost):
    p = math.fmod(now * 0.00042, 1.0)
    r = 30 + int(65 * p)
    s.ellipse_line(CX, 356, r, r // 4, hdim(H_HOLY, int(14 * (1 - p) * boost)))


def grace(s, now, breath, boost=1.0):
    flick = 0.84 + 0.16 * math.sin(now * 0.0071)
    hgt = GRACE_H + int(GRACE_AMP * math.sin(now * 0.0009))
    top_y = BASE_Y - hgt
    for i in range(7):
        f = i / 6.0
        s.ellipse(CX, top_y + 62, int(26 * (1 - 0.62 * f)), int(62 * (1 - 0.62 * f)),
                  hdim(H_AMBER, int((1 + 5 * f) * breath * boost)))
    for i in range(hgt):
        t = i / hgt
        u = 1 - t
        xx = CX + int(math.sin(t * 4.6 + now * 0.0014) * (2 + 8 * t))
        w = int(9.0 * u * math.sqrt(u))
        if w > 0:
            s.rect(xx - w, BASE_Y - i, w * 2, 1, hdim(H_AMBER, int(12 * u * flick * boost)))
        w2 = int(5.8 * (u ** 0.7) + 1.0)
        s.rect(xx - w2, BASE_Y - i, w2 * 2, 1,
               hdim(H_HOLY if i % 7 else H_PALE, int(30 * u * flick * boost)))
    s.ellipse(CX, 350, 22, 7, hdim(H_HOLY, int(16 * boost)))
    s.ellipse(CX, 350, 13, 5, hdim(H_HOLY, int(26 * boost)))
    s.ellipse(CX, 350, 6, 2, H_PALE)


def dust(s, now, boost=1.0):
    for i in range(DUST_N):
        ph = math.fmod(i / DUST_N + now * 0.00011, 1.0)
        y = 348 - int(ph * DUST_TOP)
        spread = 8 + ph * 58
        x = CX + int(math.sin(i * 2.7 + ph * 7.5 + now * 0.0012) * spread)
        fade = 1 - ph
        k = int(34 * fade * fade * boost)
        if k <= 1:
            continue
        s.disc(x, y, 2.2 if ph < 0.3 else 1.2, hdim(H_DUST if i % 4 else H_PALE, k))


def torrent(s, a, reveal):
    if a <= 0.01 or reveal <= 0.01:
        return
    blit4bpp(s, _M, _MPAL, _MX, _MY, a, reveal)


def summon_fx(s, now, p, direction=1):
    t = p if direction > 0 else 1 - p
    r = 24 + int(72 * t)
    s.ellipse_line(CX, 356, r, max(1, r // 4), hdim(H_SPECTRAL, int(6 + 16 * (1 - t))))
    for i in range(12):
        ang = i * 0.524 + now * 0.0013
        d = (1 - t) * (40 + i * 8)
        px = CX + int(math.cos(ang) * d)
        py = 350 - int(math.sin(ang) * d * 0.6) - int(t * 60)
        s.disc(px, py, 1.5, hmix(H_SPECTRAL_HI if i % 3 else H_PALE, 0.85 * t))


def centered(s, text, y, size, color):
    font = ImageFont.truetype(FONT, size * 8, index=0)
    box = s.d.textbbox((0, 0), text, font=font)
    s.d.text((CX - (box[2] - box[0]) // 2, y), text, font=font, fill=rgb565(color))


def info_card(s):
    s.d.rounded_rectangle([CX - 152, 130, CX - 152 + 303, 130 + 237], 18, fill=rgb565(H_CARD))
    s.d.rounded_rectangle([CX - 152, 130, CX - 152 + 303, 130 + 237], 18, outline=rgb565(H_CARD_ED))
    centered(s, "21:36", 148, 8, C_WHITE)
    centered(s, "2026-11-03", 226, 2, C_GREY)
    s.d.line([(CX - 118, 254), (CX + 118, 254)], fill=rgb565(0x2945))
    centered(s, "LINKED", 266, 2, C_GREEN)
    centered(s, "MotoNav-3F2A", 290, 2, C_GREY)
    centered(s, "BAT 87%", 312, 2, C_GREY)
    centered(s, "v1.1.1  40MHz", 336, 1, C_GREY)
    centered(s, "TAP TO CLOSE", 350, 1, 0x4208)


def crop(s):
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, W - 1, H - 1], fill=255)
    out = Image.new("RGB", (W, H), (0, 0, 0))
    out.paste(s.img, (0, 0), mask)
    return out


def render(mode, now=1428):
    breath = 0.88 + 0.12 * math.sin(now * 0.0011)
    s = Scene()
    if mode == "summon":
        p = 0.45
        boost = 1.0 + 0.7 * (1 - p)
        rp = min(1.0, p / 0.6)
        horse_a = p / 0.25 * 0.35 if p < 0.25 else 0.35 + (p - 0.25) / 0.75 * 0.65
        horse_r = rp
    else:
        boost = 1.0
        horse_a = 1.0 if mode in ("ready", "info") else 0.0
        horse_r = horse_a
    grace_ground(s, breath)
    grace_mound(s)
    grace_ring(s, breath)
    grace_pulse(s, now, boost)
    torrent(s, horse_a, horse_r)
    grace(s, now, breath, boost)
    dust(s, now, boost)
    if mode == "summon":
        summon_fx(s, now, 0.45)
    if mode == "info":
        info_card(s)
    return crop(s)


if __name__ == "__main__":
    dest = Path(__file__).resolve().parent / "preview"
    dest.mkdir(exist_ok=True)
    for mode in ("nolink", "summon", "ready", "info"):
        render(mode).save(dest / f"home_{mode}.png")
        print(dest / f"home_{mode}.png")
