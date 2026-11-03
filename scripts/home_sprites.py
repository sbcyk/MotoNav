#!/usr/bin/env python3
"""生成首页素材：黄昏赐福两个画面（未连接 / 已连接），8bpp 索引色。

素材来源 `pic/home_reference.png`（参考图，不进仓库；换机器要自己放回去）：
- 上格只有褪色者坐在赐福旁，取它做「未连接」；
- 下格里托雷特站在他身后，取它做「已连接」。

参考图是 3:1 横幅、圆屏是 1:1，方屏只能取其中一块，所以两格各取一块
512 宽、整格高的方形区域（上格 512x504、下格 512x512），缩放到 233x233：
缩放比横向都是 2.20 倍、纵向 2.16 / 2.20 倍，差 1.6%，看不出形变。
上格的取景刻意避开了黄金树：它在画面最右侧，要把它拉进来就得缩小整幅，
人物会比下格小一圈，切换时像镜头突然推近。

两张图都缩到 233x233 存 8bpp，固件按 2x 最近邻放大到 466x466 显示，
看上去就是 2x2 的大像素，和参考图的像素颗粒一致。
跑完顺带把成品写到 pic/scene_off.png、pic/scene_on.png，方便直接看。
用法：python scripts/home_sprites.py
"""
from pathlib import Path
from PIL import Image, ImageEnhance

S = 233                       # 底图边长
OUT = 466                     # 显示边长（固件按 2 倍放大）

# 两格原图机位不同（上格远景、下格近景），所以统一取同样大小的方形原图，
# 缩放比一致，切换状态时人物大小不会跳。取景都把人物、赐福火放在画面中间偏下。
TOP_CROP = (300, 0, 812, 504)         # 上格 512x504：褪色者独坐（废墟 / 远山 / 王城一角）
BOT_CROP = (170, 0, 682, 512)         # 下格 512x512：托雷特站在他身后


def grade(img):
    """小屏在强光下容易糊成一团，抬一点亮度与饱和度。"""
    img = ImageEnhance.Brightness(img).enhance(1.12)
    img = ImageEnhance.Contrast(img).enhance(1.06)
    return ImageEnhance.Color(img).enhance(1.10)


def beam_xy(img):
    """找赐福火最亮的暖色像素（画面下半部分），固件的光尘与闪光以它为锚点。"""
    px = img.load()
    best = (-1, 0, 0)
    for y in range(int(S * 0.55), S):
        for x in range(S):
            r, g, b = px[x, y]
            v = r * 2 + g - b * 2
            if v > best[0]:
                best = (v, x, y)
    return best[1], best[2]


def quantize(img):
    """8bpp 索引色 + 抖动，256 色调色板足够还原这种画面。"""
    return img.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)


def emit8(name, img, comment):
    w, h = img.size
    pal = list(img.getpalette() or [])
    pal += [0] * (768 - len(pal))                 # 量化结果一定带 256 色板，这里只做兜底
    px = img.load()
    data = bytearray()
    for y in range(h):
        for x in range(w):
            data.append(px[x, y])
    lines = [f"// {comment}"]
    lines.append(f"#define {name}_W {w}")
    lines.append(f"#define {name}_H {h}")
    lines.append(f"#define {name}_NPAL 256")
    pal565 = []
    for i in range(256):
        r, g, b = pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]
        pal565.append(f"0x{((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3):04X}")
    lines.append(f"static const uint16_t {name}_PAL[256] = {{")
    for i in range(0, 256, 16):
        lines.append("  " + ",".join(pal565[i:i + 16]) + ",")
    lines.append("};")
    lines.append(f"static const uint8_t {name}_BITS[{len(data)}] = {{")
    for i in range(0, len(data), 24):
        lines.append("  " + ",".join(f"0x{v:02X}" for v in data[i:i + 24]) + ",")
    lines.append("};")
    return "\n".join(lines)


def main():
    root = Path(__file__).resolve().parent.parent
    ref = root / "pic/home_reference.png"
    if not ref.exists():
        raise SystemExit(f"缺少参考图：{ref}")
    im = Image.open(ref).convert("RGB")
    width, height = im.size                       # 1536x1024：上下两格，中间约 8 行分隔线
    half = height // 2
    top = im.crop((0, 0, width, half - 8))
    bot = im.crop((0, half, width, height))

    off = quantize(grade(top.crop(TOP_CROP).resize((S, S), Image.LANCZOS)))
    on = quantize(grade(bot.crop(BOT_CROP).resize((S, S), Image.LANCZOS)))
    bx, by = beam_xy(off.convert("RGB"))
    bx2, by2 = beam_xy(on.convert("RGB"))

    dest = root / "firmware/boards/175/MotoNav/resources/HomeSprites.h"
    body = [
        "#pragma once",
        "// 首页画面：8bpp 索引色 + 256 色板，233x233，固件按 2x 放大到 466x466。",
        "// 由 scripts/home_sprites.py 从 pic/home_reference.png 生成，换参考图后重跑。",
        "",
        f"#define HOME_BEAM_OFF_X {bx}",
        f"#define HOME_BEAM_OFF_Y {by}",
        f"#define HOME_BEAM_ON_X {bx2}",
        f"#define HOME_BEAM_ON_Y {by2}",
        "",
        emit8("SCENE_OFF", off, "未连接：褪色者独坐赐福旁，远处王城与远山"),
        "",
        emit8("SCENE_ON", on, "已连接：托雷特站在褪色者身后，同在赐福旁"),
        "",
    ]
    dest.write_text("\n".join(body), encoding="utf-8")
    on.resize((OUT, OUT), Image.NEAREST).save("pic/scene_on.png")
    off.convert("RGB").resize((OUT, OUT), Image.NEAREST).save("pic/scene_off.png")
    print(dest, dest.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
