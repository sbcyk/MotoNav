#!/usr/bin/env python3
"""离线预览圆屏主页（需 Pillow，仅 PC 用，不参与固件编译）。

几何、配色、绘制顺序必须与 src/pages/HomePage.h 保持一致；
画面素材从 resources/HomeSprites.h 里读，和固件同一份数据。
输出到 scripts/preview/*.png
"""
import math
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W = H = 466
CX = 233
DUST_TOP = 150
DUST_N = 26
FONT = "C:/Windows/Fonts/consola.ttf"

H_AMBER = 0xFD46
H_HOLY = 0xFE90
H_DUST = 0xFDEB
H_SPECTRAL_HI = 0xEFFF
H_CARD = 0x10A3
H_CARD_ED = 0x39E7
C_WHITE = 0xFFFF
C_GREY = 0x7BEF
C_GREEN = 0x07E0


def rgb565(c):
    return (((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31)


def blend565(a, b, t):
    it = 255 - t
    r = (((a >> 11) & 31) * it + ((b >> 11) & 31) * t + 127) // 255
    g = (((a >> 5) & 63) * it + ((b >> 5) & 63) * t + 127) // 255
    bl = ((a & 31) * it + (b & 31) * t + 127) // 255
    return (r << 11) | (g << 5) | bl


_HDR = (Path(__file__).resolve().parent.parent /
        "firmware/boards/175/MotoNav/resources/HomeSprites.h").read_text(encoding="utf-8")


def _num(name):
    return int(re.search(rf"#define {name} (-?\d+)", _HDR).group(1))


def _grab8(name):
    w = _num(f"{name}_W")
    h = _num(f"{name}_H")
    seg = _HDR[_HDR.index(f"{name}_PAL[256]"):]
    pal = [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{4})", seg[:seg.index("};")])]
    body = _HDR[_HDR.index(f"{name}_BITS["):]
    body = body[body.index("{") + 1:body.index("};")]
    data = bytes(int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{2})", body))
    img = Image.new("L", (w, h))
    img.putdata(list(data))
    return img, pal


_OFF, _OPAL = _grab8("SCENE_OFF")
_ON, _NPAL = _grab8("SCENE_ON")
BEAM_OFF = (_num("HOME_BEAM_OFF_X"), _num("HOME_BEAM_OFF_Y"))
BEAM_ON = (_num("HOME_BEAM_ON_X"), _num("HOME_BEAM_ON_Y"))


def base_image(mix):
    m = int(mix * 255 + 0.5)
    opx, npx = _OFF.load(), _ON.load()
    w, h = _OFF.size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            a, b = opx[x, y], npx[x, y]
            c = _OPAL[a] if m <= 0 else (_NPAL[b] if m >= 255 else blend565(_OPAL[a], _NPAL[b], m))
            px[x, y] = rgb565(c)
    return img.resize((W, H), Image.NEAREST)


class Scene:
    def __init__(self):
        self.img = None
        self.d = None

    def load(self, mix):
        self.img = base_image(mix)
        self.d = ImageDraw.Draw(self.img)

    def px(self):
        return self.img.load()

    def add_span(self, x, y, w, c, k):
        if k <= 0 or w <= 0 or y < 0 or y >= H:
            return
        x0, x1 = max(0, x), min(W, x + w)
        if x0 >= x1:
            return
        cr = (((c >> 11) & 31) * k) >> 4
        cg = (((c >> 5) & 63) * k) >> 4
        cb = ((c & 31) * k) >> 4
        px = self.img.load()
        for i in range(x0, x1):
            r, g, b = px[i, y]
            px[i, y] = (min(255, r + cr * 255 // 31), min(255, g + cg * 255 // 63),
                        min(255, b + cb * 255 // 31))

    def add_ellipse(self, cx, cy, rx, ry, c, kmax):
        if rx <= 0 or ry <= 0 or kmax <= 0:
            return
        for j in range(-ry, ry + 1):
            v = 1.0 - (j * j) / float(ry * ry)
            if v <= 0:
                continue
            w = int(rx * math.sqrt(v))
            if w <= 0:
                continue
            self.add_span(cx - w, cy + j, w * 2, c, int(kmax * v + 0.5))

    def disc(self, x, y, r, c):
        self.d.ellipse([x - r, y - r, x + r, y + r], fill=rgb565(c))


def beam(mix):
    return (int((BEAM_OFF[0] + (BEAM_ON[0] - BEAM_OFF[0]) * mix) * 2),
            int((BEAM_OFF[1] + (BEAM_ON[1] - BEAM_OFF[1]) * mix) * 2))


def dust(s, now, mix, boost=1.0):
    """光尘：加色点，跟固件 hEffects 同一套参数。"""
    bx, by = beam(mix)
    for i in range(DUST_N):
        ph = math.fmod(i / DUST_N + now * 0.00009, 1.0)
        y = by - int(ph * DUST_TOP)
        spread = 6 + ph * 26
        x = bx + int(math.sin(i * 2.7 + ph * 7.5 + now * 0.0011) * spread)
        fade = 1 - ph
        k = int(7 * fade * fade * boost)
        if k <= 0:
            continue
        r = 2 if ph < 0.3 else 1
        s.add_ellipse(x, y, r, r, H_DUST if i % 4 else H_HOLY, k)


def flare(s, now, mix, boost=1.0):
    bx, by = beam(mix)
    breath = 0.75 + 0.25 * math.sin(now * 0.0011)
    k = int((1.5 + 1.5 * breath) * boost + 0.5)
    s.add_ellipse(bx, by - 6, 26, 9, H_AMBER, k)
    s.add_ellipse(bx, by - 12, 12, 5, H_HOLY, k)
    if boost > 1.05:
        r = 20 + int(60 * (boost - 1.0) / 0.7)
        s.add_ellipse(bx, by, r, r // 4, H_SPECTRAL_HI, int((boost - 1.0) * 6))


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
    centered(s, "v2.0.0  40MHz", 336, 1, C_GREY)
    centered(s, "TAP TO CLOSE", 350, 1, 0x4208)


def crop(s):
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, W - 1, H - 1], fill=255)
    out = Image.new("RGB", (W, H), (0, 0, 0))
    out.paste(s.img, (0, 0), mask)
    return out


def render(mode, now=1428):
    if mode == "nolink":
        mix, boost = 0.0, 1.0
    elif mode == "summon":                    # 刚切到已连接：火还没闪完
        mix, boost = 1.0, 1.45
    else:                                     # ready / info
        mix, boost = 1.0, 1.0
    s = Scene()
    s.load(mix)
    flare(s, now, mix, boost)
    dust(s, now, mix, boost)
    if mode == "info":
        info_card(s)
    return crop(s)


if __name__ == "__main__":
    dest = Path(__file__).resolve().parent / "preview"
    dest.mkdir(exist_ok=True)
    for mode in ("nolink", "summon", "ready", "info"):
        render(mode).save(dest / f"home_{mode}.png")
        print(dest / f"home_{mode}.png")
