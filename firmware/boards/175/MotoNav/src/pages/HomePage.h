#pragma once
// 首页：黄昏赐福。两幅画面来自 resources/HomeSprites.h（8bpp 索引色，233x233，
// 显示时按 2x 最近邻放大）：未连接是褪色者独坐赐福旁，已连接是托雷特站在他身旁、
// 他站着牵缰。两幅取自不同的参考图，取景宽度按“主体一样大”定（512 / 683），
// 且让赐福火落在同一个屏幕位置，切换时人和火不跳。素材由 scripts/home_sprites.py 生成。
//
// 绘制分三种：整帧（进页面 / 浮层开关）、溶解（状态切换的 600ms 过渡）、
// 局部（静置时的光尘与火光）。
// 推屏始终是整屏一次；省下来的是绘制量——局部只擦上一帧特效那一小块再重画，
// 静置时每帧只有几百个像素级操作，整帧则要写满 18 万个显示像素。
// 画面走同步推屏（单缓冲），局部更新才不会画到屏幕没在显示的那块缓冲上。

#define WAIT_READY  0
#define WAIT_NOLINK 1
#define WAIT_LOST   2

#include "../../HomeClock.h"
HomeClock homeClock;

// ================= 赐福配色（RGB565）=================
#define H_AMBER   0xFD46   // 外晕金 (255,168,48)
#define H_HOLY    0xFE90   // 光芯金 (255,210,132)
#define H_DUST    0xFDEB   // 光尘
#define H_SPECTRAL_HI 0xEFFF
#define H_CARD    0x10A3   // 浮层卡片
#define H_CARD_ED 0x39E7   // 浮层描边

// ================= 构图 =================
#define H_DUST_N     26        // 光尘数量
#define H_DUST_TOP  150        // 光尘上升行程（显示像素）
#define H_DUST_SPAN  36        // 特效包围盒半宽（光尘实际散布 32，留 4 像素余量）
#define HOME_FRAME_MS  100     // 静置 10fps：只重画光尘那一小块
#define HOME_FLASH_MS  320     // 切换状态时赐福闪一下的时长
#define HOME_MIX_MS    600     // 状态切换时两张图抖动溶解的时长
#define MIX_WMIN       5       // 溶解权重下限：差异为 0 的像素末段也要翻过去，所以不能取 0
#define MIX_WMAX      44       // 溶解权重上限

// 马在“已连接”那张里的位置（233 尺度），溶解时这块先化。
// 跟着 ON_CROP 走：改取景框就要重新标这个椭圆，否则光点会闪在空地上。
#define H_HORSE_CX  52
#define H_HORSE_CY  95
#define H_HORSE_RX  62
#define H_HORSE_RY  72
#define H_HORSE_R2 ((H_HORSE_RX * H_HORSE_RY) * (H_HORSE_RX * H_HORSE_RY))

// ================= 素材 =================
#include "../../resources/HomeSprites.h"

// 两张图必须同尺寸：整帧绘制按同一套 2x 坐标写两张图的像素
static_assert(SCENE_ON_W == SCENE_OFF_W && SCENE_ON_H == SCENE_OFF_H,
              "SCENE_OFF / SCENE_ON 尺寸必须一致");

// 整帧 / 溶解按源像素 2x 写画布，而 hCircleSpan 与 hPix 走的是显示坐标，
// 两套圆内判定只有在“显示尺寸 = 源尺寸 × 2”时才等价，这里锁死。
static_assert(LCD_WIDTH == SCENE_OFF_W * 2 && LCD_HEIGHT == SCENE_OFF_H * 2,
              "显示尺寸必须是源图的 2 倍");

// 加色叠加：光是加到画面上，不是盖掉背景；k = 0~16，越大越亮
static inline uint16_t hadd(uint16_t p, uint16_t c, int k) {
  int r = ((p >> 11) & 31) + (((c >> 11) & 31) * k >> 4);
  int g = ((p >> 5) & 63) + (((c >> 5) & 63) * k >> 4);
  int b = (p & 31) + ((c & 31) * k >> 4);
  return (uint16_t)(((r > 31 ? 31 : r) << 11) | ((g > 63 ? 63 : g) << 5) | (b > 31 ? 31 : b));
}

