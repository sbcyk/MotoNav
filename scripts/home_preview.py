#!/usr/bin/env python3
"""离线预览圆屏主页（需 Pillow，仅 PC 用，不参与固件编译）。

画面从 resources/HomeSprites.h 读，和固件同一份数据；信息层的版式常量（时间 / 日期 /
行位置、环半径、星芒半高）直接从 src/pages/HomeBand.h 的 #define 解析，配色也对齐它——
常量只保留一份，固件改了预览不会静默跑偏。绘制顺序跟 HomePage.h 的 hDrawFull 一致。
输出到 scripts/preview/*.png

t=0 是独坐（未连接，人在赐福里交互）、t=1 是起身牵马（已连接），中间只有人和马在变，
按 t 出几帧就能看出背景是不是真的没动——这正是要验的东西。
"""
import math
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

W = H = 466                   # = pin_config.h 的 LCD_WIDTH / LCD_HEIGHT
CX = 233
FONT = "C:/Windows/Fonts/consola.ttf"

H_AMBER = 0xFD46
H_HOLY = 0xFE90
H_DUST = 0xFDEB
H_SPECTRAL_HI = 0xEFFF
H_SPARK_HI = 0x8E5F
H_SPARK = 0x3BDB
H_SPARK_LO = 0x19F1
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


def _pal():
    seg = _HDR[_HDR.index("SCENE_PAL[256]"):]
    return [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{4})", seg[:seg.index("};")])]


def _bits(name):
    body = _HDR[_HDR.index(f"{name}["):]
    body = body[body.index("{") + 1:body.index("};")]
    data = bytes(int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{2})", body))
    img = Image.new("L", (SCENE_W, SCENE_H))
    img.putdata(list(data))
    return img


SCENE_W = _num("SCENE_W")
SCENE_H = _num("SCENE_H")
PAL = _pal()
OFF = _bits("SCENE_OFF_BITS")
ON = _bits("SCENE_ON_BITS")
PTS = [int(v) for v in re.findall(r"\d+", _HDR[_HDR.index("HOME_PTS["):].split("{")[1].split("};")[0])]

BEAM = (_num("HOME_BEAM_X"), _num("HOME_BEAM_Y"))
BEAM_BOX = (_num("HOME_BEAM_X0"), _num("HOME_BEAM_Y0"), _num("HOME_BEAM_X1"), _num("HOME_BEAM_Y1"))
MAN = (_num("HOME_MAN_X0"), _num("HOME_MAN_X1"), _num("HOME_MAN_Y0"), _num("HOME_MAN_Y1"))
HRS = (_num("HOME_HRS_X0"), _num("HOME_HRS_X1"), _num("HOME_HRS_Y0"), _num("HOME_HRS_Y1"))
DUST_TOP_SIT = _hp("H_DUST_TOP_SIT")
DUST_TOP_STAND = _hp("H_DUST_TOP_STAND")
DUST_N = _hp("H_DUST_N")
SPK_N = _hp("H_SPK_N")


def _spk():
    """从 HomePage.h 里读粒子锚点表，免得预览和固件各写一份。"""
    body = _HP[_HP.index("hSpkPts["):]
    body = body[body.index("{") + 1: body.index("};")]
    nums = [int(v) for v in re.findall(r"-?\d+", body)]
    return [(nums[i], nums[i + 1]) for i in range(0, len(nums), 2)]


SPK_PTS = _spk()


def hnoise(x, y):
    """与固件 hNoise 同一套位运算（uint32）。"""
    v = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFFFF
    v ^= v >> 13
    v = (v * 0x5BD1E995) & 0xFFFFFFFF
    v ^= v >> 15
    return v


def man_progress(t):
    v = t / 0.55
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def hrs_progress(t):
    v = (t - 0.25) / 0.75
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def horse_order(x, y):
    from_bottom = (HRS[3] - y) * 128 // (HRS[3] - HRS[2])
    return 1 + (hnoise(x, y) & 127) + from_bottom


MAN_BAND = _hp("H_MAN_BAND")


