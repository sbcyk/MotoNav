#!/usr/bin/env python3
"""生成苔林夜骑首页素材：单张 8bpp 底图 + 车灯几何参数。

和 `home_sprites.py`（艾尔登两态）不是一套东西，别混：
- 艾尔登靠两张同源图 + 一张共用调色板做“人马换姿”，所以有 SWAP_BOX 和失配校验；
- 苔林没有动作 morph，两态只差车灯亮/灭。车灯不进素材——固件在灯位叠加几何光，
  素材只出**一张没点亮灯**的底图。这样两态像素天然一致，也省掉整套调色板推导。

素材来源：`assets/reference/home-moss-base.png`
（1024 正方形，圆内是苔林山道 + 侧视摩托车，灯未点亮，画面无任何文字）

用法：python scripts/home_sprites_moss.py
"""
import math
from pathlib import Path

from PIL import Image

S = 233                                     # 底图边长，固件按 2 倍放大到 466
OUT = 466
SRC = "assets/reference/home-moss-base.png"

# 圆屏遮罩：源图整张就是圆，圆外一律压黑，免得圆角那圈残留素材底色
CIRCLE_EDGE_FEATHER = 2

# 车灯几何（**显示坐标 466**，固件直接用）。
# 参考图里车灯就是**一个亮起来的灯罩**：亮盘 + 一圈很短的辉光，路面不铺光斑。
# 所以这里只有灯盘半径和辉光半径两个量，别再加"光锥 / 地面光斑"那种东西。
# 生成时会校验灯盘中心确实是暗的——换底图后灯位跑偏会报错，不会静默画到挡泥板上。
LAMP = dict(x=314, y=222, r=9, glow=13)
LAMP_DARK_MAX = 70                          # 灯盘中心平均亮度上限：超过说明底图里灯是亮的

# 有序抖动而不是 Floyd-Steinberg：Bayer 的偏移只跟坐标有关，同一坐标同色必得同一索引
BAYER4 = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
DITHER_AMP = 9.0                            # 抖动幅度（0~255），约一个 RGB565 色阶


def clamp(v):
    return 0 if v < 0 else (255 if v > 255 else int(v))


def mask_circle(img):
    """圆外压黑，边缘按 CIRCLE_EDGE_FEATHER 羽化，避免圆边出现硬齿。"""
    px = img.load()
    n = img.width
    r = n / 2.0
    for y in range(n):
        for x in range(n):
            d = math.hypot(x + 0.5 - r, y + 0.5 - r)
            if d > r:
                px[x, y] = (8, 10, 9)
            elif d > r - CIRCLE_EDGE_FEATHER:
                k = (r - d) / CIRCLE_EDGE_FEATHER
                px[x, y] = tuple(int(v * k + o * (1 - k))
                                 for v, o in zip(px[x, y], (8, 10, 9)))


def load233(path):
    if not path.exists():
        raise SystemExit(f"缺少参考图：{path}")
    im = Image.open(path).convert("RGB")
    if im.width != im.height:
        raise SystemExit(f"{path} 必须是正方形，当前 {im.size}")
    mask_circle(im)
    return im.resize((S, S), Image.LANCZOS)


def bayer(img):
    out = img.copy()
    p = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = p[x, y]
            d = (BAYER4[y & 3][x & 3] / 16.0 - 0.5) * DITHER_AMP
            p[x, y] = (clamp(r + d), clamp(g + d), clamp(b + d))
    return out


def check_lamp_dark(img):
    """灯盘中心必须是暗的：底图要求“灯没点亮”。

    这里按显示坐标取样（源图是 233，乘 2 换算），取 5x5 邻域平均亮度，
    超过 LAMP_DARK_MAX 说明底图里灯已经是亮的，那固件再叠加一次就双层光。
    """
    px = img.load()
    cx, cy = LAMP["x"] // 2, LAMP["y"] // 2
    acc, n = 0.0, 0
    for y in range(cy - 2, cy + 3):
        for x in range(cx - 2, cx + 3):
            if 0 <= x < S and 0 <= y < S:
                r, g, b = px[x, y]
                acc += 0.299 * r + 0.587 * g + 0.114 * b
                n += 1
    avg = acc / n
    if avg > LAMP_DARK_MAX:
        raise SystemExit(f"灯盘位置 ({LAMP['x']},{LAMP['y']}) 平均亮度 {avg:.0f}，"
                         f"超过 {LAMP_DARK_MAX}：底图里灯已经点亮了，换灯灭的那张")


def emit_pal(quant):
    raw = list(quant.getpalette() or [])
    raw += [0] * (768 - len(raw))
    out = ["static const uint16_t MOSS_PAL[256] = {"]
    for i in range(0, 256, 16):
        row = []
        for j in range(i, i + 16):
            r, g, b = raw[j * 3], raw[j * 3 + 1], raw[j * 3 + 2]
            row.append(f"0x{((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3):04X}")
        out.append("  " + ",".join(row) + ",")
    out.append("};")
    return "\n".join(out)


def emit_idx(quant):
    w, h = quant.size
    px = quant.load()
    data = bytearray()
    for y in range(h):
        for x in range(w):
            data.append(px[x, y])
    if len(data) != S * S:
        raise SystemExit(f"索引长度 {len(data)} 不等于 {S * S}")
    out = [f"static const uint8_t MOSS_IDX[{len(data)}] = {{"]
    for i in range(0, len(data), 24):
        out.append("  " + ",".join(f"0x{v:02X}" for v in data[i:i + 24]) + ",")
    out.append("};")
    return "\n".join(out)


def main():
    root = Path(__file__).resolve().parent.parent
    base = load233(root / SRC)
    check_lamp_dark(base)

    quant = bayer(base).quantize(colors=256, method=Image.Quantize.MEDIANCUT,
                                 dither=Image.Dither.NONE)

    dest = root / "firmware/boards/175/MotoNav/resources/HomeSpritesMoss.h"
    body = [
        "#pragma once",
        "// 苔林夜骑首页画面：单张 8bpp 索引色底图，233x233，固件按 2x 放大到 466x466。",
        "// 由 scripts/home_sprites_moss.py 生成，别手改。",
        "//",
        "// 两态**不换素材**：底图是同一张（灯没点亮），已连接时由固件在下面这组坐标上",
        "// 叠加几何光（hAddEllipse 加色），未连接不叠加。像素天然一致，不存在对不上的问题。",
        f"#define MOSS_W {S}",
        f"#define MOSS_H {S}",
        "",
        "// 车灯几何（显示坐标，466）：亮盘 + 一圈短辉光。路面不铺光斑。",
        f"#define MOSS_LAMP_X {LAMP['x']}",
        f"#define MOSS_LAMP_Y {LAMP['y']}",
        f"#define MOSS_LAMP_R {LAMP['r']}",
        f"#define MOSS_GLOW_R {LAMP['glow']}",
        "",
        emit_pal(quant),
        "",
        emit_idx(quant),
    ]
    dest.write_text("\n".join(body) + "\n", encoding="utf-8", newline="\n")

    dump = Path(__file__).resolve().parent / "preview"
    dump.mkdir(exist_ok=True)
    quant.convert("RGB").resize((OUT, OUT), Image.NEAREST).save(dump / "moss_base.png")
    print(dest, dest.stat().st_size // 1024, "KB")
    print(f"车灯 ({LAMP['x']},{LAMP['y']}) 灯盘 r={LAMP['r']} 辉光 r={LAMP['glow']}  "
          f"索引 {S * S} 字节")


if __name__ == "__main__":
    main()
