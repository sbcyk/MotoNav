#!/usr/bin/env python3
"""生成首页素材：黄昏赐福两态（未连接独坐 / 已连接站着牵马），共用一张 256 色调色板。

素材来源都在 `assets/reference/`：
- `home-standing.png`       母版：站着牵马的褪色者、赐福火、峡谷、王城、黄金树。
                            v2.2 起它同时是两态的唯一背景来源——连接态直接用它。
- `home-standing-empty.png` 同一张图把人和马抠掉后由 AI 补全的空场景（草坡、岩壁、天空）。
- `home-seated.png`         单独生成的坐姿褪色者，平涂底色，色键抠图后贴进空场景。

**核心约束：两态只有“人和马”那一块不同，其余像素逐像素一致。**
做法：母版裁到 233 后，只把“人马蒙版”里的像素换成空场景＋坐姿人，蒙版外一律复制母版；
最后两张图用同一张调色板、同一个 Bayer 抖动场量化——偏移只跟坐标有关，相同 RGB 必得
相同索引，固件里才能用“索引相等”判断背景、只重绘那一小块。

用法：python scripts/home_sprites.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

S = 233                                     # 底图边长
OUT = 466                                   # 显示边长（固件按 2 倍放大）

# ---- 母版取景：683x683，主体与赐福火的位置都由它定死 ----
MASTER_REF = "assets/reference/home-standing.png"
EMPTY_REF = "assets/reference/home-standing-empty.png"
SEATED_REF = "assets/reference/home-seated.png"
CROP = (221, 162, 904, 845)

# ---- 人马蒙版：母版里人和马的外轮廓，多盖一点没关系，少盖会漏出白马的边 ----
MASK_HORSE = [(0, 183), (0, 52), (28, 50), (34, 44), (46, 40), (52, 31),
              (58, 35), (68, 30), (78, 37), (86, 46), (87, 183)]
MASK_MAN = [(78, 183), (78, 120), (79, 64), (86, 55), (96, 50), (107, 52),
            (114, 57), (118, 65), (122, 78), (122, 110), (128, 127), (125, 183)]
MASK_GROW = 4                               # 膨胀半径：宁可多盖，别露白边
MASK_XMAX = 128                             # 右边界：再往右是赐福火光晕，不能动
MASK_YMIN = 24                              # 上边界：马角顶端，再往上就是天空
MASK_YMAX = 183                             # 下边界：地面线，以下的草坡必须留给母版

# ---- 坐姿人：目标高度、脚底基线、水平中心 ----
SEAT_H = 70
SEAT_FLOOR = 183
SEAT_CX = 104

# ---- 固件要用的两块矩形（源像素坐标）：起身扫描和马的粒子都只在这里动 ----
MAN_BOX = (74, 44, 134, 184)
HORSE_BOX = (0, 24, 92, 184)
N_PTS = 150                                 # 马身上的粒子落点数量

# ---- 赐福光柱：两态柱高不同（v2.3）----
# 柱子是画进母版的死像素，整块抹掉会在天上留一块灰。只动"柱芯"：竖直连续 ≥BEAM_THICK 的
# 暖色块，把它按**本行**的光晕色替换掉，混合量随高度推到 1——芯就淡进自己的光晕里，
# 读起来是光散掉了，而不是被挖走。光环那种 1~3 px 的细线不满足"厚"，原样保留。
# 底不能用二维扩散估：洞几乎占满柱带时，扩散会从带顶上方的冷色天空取色，填出来是灰的。
BEAM_BAND = (138, 173, 18)                  # 柱带：x0, x1, 顶（源像素）；带内允许两态不同
BEAM_FADE_OFF = (110, 84)                   # 坐火（高）：84 以上芯已散尽，110 以下原样
BEAM_FADE_ON = (140, 118)                   # 未坐火（矮）：柱顶再低一截，两态差 34 px
BEAM_EDGE = 6                               # 估本行光晕色时，柱带左右各取几列
BEAM_LIGHT = (22, 80)                       # 判定"光"的下限：r-b > 22 且 r > 80
BEAM_THICK = 6                              # 竖直连续这么多像素才算"厚"（柱芯/光锥）；细线是光环，留着


def smoothstep(a, b, v):
    t = (v - a) / float(b - a)
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return t * t * (3.0 - 2.0 * t)


def beam_cut(img, y_full, y_top):
    """把柱芯从 y_top 往上淡进本行光晕，y_full 以下原样。

    只动"厚"的东西：竖直连续 BEAM_THICK 以上的暖色块（柱芯和光锥），
    光环那种 1~3 px 的细线一律留着——光环是赐福的形态，抹掉就不像赐福了。
    每行取柱带左右两侧的中位色当"这一行没有柱芯时该有的亮度"，横向铺平，
    再乘 smoothstep：y_full 处不动、y_top 处芯完全让位给光晕。
    """
    out = img.copy()
    p = out.load()
    x0, x1, y0 = BEAM_BAND
    h, w = y_full - y0, x1 - x0
    if h <= 0 or w <= 0:
        return out

    def light(c):
        return c[0] - c[2] > BEAM_LIGHT[0] and c[0] > BEAM_LIGHT[1]

    core = [[0.0] * w for _ in range(h)]
    for i in range(w):                                    # 逐列找竖直厚块
        j = 0
        while j < h:
            if not light(p[x0 + i, y0 + j]):
                j += 1
                continue
            k = j
            while k < h and light(p[x0 + i, y0 + k]):
                k += 1
            if k - j >= BEAM_THICK:                       # 细线（光环、碎点）不动
                for jj in range(j, k):
                    core[jj][i] = 1.0
            j = k
    if not any(any(r) for r in core):
        return out

    # 每行的光晕底色：左右各取 BEAM_EDGE 列的中位数（中位数不会被残留的芯带跑），
    # 再竖向 5 行平滑，免得逐行的颗粒在柱带里连成横纹。
    rows = []
    for j in range(h):
        y = y0 + j
        cols = [p[x, y] for x in range(x0, x0 + BEAM_EDGE)] + \
               [p[x, y] for x in range(x1 - BEAM_EDGE, x1)]
        rows.append([sorted(c[i] for c in cols)[len(cols) // 2] for i in range(3)])
    halo = []
    for j in range(h):
        acc = [0.0, 0.0, 0.0]
        n = 0
        for k in range(max(0, j - 2), min(h, j + 3)):
            for i in range(3):
                acc[i] += rows[k][i]
            n += 1
        halo.append([acc[i] / n for i in range(3)])

    # 芯的边缘半透明：3x3 均值，免得柱芯边界一步跳出硬边
    soft = [[0.0] * w for _ in range(h)]
    for j in range(h):
        for i in range(w):
            acc = 0.0
            n = 0
            for dj in (-1, 0, 1):
                for di in (-1, 0, 1):
                    jj, ii = j + dj, i + di
                    if 0 <= jj < h and 0 <= ii < w:
                        acc += core[jj][ii]
                        n += 1
            soft[j][i] = acc / n

    for j in range(h):
        y = y0 + j
        a = 1.0 - smoothstep(y_top, y_full, y)           # y_full 不动，y_top 全让位
        if a <= 0:
            continue
        f = halo[j]
        for i in range(w):
            m = soft[j][i] * a
            if m <= 0.004:
                continue
            o = p[x0 + i, y]
            p[x0 + i, y] = (clamp(o[0] + (f[0] - o[0]) * m),
                            clamp(o[1] + (f[1] - o[1]) * m),
                            clamp(o[2] + (f[2] - o[2]) * m))
    return out


# 有序抖动而不是 Floyd-Steinberg：Bayer 的偏移只跟坐标有关，两张图同一坐标同色
# 必得同一个索引，背景才可能逐像素相等。FS 依赖误差扩散，位置一变结果就变。
BAYER4 = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
DITHER_AMP = 9.0                            # 抖动幅度（0~255），约一个 RGB565 色阶


def clamp(v):
    return 0 if v < 0 else (255 if v > 255 else int(v))


def grade(img):
    """小屏在强光下容易糊成一团，抬一点亮度、对比与饱和度。"""
    img = ImageEnhance.Brightness(img).enhance(1.12)
    img = ImageEnhance.Contrast(img).enhance(1.06)
    return ImageEnhance.Color(img).enhance(1.10)


def load233(path, crop=None):
    if not path.exists():
        raise SystemExit(f"缺少参考图：{path}")
    im = Image.open(path).convert("RGB")
    if crop:
        if crop[2] > im.width or crop[3] > im.height:
            raise SystemExit(f"{path} 尺寸是 {im.size}，装不下取景框 {crop}")
        im = im.crop(crop)
    return grade(im.resize((S, S), Image.LANCZOS))


def cut_seated(path):
    """把坐姿人从平涂底色里抠出来，返回带 alpha 的 RGBA。"""
    if not path.exists():
        raise SystemExit(f"缺少参考图：{path}")
    src = Image.open(path).convert("RGB")
    w, h = src.size
    # 底色取四角中位，生成图底色很均匀
    corners = [src.getpixel(p) for p in ((4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5))]
    bg = tuple(sorted(c[i] for c in corners)[2] for i in range(3))
    alpha = Image.new("L", (w, h), 0)
    ap = alpha.load()
    sp = src.load()
    for y in range(h):
        for x in range(w):
            r, g, b = sp[x, y]
            d = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
            ap[x, y] = 0 if d <= 8 else (255 if d >= 30 else int((d - 8) * 255 / 22))
    alpha = alpha.filter(ImageFilter.MedianFilter(3))
    src.putalpha(alpha)
    box = alpha.point(lambda v: 255 if v > 60 else 0).getbbox()
    if not box:
        raise SystemExit("坐姿人抠图失败：整张都被判成底色")
    # 生成的图底部有一片涂抹阴影，占 bbox 高度的下 8%，连同水印一起切掉
    trim = int((box[3] - box[1]) * 0.08)
    box = (box[0], box[1], box[2], box[3] - trim)
    return src.crop(box)


def build_masks():
    mk = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mk)
    d.polygon(MASK_HORSE, fill=255)
    d.polygon(MASK_MAN, fill=255)
    mk = mk.filter(ImageFilter.MaxFilter(MASK_GROW * 2 + 1))
    mp = mk.load()
    for y in range(S):
        for x in range(S):
            # 上下越出地面线和马角的地方要收回来：那些像素必须留给母版，
            # 否则断开态那片草地会换成 AI 补的版本，站着时和周围接不上。
            if x > MASK_XMAX or y < MASK_YMIN or y > MASK_YMAX:
                mp[x, y] = 0
    return mk


def build_off(master, empty, seated, mask):
    """空场景＋坐姿人，蒙版外严格复制母版。"""
    off = master.copy()
    off.paste(empty, (0, 0), mask)                       # 只取蒙版内的补全结果
    mk = mask.load()
    mp, op = master.load(), off.load()
    for y in range(S):                                   # 蒙版外逐像素回填母版
        for x in range(S):
            if mk[x, y] < 128:
                op[x, y] = mp[x, y]

    h = SEAT_H
    w = round(seated.width * h / seated.height)
    sit = seated.resize((w, h), Image.LANCZOS)
    al = sit.split()[3]
    ap = al.load()
    for y in range(h - 6, h):                            # 脚底淡出，融进草地
        f = (h - 1 - y) / 6.0
        for x in range(w):
            ap[x, y] = int(ap[x, y] * f)
    sit.putalpha(al)
    off.paste(sit, (SEAT_CX - w // 2, SEAT_FLOOR - h), sit)

    op = off.load()                                      # 人可能压出蒙版一点，再回填一次
    for y in range(S):
        for x in range(S):
            if mk[x, y] < 128:
                op[x, y] = mp[x, y]
    return off


def bayer(img):
    out = img.copy()
    p = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = p[x, y]
            d = (BAYER4[y & 3][x & 3] / 16.0 - 0.5) * DITHER_AMP
            p[x, y] = (clamp(r + d), clamp(g + d), clamp(b + d))
    return out


def shared_quantize(off, on):
    """两张图并在一起求一张调色板，再各自按同一张调色板映射。"""
    merged = Image.new("RGB", (S, S * 2))
    merged.paste(bayer(off), (0, 0))
    merged.paste(bayer(on), (0, S))
    pal = merged.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.NONE)
    q_off = bayer(off).quantize(palette=pal, dither=Image.NONE)
    q_on = bayer(on).quantize(palette=pal, dither=Image.NONE)
    return pal, q_off, q_on


def emit(name, img, comment):
    w, h = img.size
    px = img.load()
    data = bytearray()
    for y in range(h):
        for x in range(w):
            data.append(px[x, y])
    out = [f"// {comment}", f"static const uint8_t {name}[{len(data)}] = {{"]
    for i in range(0, len(data), 24):
        out.append("  " + ",".join(f"0x{v:02X}" for v in data[i:i + 24]) + ",")
    out.append("};")
    return "\n".join(out)


def emit_pal(pal_img):
    raw = list(pal_img.getpalette() or [])
    raw += [0] * (768 - len(raw))
    out = ["static const uint16_t SCENE_PAL[256] = {"]
    for i in range(0, 256, 16):
        row = []
        for j in range(i, i + 16):
            r, g, b = raw[j * 3], raw[j * 3 + 1], raw[j * 3 + 2]
            row.append(f"0x{((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3):04X}")
        out.append("  " + ",".join(row) + ",")
    out.append("};")
    return "\n".join(out)


def horse_points(off_img, on_img, n):
    """马身上均匀撒点，粒子从这些点聚拢/散开。只在“两图不同且在马矩形内”的地方取。"""
    op, np_ = off_img.load(), on_img.load()
    cand = []
    for y in range(HORSE_BOX[1], HORSE_BOX[3]):
        for x in range(HORSE_BOX[0], HORSE_BOX[2]):
            if op[x, y] != np_[x, y]:
                cand.append((x, y))
    if len(cand) < n:
        raise SystemExit(f"马身上只有 {len(cand)} 个可用点，少于 {n}")
    step = len(cand) / n
    return [cand[int(i * step)] for i in range(n)]


def beam_xy(img, base_y):
    """赐福火锚点：暖色高亮行数最多的那一列。"""
    px = img.load()

    def warm(x, y):
        r, g, b = px[x, y]
        return r * 2 + g - 2 * b

    best_x, best_rows = -1, 0
    for x in range(S):
        rows = sum(1 for y in range(int(S * 0.3), S) if warm(x, y) > 400)
        if rows > best_rows or (rows == best_rows and rows and warm(x, base_y) > warm(best_x, base_y)):
            best_rows, best_x = rows, x
    if best_rows < 30:
        raise SystemExit(f"没找到赐福火：最亮的一列只有 {best_rows} 行高亮")
    return best_x, base_y


def main():
    root = Path(__file__).resolve().parent.parent
    master = load233(root / MASTER_REF, CROP)
    empty = load233(root / EMPTY_REF, CROP)
    seated = cut_seated(root / SEATED_REF)
    mask = build_masks()
    off = build_off(master, empty, seated, mask)
    on = master
    beam_y1 = max(BEAM_FADE_OFF[0], BEAM_FADE_ON[0])      # 两态改动都落在 [y0, beam_y1)
    off = beam_cut(off, *BEAM_FADE_OFF)                   # v2.3 坐火：柱子最高
    on = beam_cut(on, *BEAM_FADE_ON)                      # v2.3 未坐火：再短一截

    bx, by = beam_xy(on, 180)
    pts = horse_points(off, on, N_PTS)

    pal, q_off, q_on = shared_quantize(off, on)

    # 背景必须真的对得上：两只图在人马矩形和柱带之外，同位置索引必须相等
    a, b = q_off.load(), q_on.load()
    bad = []
    for y in range(S):
        for x in range(S):
            if a[x, y] != b[x, y]:
                inside = (HORSE_BOX[0] <= x < HORSE_BOX[2] and HORSE_BOX[1] <= y < HORSE_BOX[3]) or \
                         (MAN_BOX[0] <= x < MAN_BOX[2] and MAN_BOX[1] <= y < MAN_BOX[3]) or \
                         (BEAM_BAND[0] <= x < BEAM_BAND[1] and BEAM_BAND[2] <= y < beam_y1)
                if not inside:
                    bad.append((x, y))
    if bad:
        head = " ".join(f"({x},{y})" for x, y in bad[:8])
        raise SystemExit(f"背景没对齐：人马矩形与柱带之外有 {len(bad)} 个像素两态不同：{head}")


    dest = root / "firmware/boards/175/MotoNav/resources/HomeSprites.h"
    body = [
        "#pragma once",
        "// 首页画面：8bpp 索引色，233x233，固件按 2x 放大到 466x466。",
        "// 由 scripts/home_sprites.py 生成：两态共用一张调色板，且人马矩形之外逐像素相同，",
        "// 所以状态切换时只重绘人和马那一块，背景一动不动。",
        f"#define HOME_BEAM_X {bx}",
        f"#define HOME_BEAM_Y {by}",
        "// 赐福光柱带：柱高按状态不同（坐火高、未坐火矮），切换时这一块也要按状态重绘",
        f"#define HOME_BEAM_X0 {BEAM_BAND[0]}",
        f"#define HOME_BEAM_X1 {BEAM_BAND[1]}",
        f"#define HOME_BEAM_Y0 {BEAM_BAND[2]}",
        f"#define HOME_BEAM_Y1 {beam_y1}",
        "",
        "// 起身：人所在矩形，纵向扫描从 HOME_MAN_Y1 扫到 HOME_MAN_Y0",
        f"#define HOME_MAN_X0 {MAN_BOX[0]}",
        f"#define HOME_MAN_X1 {MAN_BOX[2]}",
        f"#define HOME_MAN_Y0 {MAN_BOX[1]}",
        f"#define HOME_MAN_Y1 {MAN_BOX[3]}",
        "// 马：粒子散开和显形只在这个矩形里",
        f"#define HOME_HRS_X0 {HORSE_BOX[0]}",
        f"#define HOME_HRS_X1 {HORSE_BOX[2]}",
        f"#define HOME_HRS_Y0 {HORSE_BOX[1]}",
        f"#define HOME_HRS_Y1 {HORSE_BOX[3]}",
        f"#define HOME_PTS_N {N_PTS}",
        f"#define SCENE_W {S}",
        f"#define SCENE_H {S}",
        "",
        emit_pal(pal),
        "",
        emit("SCENE_OFF_BITS", q_off, "未连接：褪色者独坐赐福旁，托雷特不在"),
        "",
        emit("SCENE_ON_BITS", q_on, "已连接：托雷特现身，褪色者起身牵缰"),
        "",
        "// 马身上的粒子落点（x,y 交替），粒子从这里聚拢成形、也从这里散开",
        f"static const uint8_t HOME_PTS[{len(pts) * 2}] = {{",
    ]
    flat = [str(v) for p in pts for v in p]
    for i in range(0, len(flat), 24):
        body.append("  " + ",".join(flat[i:i + 24]) + ",")
    body.append("};")
    dest.write_text("\n".join(body) + "\n", encoding="utf-8", newline="\n")

    dump = Path(__file__).resolve().parent / "preview"
    dump.mkdir(exist_ok=True)
    q_off.convert("RGB").resize((OUT, OUT), Image.NEAREST).save(dump / "scene_off.png")
    q_on.convert("RGB").resize((OUT, OUT), Image.NEAREST).save(dump / "scene_on.png")
    print(dest, dest.stat().st_size // 1024, "KB")
    print(f"赐福火锚点 ({bx},{by})  粒子落点 {len(pts)}  人马矩形外失配 0 像素")


if __name__ == "__main__":
    main()