def stood(x, y, man_line):
    """与固件 hStood 一致：扫描线附近是一条噪声过渡带，不是一刀切。"""
    d = y - man_line
    if d >= MAN_BAND:
        return True
    if d <= -MAN_BAND:
        return False
    th = (d + MAN_BAND) * 255 // (2 * MAN_BAND)
    return (hnoise(x, y) & 255) < th


def man_line_of(man_t):
    span = MAN[3] - MAN[2] + 2 * MAN_BAND
    return MAN[3] + MAN_BAND - int(man_t * span + 0.5)


def scene_image(t):
    """与固件 hScene 同一套判定：背景两态一样，只有人和马按进度换。"""
    man_t = man_progress(t)
    hrs_t = hrs_progress(t)
    man_line = man_line_of(man_t)
    hrs_k = int(hrs_t * 256)
    opx, npx = OFF.load(), ON.load()
    img = Image.new("RGB", OFF.size)
    px = img.load()
    for sy in range(OFF.height):
        man_row = MAN[2] <= sy < MAN[3]
        hrs_row = HRS[2] <= sy < HRS[3]
        beam_row = BEAM_BOX[1] <= sy < BEAM_BOX[3]
        for sx in range(OFF.width):
            a, b = opx[sx, sy], npx[sx, sy]
            if a == b:
                idx = b
                px[sx, sy] = rgb565(PAL[idx])
                continue
            in_man = man_row and MAN[0] <= sx < MAN[1]
            in_hrs = hrs_row and HRS[0] <= sx < HRS[1]
            in_beam = beam_row and BEAM_BOX[0] <= sx < BEAM_BOX[2]
            if in_man and in_hrs:      # 马头右缘与人手相连：两边都到位才翻
                idx = b if (stood(sx, sy, man_line) and horse_order(sx, sy) <= hrs_k) else a
            elif in_man:
                idx = b if stood(sx, sy, man_line) else a
            elif in_hrs:
                idx = b if horse_order(sx, sy) <= hrs_k else a
            elif in_beam:              # 柱高两态不同：按噪声阈值随进度逐个翻
                idx = b if (hnoise(sx, sy) & 255) < int(t * 256) else a
            else:
                idx = b
            px[sx, sy] = rgb565(PAL[idx])
    return img.resize((W, H), Image.NEAREST)


class Scene:
    def __init__(self):
        self.img = None
        self.d = None

    def load(self, t):
        self.img = scene_image(t)
        self.d = ImageDraw.Draw(self.img)

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