// 圆屏有效区：画布是方的，圆外那圈不发光。光效与局部擦除都裁到圆内，
// 圆外保持初始化时的黑，否则光尘飘出圆外的部分会留在已废弃的画布角落。
// （信息浮层和页码点画在圆心附近，不经过这里。）
static inline void hCircleSpan(int y, int &x0, int &x1) {
  const float r = LCD_WIDTH * 0.5f;
  const float dy = (float)y + 0.5f - r;
  const float t = r * r - dy * dy;
  if (y < 0 || y >= LCD_HEIGHT || t <= 0) { x0 = x1 = 0; return; }
  const float s = sqrtf(t);
  x0 = (int)(r - s) - 1; if (x0 < 0) x0 = 0;
  x1 = (int)(r + s) + 1; if (x1 > LCD_WIDTH) x1 = LCD_WIDTH;
}

// 横向加色条（裁到圆内）
static void hAddSpan(int x, int y, int w, uint16_t c, int k) {
  if (k <= 0 || w <= 0 || y < 0 || y >= LCD_HEIGHT) return;
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) return;
  int cx0, cx1;
  hCircleSpan(y, cx0, cx1);
  if (x < cx0) { w -= cx0 - x; x = cx0; }
  if (x + w > cx1) w = cx1 - x;
  if (w <= 0) return;
  uint16_t *row = fb + (size_t)y * LCD_WIDTH;
  for (int i = 0; i < w; i++) row[x + i] = hadd(row[x + i], c, k);
}

// 加色椭圆：中心最亮、向外衰减
static void hAddEllipse(int cx, int cy, int rx, int ry, uint16_t c, int kMax) {
  if (rx <= 0 || ry <= 0 || kMax <= 0) return;
  for (int j = -ry; j <= ry; j++) {
    float v = 1.0f - (float)(j * j) / (float)(ry * ry);
    if (v <= 0) continue;
    int w = (int)(rx * sqrtf(v));
    if (w <= 0) continue;
    hAddSpan(cx - w, cy + j, w * 2, c, (int)(kMax * v + 0.5f));
  }
}

// ================= 画面 =================
static bool  hOnScene = false;             // false = 未连接画面，true = 已连接画面
static int   hBox[4] = {0, 0, 0, 0};       // 上一帧特效矩形（显示像素），局部擦除用

// 取一个显示像素：直接查当前那张图，1 源像素对应 2x2 显示像素
static inline uint16_t hPix(int x, int y) {
  const size_t o = (size_t)(y >> 1) * SCENE_OFF_W + (x >> 1);
  return hOnScene ? SCENE_ON_PAL[SCENE_ON_BITS[o]] : SCENE_OFF_PAL[SCENE_OFF_BITS[o]];
}

// 一个源行对应两行显示像素，取这两行在圆内的并集（已按 2 对齐，源像素一次写两个）。
// 不能只按源像素中心判一次圆：圆顶 / 圆底曲率大，两行显示像素的圆内宽度差 1~4 像素，
// 按中心判会漏写圆内那一小截边缘，那截就留在画布上成了旧内容。
static inline void hScenePairSpan(int sy, int &x0, int &x1) {
  int a0, a1;
  x0 = LCD_WIDTH; x1 = 0;
  for (int sub = 0; sub < 2; sub++) {
    hCircleSpan(sy * 2 + sub, a0, a1);
    if (a1 <= a0) continue;
    if (a0 < x0) x0 = a0;
    if (a1 > x1) x1 = a1;
  }
  if (x0 >= x1) { x0 = x1 = 0; return; }
  x0 &= ~1;                                            // 源像素一次写两个，起点向下取偶
  x1 = (x1 + 1) & ~1;                                  // 终点向上取偶，别把圆内那半个像素切掉
  if (x1 > LCD_WIDTH) x1 = LCD_WIDTH;
}

// 整帧：逐像素写画布，圆屏四角看不到，按行只写圆内那一段
static void hFullScene() {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) { gfx->fillScreen(C_BLACK); return; }
  for (int sy = 0; sy < SCENE_OFF_H; sy++) {
    int x0, x1;
    hScenePairSpan(sy, x0, x1);
    if (x0 >= x1) continue;
    const uint8_t *ra = SCENE_OFF_BITS + (size_t)sy * SCENE_OFF_W;
    const uint8_t *rb = SCENE_ON_BITS + (size_t)sy * SCENE_ON_W;
    uint16_t *o0 = fb + (size_t)(sy * 2) * LCD_WIDTH + x0;
    uint16_t *o1 = o0 + LCD_WIDTH;
    for (int sx = x0 >> 1; sx < (x1 >> 1); sx++) {
      const uint16_t c = hOnScene ? SCENE_ON_PAL[rb[sx]] : SCENE_OFF_PAL[ra[sx]];
      o0[0] = c; o0[1] = c; o1[0] = c; o1[1] = c;
      o0 += 2; o1 += 2;
    }
  }
}

