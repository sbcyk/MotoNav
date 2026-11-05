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

W = H = 466                   # = pin_config.h 的 LCD_WIDTH / LCD_HEIGHT
CX = 233
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


_ROOT = Path(__file__).resolve().parent.parent
_HDR = (_ROOT / "firmware/boards/175/MotoNav/resources/HomeSprites.h").read_text(encoding="utf-8")
_HP = (_ROOT / "firmware/boards/175/MotoNav/src/pages/HomePage.h").read_text(encoding="utf-8")


def _num(name):
    return int(re.search(rf"#define\s+{name}\s+(-?\d+)", _HDR).group(1))


def _hp(name):
    """从 HomePage.h 读整数宏。常量只保留一份，免得固件改了预览静默跑偏。"""
    return int(re.search(rf"#define\s+{name}\s+(-?\d+)", _HP).group(1))


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


def base_image(use_on):
    """取一张完整画面，2x 放大到 466。use_on 为真取“已连接”那张。"""
    src, pal = (_ON, _NPAL) if use_on else (_OFF, _OPAL)
    w, h = src.size
    spx = src.load()
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = rgb565(pal[spx[x, y]])
    return img.resize((W, H), Image.NEAREST)


def hnoise(x, y):
    """与固件 hNoise 同一套位运算（uint32）。"""
    v = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFFFF
    v ^= v >> 13
    v = (v * 0x5BD1E995) & 0xFFFFFFFF
    v ^= v >> 15
    return v & 255


def pal_diff(a, b):
    """RGB565 两色的分量差之和，0~125。与固件 hPalDiff 一致。"""
    d = abs(((a >> 11) & 31) - ((b >> 11) & 31))
    e = abs(((a >> 5) & 63) - ((b >> 5) & 63))
    f = abs((a & 31) - (b & 31))
    return d + e + f


DUST_TOP = _hp("H_DUST_TOP")     # 光尘上升行程
DUST_N = _hp("H_DUST_N")         # 光尘数量
MIX_WMAX = _hp("MIX_WMAX")       # 溶解权重上限
MIX_WMIN = _hp("MIX_WMIN")       # 溶解权重下限
# 马在“已连接”那张里的位置（233 尺度），与固件 H_HORSE_* 同一来源
HORSE = (_hp("H_HORSE_CX"), _hp("H_HORSE_CY"), _hp("H_HORSE_RX"), _hp("H_HORSE_RY"))


def mix_image(t):
    """状态切换的抖动溶解（与固件 hMixScene 同一套公式）。

    每个像素有一个“起翻时刻”：权重越高越早，n 是它在这个区间里的抖动位置。
    两图差得多的像素（马、站起来的人）先翻先闪；本来一样的地方（火、天空）最后才翻，
    翻过去也看不出来。注意整屏都会闪，不是只有马那一块。
    """
    k = int(t * 256)
    w, h = _OFF.size
    opx, npx = _OFF.load(), _ON.load()
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            ca, cb = _OPAL[opx[x, y]], _NPAL[npx[x, y]]
            hx = (x - HORSE[0]) / HORSE[2]
            hy = (y - HORSE[1]) / HORSE[3]
            q = hx * hx + hy * hy
            wgt = pal_diff(ca, cb) + (int(28 * (1 - q)) if q < 1 else 0)
            if wgt > MIX_WMAX:
                wgt = MIX_WMAX
            speed = (MIX_WMIN + wgt) * 256 // (MIX_WMIN + MIX_WMAX)
            start = max(0, 255 - speed * (255 - hnoise(x, y)) // 255)
            c = cb if k > start else ca
            if k > 0 and start >= k and start - k < 10 and wgt > 18:
                c = H_HOLY if (x ^ y) & 1 else H_AMBER
            px[x, y] = rgb565(c)
    return img.resize((W, H), Image.NEAREST)


class Scene:
    def __init__(self):
        self.img = None
        self.d = None

    def load(self, use_on):
        self.img = base_image(use_on)
        self.d = ImageDraw.Draw(self.img)

    def load_mix(self, t):
        self.img = mix_image(t)
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


def beam(use_on):
    """固件 hBeamX/hBeamY 按 hOnScene 直接取一张的锚点，不做插值——这里跟它一致。"""
    bx, by = BEAM_ON if use_on else BEAM_OFF
    return bx * 2, by * 2


def dust(s, now, use_on, boost=1.0):
    """光尘：加色点，跟固件 hEffects 同一套参数。"""
    bx, by = beam(use_on)
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


def flare(s, now, use_on, boost=1.0):
    bx, by = beam(use_on)
    breath = 0.75 + 0.25 * math.sin(now * 0.0011)
    k = int((1.5 + 1.5 * breath) * boost + 0.5)
    s.add_ellipse(bx, by - 6, 26, 9, H_AMBER, k)
    s.add_ellipse(bx, by - 12, 12, 5, H_HOLY, k)
    if boost > 1.05:
        r = 20 + int(12 * (boost - 1.0) / 0.6)
        s.add_ellipse(bx, by, r, r // 4, H_SPECTRAL_HI, int((boost - 1.0) * 10))


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
    use_on = mix >= 0.5
    s.load(use_on)
    flare(s, now, use_on, boost)
    dust(s, now, use_on, boost)
    if mode == "info":
        info_card(s)
    return crop(s)


if __name__ == "__main__":
    dest = Path(__file__).resolve().parent / "preview"
    dest.mkdir(exist_ok=True)
    for mode in ("nolink", "summon", "ready", "info"):
        render(mode).save(dest / f"home_{mode}.png")
        print(dest / f"home_{mode}.png")
    for t in (0.25, 0.5, 0.75):
        s = Scene()
        s.load_mix(t)
        flare(s, 1428, t >= 0.5, 1.3)
        dust(s, 1428, t >= 0.5, 1.3)
        crop(s).save(dest / f"home_mix{int(t*100)}.png")
        print(dest / f"home_mix{int(t*100)}.png")
