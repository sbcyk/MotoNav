#pragma once
// 首页：黄昏赐福。两幅画面来自 resources/HomeSprites.h（8bpp 索引色，233x233，
// 显示时按 2x 最近邻放大）：未连接是褪色者独坐赐福旁，已连接是托雷特站在他身后。
// 两格取景比例一致，切换状态只换画面不换景别。素材由 scripts/home_sprites.py 生成。
//
// 绘制分两种：整帧（进页面 / 状态切换 / 浮层开关）和局部（静置时的光尘与火光）。
// 推屏始终是整屏一次；省下来的是绘制量——局部只擦上一帧特效那一小块再重画，
// 静置时每帧只有几百个像素级操作，整帧则要写满 18 万个显示像素。
// 画面走同步推屏（单缓冲），局部更新才不会画到屏幕没在显示的那块缓冲上。

#define WAIT_READY  0
#define WAIT_NOLINK 1
#define WAIT_LOST   2

#include "../../HomeClock.h"
HomeClock homeClock;
char homeClockTime[6] = {};
char homeClockDate[11] = {};

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

// 两色按 t（0~255）混合，用移位代替除法：整帧混合时每像素都要算一次
static inline uint16_t hmix565(uint16_t a, uint16_t b, int t) {
  const int it = 255 - t;
  const int r = (((a >> 11) & 31) * it + ((b >> 11) & 31) * t) >> 8;
  const int g = (((a >> 5) & 63) * it + ((b >> 5) & 63) * t) >> 8;
  const int bl = ((a & 31) * it + (b & 31) * t) >> 8;
  return (uint16_t)((r << 11) | (g << 5) | bl);
}

// ================= 素材 =================
#include "../../resources/HomeSprites.h"

// 两张图必须同尺寸：整帧绘制按同一套 2x 坐标写两张图的像素
static_assert(SCENE_ON_W == SCENE_OFF_W && SCENE_ON_H == SCENE_OFF_H,
              "SCENE_OFF / SCENE_ON 尺寸必须一致");

// 加色叠加：光是加到画面上，不是盖掉背景；k = 0~16，越大越亮
static inline uint16_t hadd(uint16_t p, uint16_t c, int k) {
  int r = ((p >> 11) & 31) + (((c >> 11) & 31) * k >> 4);
  int g = ((p >> 5) & 63) + (((c >> 5) & 63) * k >> 4);
  int b = (p & 31) + ((c & 31) * k >> 4);
  return (uint16_t)(((r > 31 ? 31 : r) << 11) | ((g > 63 ? 63 : g) << 5) | (b > 31 ? 31 : b));
}

// 横向加色条
static void hAddSpan(int x, int y, int w, uint16_t c, int k) {
  if (k <= 0 || w <= 0 || y < 0 || y >= LCD_HEIGHT) return;
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) return;
  if (x < 0) { w += x; x = 0; }
  if (x + w > LCD_WIDTH) w = LCD_WIDTH - x;
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
static float hMix = 0;                     // 0 = 未连接画面，1 = 已连接画面
static int   hBox[4] = {0, 0, 0, 0};       // 上一帧特效矩形（显示像素），局部擦除用

// 取一个显示像素：两张源图按 hMix 混合（m 是 0~255 的量化值）
static inline uint16_t hPix(int x, int y, int m) {
  const uint8_t a = SCENE_OFF_BITS[(size_t)(y >> 1) * SCENE_OFF_W + (x >> 1)];
  if (m <= 0) return SCENE_OFF_PAL[a];
  const uint8_t b = SCENE_ON_BITS[(size_t)(y >> 1) * SCENE_ON_W + (x >> 1)];
  if (m >= 255) return SCENE_ON_PAL[b];
  return hmix565(SCENE_OFF_PAL[a], SCENE_ON_PAL[b], m);
}

// 整帧：逐像素写画布，圆屏四角看不到，按行只写圆内那一段
static void hFullScene() {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) { gfx->fillScreen(C_BLACK); return; }
  const int m = (int)(hMix * 255.0f + 0.5f);
  const float half = SCENE_OFF_W * 0.5f;
  const float r2 = half * half;
  for (int sy = 0; sy < SCENE_OFF_H; sy++) {
    const float dy = sy + 0.5f - half;
    const float t = r2 - dy * dy;
    if (t <= 0) continue;
    int x0 = (int)(half - sqrtf(t)) - 1;
    int x1 = (int)(half + sqrtf(t)) + 1;
    if (x0 < 0) x0 = 0;
    if (x1 > SCENE_OFF_W) x1 = SCENE_OFF_W;
    const uint8_t *ra = SCENE_OFF_BITS + (size_t)sy * SCENE_OFF_W;
    const uint8_t *rb = SCENE_ON_BITS + (size_t)sy * SCENE_ON_W;
    uint16_t *o0 = fb + (size_t)(sy * 2) * LCD_WIDTH + x0 * 2;
    uint16_t *o1 = o0 + LCD_WIDTH;
    for (int sx = x0; sx < x1; sx++) {
      uint16_t c;
      if (m <= 0) c = SCENE_OFF_PAL[ra[sx]];
      else if (m >= 255) c = SCENE_ON_PAL[rb[sx]];
      else c = hmix565(SCENE_OFF_PAL[ra[sx]], SCENE_ON_PAL[rb[sx]], m);
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
  const int m = (int)(hMix * 255.0f + 0.5f);
  for (int y = y0; y < y1; y++) {
    uint16_t *row = fb + (size_t)y * LCD_WIDTH;
    for (int x = x0; x < x1; x++) row[x] = hPix(x, y, m);
  }
}

// 赐福火位置：两张图的火各自在不同位置，取当前这张的坐标再放大 2 倍
static inline int hBeamX() {
  return (hMix >= 0.5f ? HOME_BEAM_ON_X : HOME_BEAM_OFF_X) * 2;
}
static inline int hBeamY() {
  return (hMix >= 0.5f ? HOME_BEAM_ON_Y : HOME_BEAM_OFF_Y) * 2;
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

// 整帧：画面（按 hMix 混合）→ 赐福火光与光尘 → 浮层
static void hDrawFull(unsigned long now) {
  hFullScene();
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
  hMix = (st == WAIT_READY) ? 1.0f : 0.0f;           // 换画面立即生效，不等动画
  if (changed) {                                     // 换状态：赐福处闪一下
    hBoost = 1.6f;
    hBoostAt = millis();
  } else {
    hBoost = 1.0f;
  }
  hInfoOn = false;
  hFrameAt = millis();
#if DEBUG_SERIAL
  Serial.printf("HOME st=%d changed=%d mix=%.2f page=%d on=%d sliding=%d\n",
                st, (int)changed, hMix, page, (int)onWaitScreen, (int)sliding);
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
  const bool full = hFullNext;
  const int gap = hBoost > 1.0f ? 60 : HOME_FRAME_MS;   // 闪光期间 16fps，衰减看着才连续
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