// ================= 状态切换：抖动溶解 =================
// 逐像素按固定随机顺序换成新图。每个像素有自己的起翻时刻：两图差得越多越早翻，
// 马那块再加一份权重，所以马先散；天空、地面两图差得小，翻得晚，翻过去也不显眼。
// 锋面上“马上要翻”的像素点成金色，读起来就是整屏化开成光点、再重新聚成画面。
// 不用逐像素混色：混色要算三次乘法，抖动换像素只是一次比较，像素风也更耐这种质变。
// v2.1 过渡改为“可反向推进”：记进度 hMixT（0 = 起点图，1 = 终点图）而不是开始时刻。
// 快速连上又断开时，目标会中途改回来，这时只把方向改成 -1，像素按各自的翻转时刻
// 原路退回起点图——画面从屏幕上这一刻的实际混合态接着走，不会跳回整张图重来。
static bool hMixFromOn = false;            // 过渡起点是哪张
static bool hMixing = false;
static float hMixT = 0;                    // 当前进度：0 = 起点图，1 = 终点图
static int8_t hMixDir = 1;                 // +1 朝终点推进，-1 原路退回
static unsigned long hMixAt = 0;           // 上一次推进的时刻（算 dt）

// 稳定的伪随机阈值（按源像素坐标），同一像素每帧都是同一个值，才能“一个一个翻”而不是闪噪
static inline uint32_t hNoise(int x, int y) {
  // 先转 uint32_t 再乘：x * 73856093 在 int 里会溢出（x>29 就超），有符号溢出是未定义行为
  uint32_t v = ((uint32_t)x * 73856093u) ^ ((uint32_t)y * 19349663u);
  v ^= v >> 13; v *= 0x5bd1e995u; v ^= v >> 15;
  return v;
}

static inline int hPalDiff(uint16_t a, uint16_t b) {
  int d = (int)((a >> 11) & 31) - (int)((b >> 11) & 31); if (d < 0) d = -d;
  int e = (int)((a >> 5) & 63) - (int)((b >> 5) & 63); if (e < 0) e = -e;
  int f = (int)(a & 31) - (int)(b & 31); if (f < 0) f = -f;
  return d + e + f;
}

static void hMixScene(float t) {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) { gfx->fillScreen(C_BLACK); return; }
  const int k = (int)(t * 256.0f);
  const uint8_t *oldBits = hMixFromOn ? SCENE_ON_BITS : SCENE_OFF_BITS;
  const uint16_t *oldPal = hMixFromOn ? SCENE_ON_PAL : SCENE_OFF_PAL;
  const uint8_t *newBits = hOnScene ? SCENE_ON_BITS : SCENE_OFF_BITS;
  const uint16_t *newPal = hOnScene ? SCENE_ON_PAL : SCENE_OFF_PAL;
  for (int sy = 0; sy < SCENE_OFF_H; sy++) {
    int x0, x1;
    hScenePairSpan(sy, x0, x1);
    if (x0 >= x1) continue;
    const uint8_t *ra = oldBits + (size_t)sy * SCENE_OFF_W;
    const uint8_t *rb = newBits + (size_t)sy * SCENE_OFF_W;
    uint16_t *o0 = fb + (size_t)(sy * 2) * LCD_WIDTH + x0;
    uint16_t *o1 = o0 + LCD_WIDTH;
    for (int sx = x0 >> 1; sx < (x1 >> 1); sx++) {
      const uint16_t ca = oldPal[ra[sx]];
      const uint16_t cb = newPal[rb[sx]];
      // 翻转优先级：两图差得越多越先翻，马那一块再加一份权重
      const int dx = (sx - H_HORSE_CX) * H_HORSE_RY;
      const int dy = (sy - H_HORSE_CY) * H_HORSE_RX;
      const int q2 = dx * dx + dy * dy;
      int wgt = hPalDiff(ca, cb) + (q2 < H_HORSE_R2 ? (28 * (H_HORSE_R2 - q2)) / H_HORSE_R2 : 0);
      if (wgt > MIX_WMAX) wgt = MIX_WMAX;
      // 每个像素有自己的起翻时刻：权重越高越早。用“时刻”而不是“每帧重算的阈值”，
      // 才能保证 t=1（k=256）压过所有 start<=255，全部翻完、不留残影。
      const int n = (int)(hNoise(sx, sy) & 255);
      const int speed = (MIX_WMIN + wgt) * 256 / (MIX_WMIN + MIX_WMAX);   // 26~256
      int start = 255 - speed * (255 - n) / 255;
      if (start < 0) start = 0;
      uint16_t c = (k > start) ? cb : ca;
      // 锋面上“还没翻、马上要翻”的像素点成金色。用 start>=k 而不是两端对称，
      // t=0 和 t=1 时锋面为空，两端都是干净的目标图。
      if (k > 0 && start >= k && start - k < 10 && wgt > 18)
        c = ((sx ^ sy) & 1) ? H_HOLY : H_AMBER;
      o0[0] = c; o0[1] = c; o1[0] = c; o1[1] = c;
      o0 += 2; o1 += 2;
    }
  }
}