def sparks(s, hrs_t):
    """马身上的蓝粒子：与固件 hHorseSparks 同一套参数。"""
    if hrs_t <= 0.02 or hrs_t >= 0.97:
        return
    wgt = 1.0 - abs(2.0 * hrs_t - 1.0)
    away = (1.0 - hrs_t) ** 2
    kmax = int(26.0 * wgt) + 4
    for i in range(len(PTS) // 2):
        tx, ty = PTS[i * 2], PTS[i * 2 + 1]
        n = hnoise(i * 29 + 7, i * 13 + 3)
        dx = (n & 63) - 32
        dy = ((n >> 6) & 63) - 40
        x = tx + int(dx * away * 1.1)
        y = ty + int(dy * away * 1.1)
        if not (0 <= x < SCENE_W and 0 <= y < SCENE_H):
            continue
        c = H_SPARK_HI if i % 3 == 0 else (H_SPARK if i % 3 == 1 else H_SPARK_LO)
        r = 2 if i % 4 == 0 else 1
        s.add_ellipse(x * 2, y * 2, r, r, c, kmax)


def bless_sparks(s, now, boost, man_t):
    """赐福闪烁粒子：与固件 hBlessSparks 同一套参数（坐火多而亮，未坐火少而暗）。"""
    bx, by = BEAM[0] * 2, BEAM[1] * 2
    rest = man_t < 0.5
    n = SPK_N if rest else SPK_N // 2
    kmax = 13 if rest else 8
    for i in range(n):
        x = bx + SPK_PTS[i][0] + int(math.sin(now * 0.00052 + i * 2.3) * 3.0)
        y = by + SPK_PTS[i][1] + int(math.sin(now * 0.00091 + i * 1.7) * 4.0)
        tw = math.sin(now * (0.0045 + (i & 3) * 0.0012) + i * 2.399)
        if tw <= 0.2:
            continue
        q = (tw - 0.2) * 1.25
        k = int(kmax * q * q * boost + 0.5)
        if k <= 0:
            continue
        c = H_SPECTRAL_HI if q > 0.9 else (H_HOLY if (i & 3) else H_DUST)
        r = 2 if q > 0.7 else 1
        s.add_ellipse(x, y, r, r, c, k)


def dim_bless(s, cx, cy, rx, ry, k):
    """未交互时把赐福压暗一档：火是画面唯一光源，压周围的亮度，它自然就弱了。

    不能靠加色区分——母版的火本来就快到饱和，加多加少都是白。
    中心压得最多，往外按椭圆距离淡出，边界看不出来。
    """
    if k <= 0:
        return
    px = s.img.load()
    lim = float(rx * rx * ry * ry)
    for y in range(max(0, cy - ry), min(H, cy + ry + 1)):
        dy2 = (y - cy) ** 2
        for x in range(max(0, cx - rx), min(W, cx + rx + 1)):
            d2 = ((x - cx) ** 2 * ry * ry + dy2 * rx * rx) / lim
            if d2 >= 1.0:
                continue
            keep = 1.0 - (k / 16.0) * (1.0 - d2)
            r, g, b = px[x, y]
            px[x, y] = (int(r * keep), int(g * keep), int(b * keep))


def ground(s, now, boost, man_t):
    """火光 + 光尘 + 闪烁粒子：亮度、火苗大小、光尘行程、粒子多少都随姿态变。"""
    bx, by = BEAM[0] * 2, BEAM[1] * 2
    dim_bless(s, bx, by - 4, 78, 50, int(7 * man_t + 0.5))
    lit = int(16.0 * (1.0 - 0.44 * man_t) + 0.5)
    lift = int(6.0 * (1.0 - 0.55 * man_t) + 0.5)
    dust_top = int(DUST_TOP_SIT + (DUST_TOP_STAND - DUST_TOP_SIT) * man_t)
    fw = int(23.0 * (1.0 - 0.40 * man_t) + 0.5)
    fh = int(12.0 * (1.0 - 0.42 * man_t) + 0.5)
    breath = 0.75 + 0.25 * math.sin(now * 0.0011)
    k = int((1.5 + 1.5 * breath) * boost * lit / 16.0 + 0.5)
    s.add_ellipse(bx, by - lift, fw, fh, H_AMBER, k)
    s.add_ellipse(bx, by - lift - 6, (fw * 15 + 17) // 34, (fh * 7 + 6) // 12, H_HOLY, k)
    # 光柱现在画在母版里（两张图本来就一有一无），不再靠加色叠一根上去
    if boost > 1.05:
        r = 20 + int(12 * (boost - 1.0) / 0.6)
        s.add_ellipse(bx, by, r, r // 4, H_SPECTRAL_HI, int((boost - 1.0) * 10))
    dust_n = DUST_N // 2 if man_t > 0.5 else DUST_N
    for i in range(dust_n):
        ph = math.fmod(i / float(dust_n) + now * 0.00009, 1.0)
        y = by - int(ph * dust_top)
        spread = 6 + ph * 26
        x = bx + int(math.sin(i * 2.7 + ph * 7.5 + now * 0.0011) * spread)
        fade = 1 - ph
        dk = int(7 * fade * fade * boost)
        if dk <= 0:
            continue
        r = 2 if ph < 0.3 else 1
        s.add_ellipse(x, y, r, r, H_DUST if i % 4 else H_HOLY, dk)
    bless_sparks(s, now, boost, man_t)


def centered(s, text, y, size, color):
    font = ImageFont.truetype(FONT, size * 8, index=0)
    box = s.d.textbbox((0, 0), text, font=font)
    s.d.text((CX - (box[2] - box[0]) // 2, y), text, font=font, fill=rgb565(color))


# ---- 常驻信息带：常量从 HomeBand.h 读，和固件同一份 ----
_BAND = (_ROOT / "firmware/boards/175/MotoNav/src/pages/HomeBand.h").read_text(encoding="utf-8")


def _band(name, default):
    m = re.search(rf"#define\s+{name}\s+(-?\d+)", _BAND)
    return int(m.group(1)) if m else default


def _565(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


GOLD_TXT = _565(244, 222, 170)      # 时间：暖白金
GOLD_SUB = _565(214, 188, 138)      # 日期 / 地点：暗金
GOLD_RING = _565(206, 166, 74)      # 环
INK = _565(20, 14, 6)               # 描边：深褐黑，不是纯黑


def soft_dim(s, box, strength=0.40, feather=30):
    """柔和压暗：椭圆遮罩 + 高斯模糊，没有矩形边界。

    比描边干净得多——字浮在自然暗下去的一块上，而不是每个字都镶一圈黑。
    """
    w, h = box[2] - box[0], box[3] - box[1]
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, w - 1, h - 1], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather))
    region = s.img.crop(box)
    dark = ImageEnhance.Brightness(region).enhance(1.0 - strength)
    s.img.paste(dark, box, mask)


def band_text(s, text, y, size, color, x=None, outline=0):
    """文字。默认不描边——底子已经柔和压暗过，再镶黑边就脏了。"""
    font = ImageFont.truetype(FONT, size * 8, index=0)
    box = s.d.textbbox((0, 0), text, font=font)
    tw = box[2] - box[0]
    left = CX - tw // 2 if x is None else x
    if outline:
        for dy in (-outline, 0, outline):
            for dx in (-outline, 0, outline):
                if dx == 0 and dy == 0:
                    continue
                s.d.text((left + dx, y + dy), text, font=font, fill=rgb565(INK))
    s.d.text((left, y), text, font=font, fill=rgb565(color))
    return tw


HB_TIME_Y = _band("HB_TIME_Y", 52)
HB_DATE_Y = _band("HB_DATE_Y", 128)
HB_ROW_Y = _band("HB_ROW_Y", 156)
HB_RING_R = _band("HB_RING_R", 224)
HB_SPARK_R = _band("HB_SPARK_R", 7)


def draw_ring(s):
    """金色细环 + 四向星芒。环贴着圆边走，星芒落在 12/3/6/9。"""
    r = HB_RING_R
    s.d.ellipse([CX - r, CX - r, CX + r, CX + r], outline=rgb565(GOLD_RING), width=2)
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        x = CX + math.cos(a) * r
        y = CX + math.sin(a) * r
        s.d.polygon([(x, y - HB_SPARK_R), (x + 5, y), (x, y + HB_SPARK_R), (x - 5, y)], fill=rgb565(GOLD_TXT))


def wx_cloud(s, cx, cy, sz, color):
    s.disc(cx - sz * 0.5, cy + sz * 0.08, sz * 0.42, color)
    s.disc(cx + sz * 0.05, cy - sz * 0.2, sz * 0.58, color)
    s.disc(cx + sz * 0.55, cy + sz * 0.12, sz * 0.38, color)
    s.d.rounded_rectangle([cx - sz * 0.92, cy + sz * 0.02, cx + sz * 0.92, cy + sz * 0.52],
                          int(sz * 0.25), fill=rgb565(color))


def info_band(s, time="21:36", date="2026-11-03", temp=16, loc="LIMGRAVE"):
    """融合版信息层：环 + 星芒 + 时间 + 日期 + 地点 + 天气。

    排版照参考图：时间最大居中，日期紧跟，地点靠左下、天气靠右下，中间让给王城。
    字全用暖金色系（和画面唯一的光源同色）；可读性靠两块柔和压暗的椭圆，
    不用描边，也没有矩形边界——暗是慢慢淡下去的，看不出来从哪开始。
    """
    draw_ring(s)
    soft_dim(s, (34, 24, 432, 150), 0.40, 36)
    soft_dim(s, (66, 146, 400, 184), 0.30, 24)

    band_text(s, time, HB_TIME_Y, 8, GOLD_TXT)
    band_text(s, date + "   TUE", HB_DATE_Y, 2, GOLD_SUB)

    y = HB_ROW_Y
    lx = CX - 132
    s.d.polygon([(lx + 5, y + 2), (lx + 9, y + 8), (lx + 5, y + 14), (lx + 1, y + 8)],
                outline=rgb565(GOLD_SUB))
    band_text(s, loc, y, 2, GOLD_SUB, x=lx + 14)

    wx_cloud(s, CX + 74, y + 8, 12, 0xDEFB)
    font = ImageFont.truetype(FONT, 16, index=0)
    label = str(temp)
    box = s.d.textbbox((0, 0), label, font=font)
    tw = box[2] - box[0]
    tx = CX + 128 - tw - 6
    s.d.text((tx, y), label, font=font, fill=rgb565(GOLD_TXT))
    ox = CX + 128 - 4
    s.d.ellipse([ox, y + 4, ox + 4, y + 8], outline=rgb565(GOLD_TXT))


_FW = (_ROOT / "firmware/boards/175/MotoNav/src/core/FirmwareConfig.h").read_text(encoding="utf-8")
FW_VER = re.search(r'#define\s+FW_VERSION\s+"([^"]+)"', _FW).group(1)   # 版本串只留一份，别在预览里再抄一遍


def info_card(s):
    s.d.rounded_rectangle([CX - 152, 130, CX - 152 + 303, 130 + 237], 18, fill=rgb565(H_CARD))
    s.d.rounded_rectangle([CX - 152, 130, CX - 152 + 303, 130 + 237], 18, outline=rgb565(H_CARD_ED))
    centered(s, "21:36", 148, 8, C_WHITE)
    centered(s, "2026-11-03", 226, 2, C_GREY)
    s.d.line([(CX - 118, 254), (CX + 118, 254)], fill=rgb565(0x2945))
    centered(s, "LINKED", 266, 2, C_GREEN)
    centered(s, "MotoNav-3F2A", 290, 2, C_GREY)
    centered(s, "BAT 87%", 312, 2, C_GREY)
    centered(s, f"{FW_VER}  40MHz", 336, 1, C_GREY)
    centered(s, "TAP TO CLOSE", 350, 1, 0x4208)


def crop(s):
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, W - 1, H - 1], fill=255)
    out = Image.new("RGB", (W, H), (0, 0, 0))
    out.paste(s.img, (0, 0), mask)
    return out


def render(t, now=1428, boost=1.0, info=False, band=False):
    s = Scene()
    s.load(t)
    hrs_t = hrs_progress(t)
    if 0.02 < hrs_t < 0.97:
        sparks(s, hrs_t)
    ground(s, now, boost, man_progress(t))
    if band:
        info_band(s)
    if info:
        info_card(s)
    return crop(s)


if __name__ == "__main__":
    dest = Path(__file__).resolve().parent / "preview"
    dest.mkdir(exist_ok=True)
    shots = [("nolink", 0.0, 1.0, False, False), ("ready", 1.0, 1.0, False, False),
             ("band", 1.0, 1.0, False, True), ("band_int", 0.0, 1.0, False, True),
             ("info", 1.0, 1.0, True, False), ("summon", 1.0, 1.45, False, False)]
    for name, t, boost, info, band in shots:
        render(t, boost=boost, info=info, band=band).save(dest / f"home_{name}.png")
        print(dest / f"home_{name}.png")
    for t in (0.2, 0.35, 0.5, 0.65, 0.8):
        render(t, now=1428, boost=1.3).save(dest / f"home_t{int(t*100):02d}.png")
        print(dest / f"home_t{int(t*100):02d}.png")
    # 过渡期间背景是否真的没动：拿 t=0 和 t=1 逐像素比，人马矩形外必须 0 差异
    a, b = scene_image(0.0).load(), scene_image(1.0).load()
    bad = 0
    for y in range(H):
        for x in range(W):
            if a[x, y] != b[x, y]:
                sx, sy = x // 2, y // 2
                if not ((MAN[0] <= sx < MAN[1] and MAN[2] <= sy < MAN[3]) or
                        (HRS[0] <= sx < HRS[1] and HRS[2] <= sy < HRS[3]) or
                        (BEAM_BOX[0] <= sx < BEAM_BOX[2] and BEAM_BOX[1] <= sy < BEAM_BOX[3])):
                    bad += 1
    if bad:
        raise SystemExit(f"背景校验失败：两态在人马矩形与柱带之外有 {bad} 个像素不同，"
                         f"说明素材没对齐或矩形常量改错了")
    print("背景校验：两态在人马矩形与柱带之外差异 0 像素")
