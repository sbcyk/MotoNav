#!/usr/bin/env python3
"""生成首页素材：黄昏赐福两态（未连接独坐 / 已连接起身牵马），共用一张 256 色调色板。

素材来源都在 `assets/reference/`：
- `home-v3-standing.png` 已连接态：站着牵马，黄金树横跨顶部、王城带拱桥与纵深。
- `home-v3-seated.png`   未连接态：同源生成，只把人改成独坐、马去掉，其余构图不动。

**核心约束：人马矩形与赐福柱带之外，两态逐像素一致。**
做法：以母版为底，只把这两块的像素换成另一张图的（边缘高斯羽化），区外一律复制母版；
最后两张图用同一张调色板、同一个 Bayer 抖动场量化——偏移只跟坐标有关，相同 RGB 必得
相同索引，固件里才能用“索引相等”判断背景、只重绘那一小块。

用法：python scripts/home_sprites.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

S = 233                                     # 底图边长
OUT = 466                                   # 显示边长（固件按 2 倍放大）

# ---- 母版取景：1024x1024 整张就是圆，取到圆的视觉边界 984 ----
# v3 换了新母版：黄金树在顶、王城横贯中景、人马在左下、赐福在中下，
# 上一版那张人马占掉半屏、树只露一角，怎么调都腾不出信息位。
MASTER_REF = "assets/reference/home-v3-standing.png"
ALT_REF = "assets/reference/home-v3-seated.png"     # 同源生成的"独坐、无马"
CROP = (20, 20, 1004, 1004)

# ---- 人马替换区（源像素坐标）：两态只有这一块不同 ----
# 不再抠图贴人。两张图同源生成，坐姿的位置、光照、草纹都对得上，
# 直接整块替换比"抠出人再贴进去"少一道接缝；边缘高斯羽化，草纹不会硬接。
SWAP_BOX = (15, 112, 99, 194)
SWAP_FEATHER = 3

# ---- 固件要用的两块矩形（源像素坐标）：起身扫描和马的粒子都只在这里动 ----
MAN_BOX = (15, 112, 99, 194)                # 人：站姿与坐姿位置的并集
HORSE_BOX = (17, 114, 78, 165)              # 马：站姿有，坐姿是草地
N_PTS = 150                                 # 马身上的粒子落点数量

# ---- 赐福光柱 ----
# v3 母版里的光柱本来就只有火头上一小截，两态共用同一张，不存"柱高不同"的问题。
# 之前那套"把上段填掉"的做法整条删了：填色必然留边界（混向天空出来是半透明柱子，
# 混向光晕出来是暗带），看上去就是被擦掉的。两态差多少由固件的 hDimBless 压暗决定。
BEAM_BAND = (109, 127, 176)                 # 柱带：两态都只有火头上一小截细光，差别微乎其微
BEAM_Y1 = 210                               # 柱带底：落到火圈
BEAM_FEATHER = 4                            # 柱带边缘羽化


# 有序抖动而不是 Floyd-Steinberg：Bayer 的偏移只跟坐标有关，两张图同一坐标同色
# 必得同一个索引，背景才可能逐像素相等。FS 依赖误差扩散，位置一变结果就变。
BAYER4 = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
DITHER_AMP = 9.0                            # 抖动幅度（0~255），约一个 RGB565 色阶


def clamp(v):
    return 0 if v < 0 else (255 if v > 255 else int(v))


def grade(img):
    """v3 母版本身偏亮偏紫，这里往回压：小屏要的是暗底 + 克制的金。

    原来那套是"提亮 1.12、加饱和 1.10"，那是给旧母版（底子很暗）用的；
    换到 v3 上会把云和雾一起推成一片粉紫，暗部全糊掉，金色也不再跳。
    现在降亮度、加对比、压饱和——暗的地方真的暗下去，赐福才像唯一的光源。
    """
    img = ImageEnhance.Brightness(img).enhance(0.90)
    img = ImageEnhance.Contrast(img).enhance(1.16)
    return ImageEnhance.Color(img).enhance(0.92)


def load233(path, crop=None):
    if not path.exists():
        raise SystemExit(f"缺少参考图：{path}")
    im = Image.open(path).convert("RGB")
    if crop:
        if crop[2] > im.width or crop[3] > im.height:
            raise SystemExit(f"{path} 尺寸是 {im.size}，装不下取景框 {crop}")
        im = im.crop(crop)
    return grade(im.resize((S, S), Image.LANCZOS))


def build_swap_mask():
    """人马替换区的软蒙版：硬矩形内 255，边缘羽化 SWAP_FEATHER。

    用矩形而不是描轮廓，是因为两张图同源生成，替换区里的草地、雾、石头的纹理
    本来就是一套；矩形边界落在草坡上，羽化几像素就把纹理接回去了。
    """
    mk = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mk).rectangle(
        [SWAP_BOX[0], SWAP_BOX[1], SWAP_BOX[2] - 1, SWAP_BOX[3] - 1], fill=255)
    if SWAP_FEATHER:
        mk = mk.filter(ImageFilter.GaussianBlur(SWAP_FEATHER))
    return mk


def build_beam_mask():
    """光柱带的软蒙版。两态在这里一有一无，是画面最大的差别，不能归到人马区里。"""
    mk = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mk).rectangle(
        [BEAM_BAND[0], BEAM_BAND[2], BEAM_BAND[1] - 1, BEAM_Y1 - 1], fill=255)
    if BEAM_FEATHER:
        mk = mk.filter(ImageFilter.GaussianBlur(BEAM_FEATHER))
    return mk


def build_off(master, alt, swap_mask, beam_mask):
    """未连接态：人马区 + 光柱带取另一张图，其余逐像素复制母版。

    区外必须严格回填：固件靠"同坐标同索引"判断哪些像素属于背景、只重绘那一小块，
    羽化溢出到区外的那几个像素若不收回，边界上就会有一圈两态对不上，
    静止时看不出来，一切换就闪。
    """
    off = master.copy()
    off.paste(alt, (0, 0), swap_mask)
    off.paste(alt, (0, 0), beam_mask)
    op, mp = off.load(), master.load()
    x0, y0, x1, y1 = SWAP_BOX
    bx0, bx1, by0 = BEAM_BAND
    for y in range(S):
        for x in range(S):
            in_swap = x0 <= x < x1 and y0 <= y < y1
            in_beam = bx0 <= x < bx1 and by0 <= y < BEAM_Y1
            if not (in_swap or in_beam):
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
    """赐福火锚点：画面下部暖色行数最多的那一列。

    只在 y 0.62~0.92 之间找。v3 母版里黄金树的光也是暖色，从全图算会把树冠那几列
    选出来；限定在下三分之一，取到的才是火。火本身只有十几行高，阈值跟着降到 8。
    """
    px = img.load()
    y0, y1 = int(S * 0.62), int(S * 0.92)

    def warm(x, y):
        r, g, b = px[x, y]
        return r * 2 + g - 2 * b

    best_x, best_rows = -1, 0
    for x in range(S):
        rows = sum(1 for y in range(y0, y1) if warm(x, y) > 400)
        if rows > best_rows or (rows == best_rows and rows and warm(x, base_y) > warm(best_x, base_y)):
            best_rows, best_x = rows, x
    if best_rows < 5:
        raise SystemExit(f"没找到赐福火：最暖的一列只有 {best_rows} 行达标")
    return best_x, base_y


def main():
    root = Path(__file__).resolve().parent.parent
    master = load233(root / MASTER_REF, CROP)
    alt = load233(root / ALT_REF, CROP)
    swap_mask = build_swap_mask()
    beam_mask = build_beam_mask()
    off = build_off(master, alt, swap_mask, beam_mask)
    on = master
    beam_y1 = BEAM_Y1

    bx, by = beam_xy(on, 204)
    pts = horse_points(off, on, N_PTS)

    pal, q_off, q_on = shared_quantize(off, on)

    # 背景必须真的对得上：替换区之外，同坐标必须同索引。
    # 放行的是 SWAP_BOX（素材真正替换的范围），不是 MAN/HORSE 两个动画矩形——
    # 那两块只是固件重绘的粒度，比替换区小，用它们放行会把羽化边当成错误。
    a, b = q_off.load(), q_on.load()
    bad = []
    for y in range(S):
        for x in range(S):
            if a[x, y] != b[x, y]:
                inside = ((SWAP_BOX[0] <= x < SWAP_BOX[2] and SWAP_BOX[1] <= y < SWAP_BOX[3]) or
                          (BEAM_BAND[0] <= x < BEAM_BAND[1] and BEAM_BAND[2] <= y < BEAM_Y1))
                if not inside:
                    bad.append((x, y))
    if bad:
        head = " ".join(f"({x},{y})" for x, y in bad[:8])
        raise SystemExit(f"背景没对齐：替换区之外有 {len(bad)} 个像素两态不同：{head}")


    dest = root / "firmware/boards/175/MotoNav/resources/HomeSprites.h"
    body = [
        "#pragma once",
        "// 首页画面：8bpp 索引色，233x233，固件按 2x 放大到 466x466。",
        "// 由 scripts/home_sprites.py 生成：两态共用一张调色板，且人马矩形之外逐像素相同，",
        "// 所以状态切换时只重绘人和马那一块，背景一动不动。",
        f"#define HOME_BEAM_X {bx}",
        f"#define HOME_BEAM_Y {by}",
        "// 赐福柱带：两态一有一无（未连接有火柱、已连接只剩小火），切换时这一块跟着重绘",
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