// 局部擦除：把矩形区用当前画面重新盖回去（光尘动了，旧位置要擦）
static void hRestore(int x0, int y0, int x1, int y1) {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) return;
  if (x0 < 0) x0 = 0;
  if (y0 < 0) y0 = 0;
  if (x1 > LCD_WIDTH) x1 = LCD_WIDTH;
  if (y1 > LCD_HEIGHT) y1 = LCD_HEIGHT;
  if (x0 >= x1 || y0 >= y1) return;
  for (int y = y0; y < y1; y++) {
    int cx0, cx1;
    hCircleSpan(y, cx0, cx1);                       // 包围盒角落可能出圆，逐行再裁一次
    if (x0 > cx0) cx0 = x0;
    if (x1 < cx1) cx1 = x1;
    if (cx0 >= cx1) continue;
    uint16_t *row = fb + (size_t)y * LCD_WIDTH;
    for (int x = cx0; x < cx1; x++) row[x] = hPix(x, y);
  }
}

// 赐福火位置：两张图的火各自在不同位置，取当前这张的坐标再放大 2 倍
static inline int hBeamX() {
  return (hOnScene ? HOME_BEAM_ON_X : HOME_BEAM_OFF_X) * 2;
}
static inline int hBeamY() {
  return (hOnScene ? HOME_BEAM_ON_Y : HOME_BEAM_OFF_Y) * 2;
}

// 光尘 + 赐福火光：只动这两层，画完把包围盒交给局部重绘用
static void hEffects(unsigned long now, float boost) {
  const int bx = hBeamX(), by = hBeamY();
  // 火光呼吸
  const float breath = 0.75f + 0.25f * sinf(now * 0.0011f);
  const int k = (int)((1.5f + 1.5f * breath) * boost + 0.5f);
  hAddEllipse(bx, by - 6, 26, 9, H_AMBER, k);
  hAddEllipse(bx, by - 12, 12, 5, H_HOLY, k);
  if (boost > 1.05f) {                                    // 切换闪光（半径必须留在包围盒内）
    const int r = 20 + (int)(12 * (boost - 1.0f) / 0.6f);
    hAddEllipse(bx, by, r, r / 4, H_SPECTRAL_HI, (int)((boost - 1.0f) * 10));
  }
  // 光尘：加色点，压在亮天空上也只会更亮
  for (int i = 0; i < H_DUST_N; i++) {
    const float ph = fmodf(i / (float)H_DUST_N + now * 0.00009f, 1.0f);
    const int y = by - (int)(ph * H_DUST_TOP);
    const float spread = 6 + ph * 26;
    const int x = bx + (int)(sinf(i * 2.7f + ph * 7.5f + now * 0.0011f) * spread);
    const float fade = 1.0f - ph;
    const int dk = (int)(7 * fade * fade * boost);
    if (dk <= 0) continue;
    const int r = ph < 0.3f ? 2 : 1;
    hAddEllipse(x, y, r, r, (i % 4) ? H_DUST : H_HOLY, dk);
  }
  hBox[0] = bx - H_DUST_SPAN - 4;
  hBox[1] = by - H_DUST_TOP - 4;
  hBox[2] = bx + H_DUST_SPAN + 4;
  hBox[3] = by + 12;
}

// ================= 动画状态 =================
bool onWaitScreen = false;
bool sliding = false;                       // v5.5 正在拖动/滑动换页：别的画面先别画
int waitSt = WAIT_NOLINK;
bool catForce = true;                       // 首页刚重画：马上画一次
static bool   hInfoOn = false;              // 点击浮层是否展开
static unsigned long hInfoAt = 0;
static float  hBoost = 1;                   // 赐福闪光强度，切换后衰减回 1
static unsigned long hBoostAt = 0;
static bool   hFullNext = true;             // 下一帧要整帧重画
static int    hSt = -1;                     // 上一次状态，用来判断要不要闪一下
static unsigned long hFrameAt = 0;
static bool   hSkipMixOnce = false;         // 滑动合成要静态落点：这一次不做溶解

