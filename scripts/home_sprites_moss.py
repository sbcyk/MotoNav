#!/usr/bin/env python3
"""生成苔林夜骑首页素材：**两帧** 8bpp 索引图（灯灭 / 灯亮），466x466，屏上 1:1 直出。

和 `home_sprites.py`（艾尔登两态）一个思路：两帧共用一张调色板，且**光照区之外逐像素
完全相同**，所以连接状态切换时只有车灯那一片在变，背景一动不动。

灯亮帧的构造方式（和 voge_cu530_pixel_locked_pair_v2 那套一样）：
- 灯灭帧是母版，取参考图左联；
- 灯亮帧 = 灯灭帧，只把光照区整块换成右联的像素（光照区怎么圈见 `build_on`），其余一律
  保留灯灭帧的像素。

为什么不整联替换：参考图左右两联是两次生成的，右联整体比左联亮 2 个色阶，每条边还有
1px 相位差，直接换整张会让画面在切换瞬间整体闪一下。按区域替换、再裁回 LIT_RECT 之后，
矩形外的改动数为 0，切换绝对干净。

为什么不走 233 + 2x：参考图 884 宽，降到 466 还留得住原画的格块（"VOGE"、"NICE TO CU"
都读得出来）；降到 233 再放大 2 倍，字全糊成色块。固件也省掉那套 2x 重复写。

铭牌那行字单独重写：参考图上本来就是 "NICE TO CU"，但 AI 把字挤在一起、中间没留空格，
降到 466 之后每字只剩 3~4 像素宽，糊成一坨像乱码。这里在原位按 3x5 像素字重写一遍，
铭牌的大小、位置、边框、光晕都不动，只把旧字擦掉换新字。

素材来源：`assets/reference/home-moss-pair.png`（左右两联的横图，中间一条亮分隔线）

用法：python scripts/home_sprites_moss.py
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

S = 466                                     # 屏上直出边长，和 LCD 一致，不再放大
SRC = "assets/reference/home-moss-pair.png"

# 分隔线判定：画面中线附近，整列均值超过这个亮度就当成分隔线
DIVIDER_LUMA = 200
DIVIDER_SEARCH = 0.08                       # 只在中线 ±8% 宽度内找

# 光照区：把车头灯 + 前叉 + 光锥落到的护栏 + 地面反光 + 发动机铭牌一起圈进来。
# 这个矩形是"允许改动"的范围：替换的像素取「邻域平均提亮」的区域、膨胀 LIT_DILATE 像素，
# 再裁回矩形。圈大点不心疼，圈小了会把光锥切一半——换素材后先看脚本打印的"矩形外跳过"数量。
LIT_RECT = (220, 185, 466, 450)             # x0, y0, x1, y1（右/下开区间，466 坐标）
LIT_MIN_DELTA = 8                           # 算"真被照亮"的亮度差阈值，约半个 RGB565 色阶
LIT_BLUR_MIN = 6                            # 5x5 邻域平均也要提亮这么多，滤掉 1px 相位噪声
LIT_DILATE = 2                              # 光照区向外膨胀的像素数，把光晕尾巴包进去
LIGHT_COLORS = 80                           # 色板里专留给车灯/光锥的色位数

EXPECT_MIN_CHANGED = 0.01                   # 两帧差异下限：太低说明根本没找到灯
EXPECT_MAX_CHANGED = 0.15                   # 上限：太高说明把整联当光照替换进去了

# 发动机侧盖铭牌：旧字所在的那一块（466 坐标，含右/下边界）
PLATE = (244, 277, 280, 281)                # x0, y0, x1, y1：旧字实际占的像素范围
PLATE_BAND = (274, 284)                     # 铭牌亮带（上含下不含）：擦字时按列在这里取牌面底色
PLATE_TEXT = "NICE TO CU"
PLATE_GAP = 1                               # 字间距（像素）
PLATE_MIN_LUMA = 120                        # 旧字区平均亮度下限，低于它说明坐标量错了
PLATE_MIN_BASE = 40                         # 牌面底色亮度下限，低于它说明取到了车身而不是铭牌

# 3x5 像素字库，只收铭牌要用的字符。字宽不统一（I 和空格窄），排版按每个字形的实际宽度算。
# N 用 4 像素宽：3 像素宽的 N 只能靠一点点斜角暗示，看成 R/H 的概率很高。
PLATE_GLYPHS = {
    "N": ("#..#", "##.#", "#.##", "#..#", "#..#"),
    "I": ("#", "#", "#", "#", "#"),
    "C": (".##", "#..", "#..", "#..", ".##"),
    "E": ("###", "#..", "##.", "#..", "###"),
    "T": ("###", ".#.", ".#.", ".#.", ".#."),
    "O": (".#.", "#.#", "#.#", "#.#", ".#."),
    "U": ("#.#", "#.#", "#.#", "#.#", ".#."),
    " ": (".", ".", ".", ".", "."),
}


def luma(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def split_pair(im):
    """按中间的亮竖线把两联切开，两边裁成同样宽度，返回 (左, 右)。"""
    w, h = im.size
    px = im.load()
    mid, span = w // 2, int(w * DIVIDER_SEARCH)
    ys = range(0, h, 7)
    bright = [x for x in range(mid - span, mid + span)
              if sum(sum(px[x, y]) for y in ys) / (3 * len(ys)) > DIVIDER_LUMA]
    if not bright:
        raise SystemExit("没找到中间的分隔线：参考图不是左右两联？")
    x0, x1 = min(bright), max(bright) + 1
    left, right = im.crop((0, 0, x0, h)), im.crop((x1, 0, w, h))
    n = min(left.width, right.width)
    return left.crop((0, 0, n, h)), right.crop((right.width - n, 0, right.width, h))


def delta_map(off, lit):
    """逐像素亮度差（亮 - 暗），以及它的 5x5 邻域平均。"""
    lo = [luma(c) for c in off.getdata()]
    ln = [luma(c) for c in lit.getdata()]
    d = [b - a for a, b in zip(lo, ln)]
    shifted = Image.new("L", off.size)
    shifted.putdata([max(0, min(255, int(v + 128))) for v in d])
    blurred = shifted.filter(ImageFilter.BoxBlur(2)).getdata()
    return d, [v - 128 for v in blurred]


def build_on(off, lit):
    """灯亮帧 = 灯灭帧，只把光照区整块换成右联的像素。

    光照区按"邻域平均亮度提亮"圈（blur >= LIT_BLUR_MIN），再向外膨胀 LIT_DILATE 像素。
    不能按单像素阈值逐点替换：光锥内部有些像素只亮 4~7 个色阶，逐点判会留下没换的绿点，
    光锥看上去是一块一块的斑。整块替换之后边界落在光晕真正消失的地方，里面是连着的。
    """
    w, h = off.size
    d, blur = delta_map(off, lit)
    x0, y0, x1, y1 = LIT_RECT

    seed = Image.new("L", off.size, 0)
    seed.putdata([255 if (blur[i] >= LIT_BLUR_MIN and x0 <= i % w < x1
                          and y0 <= i // w < y1) else 0 for i in range(w * h)])
    # 膨胀会把边界推开 1~2 像素，和"矩形之外逐像素相同"的约定冲突，所以再裁回矩形
    rect_mask = Image.new("L", off.size, 0)
    rect_mask.paste(255, (x0, y0, x1, y1))
    mask = ImageChops.multiply(seed.filter(ImageFilter.MaxFilter(2 * LIT_DILATE + 1)), rect_mask)
    keep = mask.tobytes()

    src = lit.load()
    out = off.copy()
    px = out.load()
    outside = 0
    light = []                              # 真正被照亮那一批像素的颜色，量化时单独留色位
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if d[i] >= LIT_MIN_DELTA and blur[i] >= LIT_BLUR_MIN:
                if not (x0 <= x < x1 and y0 <= y < y1):
                    outside += 1
                    continue
                light.append(src[x, y])
            if keep[i]:
                px[x, y] = src[x, y]
    return out, outside, light


def plate_text_width(text, gap=PLATE_GAP):
    return sum(len(PLATE_GLYPHS[c][0]) for c in text) + gap * (len(text) - 1)


def redraw_plate(img):
    """把铭牌上那行糊字擦掉，原位重写成 PLATE_TEXT。

    字色取旧字里偏亮的那一档：灯灭帧是字白、灯亮帧是琥珀，两帧各自取各自的，不写死。
    擦字只擦旧字自己占的那几列，不碰铭牌两端——牌面两头是往车身弯下去的，按整段擦会把
    暗色涂到牌面上，留一个缺口。底色先全部算完、校验过再动图，免得报错时画面改了一半。
    """
    px = img.load()
    x0, y0, x1, y1 = PLATE
    rows = list(range(y0, y1 + 1))
    cols = list(range(x0, x1 + 1))

    old = sorted((px[x, y] for x in cols for y in rows), key=luma)
    if sum(luma(c) for c in old) / len(old) < PLATE_MIN_LUMA:
        raise SystemExit(f"铭牌 {PLATE} 那一带不够亮：旧字的坐标量错了？")
    color = old[int(len(old) * 0.9)]          # 偏亮那一档，避开零星的高光点

    tw = plate_text_width(PLATE_TEXT)
    if tw > len(cols):
        raise SystemExit(f"'{PLATE_TEXT}' 要 {tw} 像素宽，铭牌只有 {len(cols)} 像素")
    tx = x0 + (len(cols) - tw) // 2

    bases = {}
    for x in cols:
        bases[x] = min((px[x, y] for y in range(*PLATE_BAND)), key=luma)
        if luma(bases[x]) < PLATE_MIN_BASE:
            raise SystemExit(f"铭牌第 {x} 列牌面底色只有 {luma(bases[x]):.0f}：PLATE_BAND 量错了？")

    for x in cols:
        for y in rows:
            px[x, y] = bases[x]

    x = tx
    for ch in PLATE_TEXT:
        glyph = PLATE_GLYPHS[ch]
        for row, line in enumerate(glyph):
            for col, v in enumerate(line):
                if v == "#":
                    px[x + col, y0 + row] = color
        x += len(glyph[0]) + PLATE_GAP


def palette_of(img, n):
    """取 img 量化后实际用到的颜色（去重，按索引顺序）。"""
    q = img.quantize(colors=n, method=Image.Quantize.MEDIANCUT,
                     dither=Image.Dither.NONE)
    pal = list(q.getpalette() or [])
    pal += [0] * (768 - len(pal))
    return [(pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]) for i in sorted(set(q.tobytes()))]


def color_sample_image(colors):
    """把一堆颜色摊成一张图，专门喂给量化器（用来给光照色单独留色位）。"""
    w = 128
    rows = (len(colors) + w - 1) // w
    img = Image.new("RGB", (w, rows), (0, 0, 0))
    px = img.load()
    for i, c in enumerate(colors):
        px[i % w, i // w] = c
    return img


def build_palette(canvas, light_colors):
    """主色板 + 光照专用色板。光照只占几个百分点，整图量化会把暖色全挤掉——
    实测不单独留色位时，光锥会从琥珀色变成灰绿，灯心也发白。
    LIGHT_COLORS 个色位专门从"被照亮的那批像素"里取。"""
    if not light_colors:
        raise SystemExit("没有找到被照亮的像素：LIT_RECT / 阈值不对，先别出素材")
    warm = palette_of(color_sample_image(light_colors), LIGHT_COLORS)
    main = palette_of(canvas, 256 - LIGHT_COLORS)
    out, seen = [], set()
    for c in warm + main:                    # 暖色排前面，色号小、好排查
        if c in seen:
            continue
        seen.add(c)
        out.append(c)
    out = out[:256]
    while len(out) < 256:
        out.append((0, 0, 0))
    return out


def apply_palette(canvas, palette):
    """按给定色板重新映射索引（PIL 在 C 里做最近色匹配，不抖动）。"""
    p = Image.new("P", (1, 1))
    p.putpalette([v for c in palette for v in c])
    return canvas.quantize(palette=p, dither=Image.Dither.NONE)


def emit_pal(palette):
    out = ["static const uint16_t MOSS_PAL[256] = {"]
    for i in range(0, 256, 16):
        row = []
        for j in range(i, i + 16):
            r, g, b = palette[j]
            row.append(f"0x{((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3):04X}")
        out.append("  " + ",".join(row) + ",")
    out.append("};")
    return "\n".join(out)


def emit_idx(name, quant, x_off):
    """从联合量化的画布里挖出一帧的索引。"""
    data = quant.crop((x_off, 0, x_off + S, S)).tobytes()
    if len(data) != S * S:
        raise SystemExit(f"{name} 索引长度 {len(data)} 不等于 {S * S}")
    out = [f"static const uint8_t {name}[{len(data)}] = {{"]
    for i in range(0, len(data), 24):        # 每行 24 字节，和 home_sprites.py 一致
        out.append("  " + ",".join(f"0x{v:02X}" for v in data[i:i + 24]) + ",")
    out.append("};")
    return "\n".join(out)


def main():
    root = Path(__file__).resolve().parent.parent
    path = root / SRC
    if not path.exists():
        raise SystemExit(f"缺少参考图：{path}")

    im = Image.open(path).convert("RGB")
    if im.height > im.width:
        raise SystemExit(f"{path} 应该是左右两联的横图，当前 {im.size}")

    left, right = split_pair(im)
    off = left.resize((S, S), Image.BOX)
    lit = right.resize((S, S), Image.BOX)

    on, outside, light = build_on(off, lit)

    # 铭牌重写放在量化之前：两帧都写一遍，字色各自从旧字里取
    redraw_plate(off)
    redraw_plate(on)

    # 两帧真正的差异像素（重写铭牌之后重新算），只用来挡"没找到灯"和"整幅都在变"两种跑偏
    differ = sum(1 for a, b in zip(off.getdata(), on.getdata()) if a != b)
    ratio = differ / (S * S)
    if ratio < EXPECT_MIN_CHANGED:
        raise SystemExit(f"两帧只差 {ratio:.2%}：没找到灯，检查 LIT_RECT / 阈值")
    if ratio > EXPECT_MAX_CHANGED:
        raise SystemExit(f"两帧差 {ratio:.2%} 超过 {EXPECT_MAX_CHANGED:.0%}：阈值太低，整幅都在变")

    # 两帧拼一起量化：一张 256 色板给两帧共用，固件只存一份 MOSS_PAL
    canvas = Image.new("RGB", (S * 2, S))
    canvas.paste(off, (0, 0))
    canvas.paste(on, (S, 0))
    palette = build_palette(canvas, light)
    quant = apply_palette(canvas, palette)

    dest = root / "firmware/boards/175/MotoNav/resources/HomeSpritesMoss.h"
    body = [
        "#pragma once",
        f"// 苔林夜骑首页画面：两帧 8bpp 索引色，{S}x{S}，屏上 1:1 直出（不再放大）。",
        "// 由 scripts/home_sprites_moss.py 生成，别手改。",
        "//",
        "// 两帧共用一张调色板，且光照矩形之外逐像素相同：连接状态切换时只有车灯那一片在变，",
        "// 背景一动不动。灯亮帧是拿灯灭帧当母版、只替换确实变亮的像素得来的，不是另画一张。",
        "// 发动机铭牌那行 NICE TO CU 是脚本原位重写的（3x5 像素字），不是参考图原样。",
        f"#define MOSS_W {S}",
        f"#define MOSS_H {S}",
        f"// 两帧可能不同的范围：x {LIT_RECT[0]}~{LIT_RECT[2] - 1}、y {LIT_RECT[1]}~{LIT_RECT[3] - 1}",
        "//（车灯 + 光锥 + 发动机铭牌），别的像素逐字节相同",
        "",
        emit_pal(palette),
        "",
        emit_idx("MOSS_IDX_OFF", quant, 0),
        "",
        emit_idx("MOSS_IDX_ON", quant, S),
    ]
    dest.write_text("\n".join(body) + "\n", encoding="utf-8", newline="\n")

    dump = Path(__file__).resolve().parent / "preview"
    dump.mkdir(exist_ok=True)
    rgb = quant.convert("RGB")
    rgb.crop((0, 0, S, S)).save(dump / "moss_base_off.png")
    rgb.crop((S, 0, S * 2, S)).save(dump / "moss_base_on.png")

    # 量化会把相近的颜色并成一个索引，所以最终阵列的差异比上面那个数还小一点，
    # 这个才是"屏上真正变了多少像素"
    q_off = quant.crop((0, 0, S, S)).tobytes()
    q_on = quant.crop((S, 0, S * 2, S)).tobytes()
    q_differ = sum(1 for a, b in zip(q_off, q_on) if a != b)

    print(dest, dest.stat().st_size // 1024, "KB")
    print(f"两帧差异 {q_differ} 索引（{q_differ / (S * S):.2%}）；"
          f"光照矩形外跳过 {outside} 像素（相位噪声，不动）")
    print(f"铭牌重写 {PLATE_TEXT!r}：字宽 {plate_text_width(PLATE_TEXT)} 像素")
    print(f"索引 {S * S} 字节/帧，调色板 256 色共用（{LIGHT_COLORS} 位留给光照）")


if __name__ == "__main__":
    main()
