#!/usr/bin/env python3
"""生成首页占位立绘：2bpp 位图（0 透明 / 1 本体 / 2 边缘光），输出 C 头文件。
形状用胶囊体和多边形拼，轮廓平滑但硬边，适合圆屏。替换成正式立绘时重跑本脚本。
用法：python scripts/home_sprites.py
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw

SS = 4  # 超采样倍数


class Sheet:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("L", (w * SS, h * SS), 0)
        self.d = ImageDraw.Draw(self.img)

    def _s(self, v):
        return int(round(v * SS))

    def capsule(self, p0, p1, r):
        (x0, y0), (x1, y1) = p0, p1
        n = max(2, int(math.hypot(x1 - x0, y1 - y0)))
        for i in range(n + 1):
            t = i / n
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            self.d.ellipse([self._s(x - r), self._s(y - r), self._s(x + r), self._s(y + r)], fill=255)

    def ellipse(self, x, y, rx, ry):
        self.d.ellipse([self._s(x - rx), self._s(y - ry), self._s(x + rx), self._s(y + ry)], fill=255)

    def poly(self, pts):
        self.d.polygon([(self._s(x), self._s(y)) for x, y in pts], fill=255)

    def mask(self):
        return self.img.resize((self.w, self.h), Image.LANCZOS).point(lambda v: 255 if v >= 110 else 0)


def shift(mask, dx=0, dy=0):
    out = Image.new("L", mask.size, 0)
    out.paste(mask, (dx, dy))
    return out


def tarnished():
    """抱膝坐姿，朝右（篝火在右边）。脚底 y≈133，画布 180x140。"""
    s = Sheet(180, 140)
    s.poly([(74, 62), (50, 133), (126, 133), (104, 100), (84, 66)])   # 披风
    s.capsule((86, 104), (80, 72), 24)          # 弓着的背
    s.capsule((80, 72), (94, 56), 17)           # 肩
    s.ellipse(102, 42, 14, 15)                  # 低着的头
    s.poly([(88, 34), (100, 16), (112, 34), (104, 26)])  # 兜帽
    s.capsule((94, 64), (122, 86), 9)           # 环抱的手臂
    s.ellipse(130, 88, 15, 14)                  # 膝
    s.capsule((96, 106), (128, 92), 12)         # 大腿
    s.capsule((133, 90), (144, 126), 10)        # 小腿
    s.capsule((145, 129), (165, 132), 7)        # 靴
    s.capsule((84, 108), (96, 114), 20)         # 臀
    return s.mask()


def torrent():
    """灵马托雷特：浅灰白灵体，朝左。长颈、小头、前弯的双角、细腿、下垂长尾。
    画布 240x170，脚底 y≈166。"""
    s = Sheet(240, 170)
    # 躯干
    s.ellipse(124, 92, 54, 24)
    s.ellipse(74, 94, 26, 24)
    s.ellipse(174, 88, 26, 24)
    # 长颈与头
    s.capsule((76, 80), (48, 36), 15)
    s.capsule((46, 32), (22, 42), 10)
    s.capsule((26, 44), (17, 49), 5)
    # 双角（向前弯）
    s.capsule((37, 27), (29, 11), 3)
    s.capsule((29, 11), (22, 3), 2)
    s.capsule((46, 25), (40, 9), 3)
    s.capsule((40, 9), (34, 1), 2)
    # 耳与鬃毛
    s.poly([(49, 27), (56, 13), (60, 28)])
    s.poly([(78, 66), (50, 24), (61, 20), (85, 58)])
    # 腿
    s.capsule((84, 112), (80, 164), 6)
    s.capsule((104, 114), (100, 164), 6)
    s.capsule((152, 112), (148, 164), 7)
    s.capsule((174, 110), (170, 164), 7)
    # 尾
    s.capsule((192, 84), (210, 122), 5)
    s.capsule((210, 122), (214, 158), 3)
    # 鞍
    s.poly([(108, 76), (134, 74), (138, 85), (110, 87)])
    return s.mask()


PAL = [(0, 0, 0), (24, 26, 30), (52, 56, 64), (86, 92, 104),
       (126, 134, 150), (170, 180, 198), (214, 224, 242), (240, 246, 255)]


def shade(mask, light, origin, lit="left"):
    """按到光源的距离分 2..6 阶，交界处用棋盘抖动过渡；受光侧最外 2px 为 7 号边缘光。"""
    w, h = mask.size
    mp = mask.load()
    dist = {}
    for y in range(h):
        for x in range(w):
            if mp[x, y]:
                dist[(x, y)] = math.hypot(origin[0] + x - light[0], origin[1] + y - light[1])
    if not dist:
        return Image.new("L", (w, h), 0)
    d0, d1 = min(dist.values()), max(dist.values())
    span = max(1.0, d1 - d0)
    out = Image.new("L", (w, h), 0)
    op = out.load()
    for (x, y), d in dist.items():
        t = 1.0 - (d - d0) / span
        dith = 0.45 if (x + y) % 2 == 0 else -0.45
        op[x, y] = max(1, min(6, 2 + int(t * 4.2 + dith)))
    for y in range(h):
        row = [x for x in range(w) if mp[x, y]]
        if not row:
            continue
        edge = row[0] if lit == "left" else row[-1]
        for k in range(2):
            ex = edge + k if lit == "left" else edge - k
            if 0 <= ex < w and mp[ex, y]:
                op[ex, y] = 7
    return out


def to_c(name, img, x, y, comment, pal):
    w, h = img.size
    stride = (w + 1) // 2
    px = img.load()
    data = bytearray()
    for row in range(h):
        for col in range(0, w, 2):
            hi = px[col, row] & 0x0F
            lo = px[col + 1, row] & 0x0F if col + 1 < w else 0
            data.append((hi << 4) | lo)
        assert len(data) == (row + 1) * stride
    lines = [f"// {comment}"]
    lines.append(f"#define {name}_W {w}")
    lines.append(f"#define {name}_H {h}")
    lines.append(f"#define {name}_X {x}")
    lines.append(f"#define {name}_Y {y}")
    pal565 = []
    for (r, g, b) in pal:
        pal565.append(f"0x{((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3):04X}")
    lines.append(f"static const uint16_t {name}_PAL[16] = {{{','.join(pal565)}}} ;".replace(" ;", ";"))
    lines.append(f"static const uint8_t {name}_BITS[{len(data)}] = {{")
    for i in range(0, len(data), 16):
        lines.append("  " + ",".join(f"0x{v:02X}" for v in data[i:i + 16]) + ",")
    lines.append("};")
    return "\n".join(lines)


def main():
    root = Path(__file__).resolve().parent.parent
    dest = root / "firmware/boards/175/MotoNav/resources/HomeSprites.h"
    horse = shade(torrent().resize((190, 135), Image.LANCZOS).point(lambda v: 255 if v >= 110 else 0),
                  (233, 350), (288, 218), "left")
    body = [
        "#pragma once",
        "// 首页立绘：4bpp 索引色，每字节 2 像素（高 4 位在前），索引 0 = 透明。",
        "// 由 tools 里的 scripts/home_sprites.py 生成，换正式立绘时重跑脚本覆盖本文件。",
        "",
        to_c("TORRENT", horse, 288, 218, "灵马托雷特：灰白灵体，朝左，脚底落在 (288+128, 218+118)", PAL),
        "",
    ]
    dest.write_text("\n".join(body), encoding="utf-8")
    print(dest)


if __name__ == "__main__":
    main()