#include "../../FixedPageLayout.h"
// 固定位置：音乐在左、导航居中、天气在右；降雨在天气上方、预警在下方。
int page = 0;                               // 0 = 导航 / 首页，1 = 天气，2 = 音乐
int wxDetail = 0;                           // 天气列：0 = 天气，1 = 上方降雨，2 = 下方预警
unsigned long pageAt = 0;

// 页面顺序对应滑动位置：音乐在左，主页居中，天气在右；导航主页不显示。
void drawPageDots() {
  if (page == 0 && inNav) return;
  const int pageOrder[] = {2, 0, 1};
  for (int i = 0; i < 3; i++) {
    aaDisc(CX + (i - 1) * 20, 444, 4, page == pageOrder[i] ? C_WHITE : 0x4208);
  }
  if (page == 1) for (int i = 0; i < 3; i++) {
    aaDisc(438, CX + (i - 1) * 18, 3,
      i == FixedPageLayout::weatherRow(wxDetail) ? C_WHITE : 0x4208);
  }
}

// 点击浮层：时间日期 + 连接状态 + 蓝牙名 + 电量 + 固件版本
static void hDrawInfo() {
  gfx->fillRoundRect(CX - 152, 130, 304, 238, 18, H_CARD);
  gfx->drawRoundRect(CX - 152, 130, 304, 238, 18, H_CARD_ED);
  char time[6], date[11];
  const bool ok = homeClock.format(millis(), time, date);
  printCentered(ok ? time : "--:--", CX, 148, 8, C_WHITE);
  printCentered(ok ? date : "---- -- --", CX, 226, 2, C_GREY);
  gfx->fillRect(CX - 118, 254, 236, 1, 0x2945);
  const char *s = waitSt == WAIT_READY ? "LINKED" : waitSt == WAIT_LOST ? "LINK LOST" : "NOT LINKED";
  printCentered(s, CX, 266, 2, waitSt == WAIT_READY ? C_GREEN : C_GREY);
  printCentered(bleName, CX, 290, 2, C_GREY);
  char bat[24];
  if (batPct >= 0) snprintf(bat, sizeof(bat), "BAT %d%%", batPct); else strcpy(bat, "BAT --");
  printCentered(bat, CX, 312, 2, C_GREY);
  char fw[40];
  snprintf(fw, sizeof(fw), "%s  %dMHz", FW_VERSION, qspiMHz);
  printCentered(fw, CX, 336, 1, C_GREY);
  printCentered("TAP TO CLOSE", CX, 350, 1, 0x4208);
}

// 整帧：画面 → 赐福火光与光尘 → 浮层
static void hDrawFull(unsigned long now) {
  if (hMixing) {
    hMixScene(hMixT);                    // v2.1 进度由 animateCat 维护，可正可反
  } else {
    hFullScene();
  }
  hEffects(now, hBoost);
  if (hInfoOn) hDrawInfo();
}

void drawWaiting(int st) {
  waitSt = st;
  if (sliding) return;                                                 // v5.5 正在滑动：滑完再画
  if (page == 2) { onWaitScreen = false; musicDirty = true; return; }
  if (page == 1) { onWaitScreen = false; wxDirty = true; return; }   // v5.3 正在看天气：先不画首页
  onWaitScreen = true;
  catForce = true;
  hFullNext = true;
  const bool changed = hSt >= 0 && hSt != st;
  hSt = st;
  const bool target = (st == WAIT_READY);
  // v2.1 过渡状态机（三种情况互斥，不再有“从上一张目标图重来”的跳变）：
  //   1. 滑动落点 hSkipMixOnce：必须是一张静态目标图，直接落地，不参与过渡；
  //   2. 正在过渡：目标没变就继续推进（+1），目标改回起点图就原路退回（-1）；
  //   3. 没在过渡且目标与屏上不同：从当前这张图开始新的过渡。
  // hOnScene 在过渡期间仍表示“终点图”（hMixScene 要按它取像素），退回到 0 时才归位。
  if (hSkipMixOnce) {
    hSkipMixOnce = false;
    hMixing = false;
    hMixT = 0;
    hMixDir = 1;
    hMixFromOn = target;
    hOnScene = target;
  } else if (hMixing) {
    hMixDir = (target == hOnScene) ? 1 : -1;
  } else if (target != hOnScene) {
    hMixFromOn = hOnScene;
    hOnScene = target;
    hMixT = 0;
    hMixDir = 1;
    hMixing = true;
    hMixAt = millis();
  }
  if (changed) {                                     // 换状态：赐福处闪一下
    hBoost = 1.6f;
    hBoostAt = millis();
  } else if (!hMixing) {
    hBoost = 1.0f;
  }
  hInfoOn = false;
  hFrameAt = millis();
#if DEBUG_SERIAL
  Serial.printf("HOME st=%d changed=%d scene=%d mix=%d page=%d on=%d sliding=%d\n",
                st, (int)changed, (int)hOnScene, (int)hMixing, page, (int)onWaitScreen, (int)sliding);
#endif
  hDrawFull(hFrameAt);
  hFullNext = false;                                 // 这一帧已经是整帧，别让下一帧再整屏重画
  needFlush = true;
  frameIsMap = false;                                // 同步推屏（单缓冲），局部更新才有效
}

