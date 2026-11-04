#!/usr/bin/env python3
"""生成首页素材：黄昏赐福两个画面（未连接 / 已连接），8bpp 索引色 233x233。

两张参考图都在仓库里（`assets/reference/`），拉下来就能重跑：
- `home-dual-pose.png` 1536x1024「双姿态」图，上下两格。只用**上格**——褪色者独坐
  赐福旁、没有马。下格是同一场景坐着带马的版本，本脚本不用。
- `home-standing.png` 1536x1024 一整张「紧凑」构图：站着牵马的褪色者、赐福火、
  王城、黄金树全在同一帧里。

两张图的取景框宽度必须让**主体看上去一样大**，否则切换时像镜头推近：
- 双姿态图每格只有 504 px 高，圆屏是 1:1，方形取景的宽度被格子高度卡在 504
  （这里用 512，横向差 1.6%，看不出形变）。
- 紧凑图裁 683x683。683 是量出来的：两图火焰列的高度按取景宽度反比缩放，
  512 那张是 129 px、683 这张也是 129 px，一比一。**不要为了把王城框进来把这里
  放大到 1024**——那样已连接那张会整体缩到 67%，切换时看得见镜头拉远。
- 代价：放大到 1024 才能看见的王城、以及 x 1150~1500 的黄金树，都不在画面里。

两张的对齐：取景框各自选定，让赐福火落在同一个屏幕位置（233 尺度下
OFF x=151 / ON 自动求到 155，差 4 源像素 = 8 显示像素），切换时人和火不跳。

用法：python scripts/home_sprites.py
"""
from pathlib import Path
from PIL import Image, ImageEnhance

S = 233                       # 底图边长
OUT = 466                     # 显示边长（固件按 2 倍放大）

# ---- 未连接：双姿态图的上格（褪色者独坐，无马，无王城）----
OFF_REF = "assets/reference/home-dual-pose.png"
OFF_PANEL = (0, 0, 1536, 504)         # 上格（下格与中间分隔线都不要）
OFF_CROP = (230, 0, 742, 504)         # 512x504，人物与火居中，左侧留一点废墟立柱
OFF_BASE_Y = 180

# ---- 已连接：紧凑图（站着牵马）----
ON_REF = "assets/reference/home-standing.png"
ON_CROP = (221, 162, 904, 845)        # 683x683，主体与未连接那张同比例，且火落在同一位置
ON_BASE_Y = 180

WARM = 400                    # 暖色高亮判定：r*2 + g - 2b
MIN_ROWS = 30                 # 火苗至少要有这么高，否则认为没找到


def grade(img):
    """小屏在强光下容易糊成一团，抬一点亮度、对比与饱和度。"""
    img = ImageEnhance.Brightness(img).enhance(1.12)
    img = ImageEnhance.Contrast(img).enhance(1.06)
    return ImageEnhance.Color(img).enhance(1.10)


def beam_xy(img, base_y):
    """找赐福火的锚点，固件的光尘与闪光以它为锚点。

    x 用“暖色高亮行数最多的那一列”定：火焰是画面里唯一一条竖直长条，能占掉上百行，
    别的亮东西（碎金花丛、天空云底、量化抖动的极端色噪点）只有个位数。不能用单点
    最亮——野花和噪点都比火根亮，旧版就是这么跑偏的（落在 y=128，那是火焰中段）。

    y 由调用方给常数而不是自动找：火焰内部有暗带，地面上那圈法阵也又亮又暖，
    “最下面一个高亮点”会一路探到法阵底边。基线跟着取景框走，改取景就要重新量。

    传进来的必须是 grade 之后、quantize 之前的图。
    """
    px = img.load()

    def warm(x, y):
        r, g, b = px[x, y]
        return r * 2 + g - 2 * b

    best_x, best_rows = -1, 0
    for x in range(S):
        rows = sum(1 for y in range(int(S * 0.3), S) if warm(x, y) > WARM)
        # 同分（火焰有好几列一样高）就看基线那一行谁更亮，否则会挑到火焰边缘的暗列
        if rows > best_rows or (rows == best_rows and rows and warm(x, base_y) > warm(best_x, base_y)):
            best_rows, best_x = rows, x
    if best_rows < MIN_ROWS:
        raise SystemExit(f"没找到赐福火：最亮的一列只有 {best_rows} 行高亮（至少要 {MIN_ROWS} 行）")
    r, g, b = px[best_x, base_y]
    if warm(best_x, base_y) < 250:
        raise SystemExit(
            f"火根基线对不上：x={best_x}、y={base_y} 处不亮（{(r, g, b)}）。"
            f"换过参考图或改过取景框的话，请重新量基线。")
    return best_x, base_y


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


def load(path, crop, panel=None):
    if not path.exists():
        raise SystemExit(f"缺少参考图：{path}")
    im = Image.open(path).convert("RGB")
    if panel:
        if panel[2] > im.width or panel[3] > im.height:
            raise SystemExit(f"{path} 尺寸是 {im.size}，装不下取景块 {panel}")
        im = im.crop(panel)
    if crop[2] > im.width or crop[3] > im.height:
        raise SystemExit(f"{path} 尺寸是 {im.size}，装不下取景框 {crop}")
    return grade(im.crop(crop).resize((S, S), Image.LANCZOS))


def main():
    root = Path(__file__).resolve().parent.parent
    off_src = load(root / OFF_REF, OFF_CROP, OFF_PANEL)
    on_src = load(root / ON_REF, ON_CROP)
    bx, by = beam_xy(off_src, OFF_BASE_Y)          # 锚点在量化前求，抖动噪点不参与
    bx2, by2 = beam_xy(on_src, ON_BASE_Y)
    off, on = quantize(off_src), quantize(on_src)

    dest = root / "firmware/boards/175/MotoNav/resources/HomeSprites.h"
    body = [
        "#pragma once",
        "// 首页画面：8bpp 索引色 + 256 色板，233x233，固件按 2x 放大到 466x466。",
        "// 由 scripts/home_sprites.py 生成：未连接取自 assets/reference/home-dual-pose.png",
        "// 的上格（人独坐），已连接取自 assets/reference/home-standing.png（人站着牵马）。",
        "",
        f"#define HOME_BEAM_OFF_X {bx}",
        f"#define HOME_BEAM_OFF_Y {by}",
        f"#define HOME_BEAM_ON_X {bx2}",
        f"#define HOME_BEAM_ON_Y {by2}",
        "",
        emit8("SCENE_OFF", off, "未连接：褪色者独坐赐福旁，远处废墟与远山"),
        "",
        emit8("SCENE_ON", on, "已连接：托雷特与站着牵缰的褪色者"),
        "",
    ]
    dest.write_text("\n".join(body), encoding="utf-8")
    dump = Path(__file__).resolve().parent / "preview"       # 成品导出，和别的预览图放一起（不进仓库）
    dump.mkdir(exist_ok=True)
    off.convert("RGB").resize((OUT, OUT), Image.NEAREST).save(dump / "scene_off.png")
    on.convert("RGB").resize((OUT, OUT), Image.NEAREST).save(dump / "scene_on.png")
    print(dest, dest.stat().st_size // 1024, "KB")
    print(f"锚点 OFF=({bx},{by})  ON=({bx2},{by2})")


if __name__ == "__main__":
    main()