// 主页点击：展开 / 收起信息浮层（由 touchPoll 调用）
void homeToggleInfo() {
  if (sliding || page != 0 || inNav || !onWaitScreen) return;
  // 不在这里直接画：画布可能正被异步推屏任务读取，统一交给 animateCat
  hInfoOn = !hInfoOn;
  hInfoAt = millis();
  catForce = true;
  hFullNext = true;
  needFlush = true;
  frameIsMap = false;
}

// 浮层展开时只有分钟变化才置脏；重画由 animateCat 统一完成
void drawHomeClock() {
  if (!hInfoOn) return;
  static int64_t drawnMinute = -2;
  const int64_t m = homeClock.minuteKey(millis());
  if (m == drawnMinute) return;
  drawnMinute = m;
  catForce = true;
  hFullNext = true;
  needFlush = true;
  frameIsMap = false;
}

// 每帧推进：需要整帧时整帧重画，其余只擦上一帧特效那一小块再画新的
void animateCat() {
  if (!onWaitScreen || sliding) {
#if DEBUG_SERIAL
    static unsigned long warnAt = 0;
    if (!onWaitScreen && page == 0 && !inNav && millis() - warnAt > 3000) {
      warnAt = millis();
      Serial.printf("HOME idle: onWaitScreen=0 st=%d page=%d inNav=%d sliding=%d\n",
                    waitSt, page, (int)inNav, (int)sliding);
    }
#endif
    return;
  }
  const unsigned long now = millis();
  if (hInfoOn && now - hInfoAt >= 6000) {
    hInfoOn = false;
    drawWaiting(waitSt);
    return;
  }
  if (hInfoOn && !catForce) return;                  // 浮层开着：冻住背景动画，只等分钟变
  if (hMixing) {                                     // v2.1 按时间推进，方向可正可反
    unsigned long dt = now - hMixAt;
    hMixAt = now;
    if (dt > 100) dt = 100;                          // 浮层冻住 / 卡过帧：别一下跳到对面
    hMixT += hMixDir * (float)dt / (float)HOME_MIX_MS;
    if (hMixT >= 1.0f) {                             // 到终点图：整帧收尾
      hMixT = 1.0f;
      hMixing = false;
      hFullNext = true;
      catForce = true;                               // 别让下面的 gap 把收尾帧推迟
    } else if (hMixT <= 0.0f) {                      // 原路退回起点图：把锚点也归位
      hMixT = 0.0f;
      hMixing = false;
      hOnScene = hMixFromOn;
      hFullNext = true;
      catForce = true;
    }
  }
  const bool full = hFullNext || hMixing;
  const int gap = hMixing ? 33 : (hBoost > 1.0f ? 60 : HOME_FRAME_MS);
  if (!catForce && now - hFrameAt < gap) return;
  catForce = false;
  hFrameAt = now;
  if (hBoost > 1.0f) {                               // 闪光按时间衰减，与帧率无关
    float q = 1.0f - (now - hBoostAt) / (float)HOME_FLASH_MS;
    hBoost = q <= 0.0f ? 1.0f : 1.0f + 0.6f * q;
  }
  if (full) {
    hFullNext = false;
    hDrawFull(now);
  } else {
    hRestore(hBox[0], hBox[1], hBox[2], hBox[3]);
    hEffects(now, hBoost);
  }
  needFlush = true;
  frameIsMap = false;
}
