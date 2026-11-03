#pragma once
// 首页：赐福（Site of Grace）。一根从地面升起的金色光丝 + 脚下法阵 + 上升光尘。
// 由 MotoNav.ino 按依赖顺序包含，仅编译一次。
// v1.1 主页重做：去掉常驻文字与时钟，改成点击浮层；赐福与法阵为纯代码绘制，不依赖素材。
// v1.1.1 修正：法阵被填色盖住、光尘不动、切页后过渡状态残留、浮层绘制未等推屏完成；
//        构图上移、光丝加粗并呼吸、法阵增加扩散波、灵马改为自下而上凝聚。
// 整帧重画 + 异步推屏（frameIsMap），HOME_FRAME_MS 控制目标帧率。

#define WAIT_READY  0
#define WAIT_NOLINK 1
#define WAIT_LOST   2

#include "../../HomeClock.h"
HomeClock homeClock;
char homeClockTime[6] = {};
char homeClockDate[11] = {};

// ================= 赐福配色（RGB565）=================
#define H_AMBER   0xFE0B   // 外晕金
#define H_HOLY    0xFEF2   // 光芯金
#define H_PALE    0xFF9A   // 白金
#define H_DUST    0xFDEB   // 光尘
#define H_SOIL    0x528C   // 土堆亮部
#define H_SOIL_D  0x31A6   // 土堆暗部
#define H_STONE   0x2945   // 碎石
#define H_SPECTRAL   0x7BEF // 召唤扩散波用色（与灵马同系）
#define H_SPECTRAL_HI 0xEFFF
#define H_CARD    0x10A3   // 浮层卡片
#define H_CARD_ED 0x39E7   // 浮层描边

// ================= 构图 =================
#define H_BASE_Y    352        // 光丝根部
#define H_GRACE_H   168        // 光丝基准高度
#define H_GRACE_AMP 12         // 高度呼吸幅度
#define H_DUST_TOP  300        // 光尘上升总行程
#define H_DUST_N    34
#define HOME_FRAME_MS  40      // 25fps，推屏跟不上时由 flushWait 自动节流
#define HOME_SUMMON_MS 1000    // 召唤 / 送别过渡时长

static inline uint16_t hdim(uint16_t c, int k) {   // k: 0~32，32 = 原样
  uint32_t r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31;
  int kk = k < 0 ? 0 : k > 32 ? 32 : k;
  return (uint16_t)(((r * kk >> 5) << 11) | ((g * kk >> 5) << 5) | (b * kk >> 5));
}

static inline uint16_t hmix(uint16_t c, float a) { // 与黑混合，a: 0~1
  return hdim(c, (int)(a * 32.0f + 0.5f));
}

// ================= 场景各层 =================
#include "../../resources/HomeSprites.h"

// 4bpp 索引位图：每字节 2 像素（高 4 位在前），索引 0 = 透明。
// reveal：0~1，只画最上面这一段（自下而上凝聚时从下往上揭示），按行合并连续像素再 fillRect。
static void hBlit4bpp(const uint8_t *bits, int w, int h, int x0, int y0,
                      const uint16_t *pal, float a, float reveal) {
  uint16_t lp[16];
  for (int i = 0; i < 16; i++) lp[i] = hmix(pal[i], a);
  const int stride = (w + 1) / 2;
  const int revealRows = reveal >= 1.0f ? h : (int)(h * reveal);
  const int ySkip = h - revealRows;
  for (int y = ySkip; y < h; y++) {
    const uint8_t *row = bits + y * stride;
    int runAt = -1;
    uint8_t runVal = 0;
    for (int x = 0; x <= w; x++) {
      uint8_t v = 0;
      if (x < w) v = (row[x >> 1] >> ((x & 1) ? 0 : 4)) & 0x0F;
      if (v != runVal || x == w) {
        if (runVal && runAt >= 0) gfx->fillRect(x0 + runAt, y0 + y, x - runAt, 1, lp[runVal]);
        runVal = v;
        runAt = x;
      }
    }
  }
}

// 地面：赐福周围一圈横向反光 + 散落碎石
static void hGraceGround(float breath) {
  for (int i = 0; i < 22; i++) {
    float f = i / 22.0f;
    int w = (int)(120 * (1.0f - f * f));
    if (w <= 0) break;
    gfx->fillRect(CX - w, 344 + i, w * 2, 1, hdim(H_AMBER, (int)(7 * (1.0f - f) * breath)));
  }
  const int pebbles[][5] = {{70,384,10,4,12},{112,394,8,3,10},{156,386,7,3,11},
                            {300,390,9,4,12},{344,382,8,3,11},{388,392,7,3,10},
                            {198,400,11,4,12},{262,396,9,4,11}};
  for (int i = 0; i < 8; i++)
    gfx->fillEllipse(pebbles[i][0], pebbles[i][1], pebbles[i][2], pebbles[i][3],
                     hdim(H_STONE, pebbles[i][4]));
}

// 法阵：先铺一层暗金底，再描三圈细环；否则填色会把描边盖掉
static void hGraceRing(float breath) {
  gfx->fillEllipse(CX, 356, 48, 10, hdim(H_AMBER, (int)(4 * breath)));
  gfx->drawEllipse(CX, 356, 60, 15, hdim(H_HOLY, (int)(10 * breath)));
  gfx->drawEllipse(CX, 356, 50, 12, hdim(H_HOLY, (int)(17 * breath)));
  gfx->drawEllipse(CX, 356, 40, 10, hdim(H_HOLY, (int)(8 * breath)));
}

// 扩散波：每 2.4 秒一圈金光从根部向外推开，越远越淡
static void hGracePulse(unsigned long now, float boost) {
  float p = fmodf(now * 0.00042f, 1.0f);
  int r = 30 + (int)(65 * p);
  gfx->drawEllipse(CX, 356, r, r / 4, hdim(H_HOLY, (int)(14 * (1.0f - p) * boost)));
}

// 土堆：光丝脚下的浅色土丘（在法阵之前画，不盖环）
static void hGraceMound() {
  gfx->fillEllipse(CX, 352, 30, 10, H_SOIL_D);
  gfx->fillEllipse(CX, 350, 22, 7, H_SOIL);
  gfx->fillEllipse(CX, 348, 13, 4, hdim(H_HOLY, 20));
}

// 光丝：高度呼吸 + S 形横摆；外晕与亮芯逐行绘制，亮度随机闪烁
static void hGrace(unsigned long now, float breath, float boost) {
  float flick = 0.84f + 0.16f * sinf(now * 0.0071f);
  const int H = H_GRACE_H + (int)(H_GRACE_AMP * sinf(now * 0.0009f));
  const int topY = H_BASE_Y - H;
  // 垂直泛光：7 层同心椭圆逐层加亮，避免硬边
  for (int i = 0; i < 7; i++) {
    float f = i / 6.0f;
    int rx = (int)(26 * (1.0f - 0.62f * f));
    int ry = (int)(62 * (1.0f - 0.62f * f));
    gfx->fillEllipse(CX, topY + 62, rx, ry, hdim(H_AMBER, (int)((1 + 5 * f) * breath * boost)));
  }
  for (int i = 0; i < H; i++) {
    float t = i / (float)H;
    float u = 1.0f - t;
    int xx = CX + (int)(sinf(t * 4.6f + now * 0.0014f) * (2 + 8 * t));
    int w = (int)(9.0f * u * sqrtf(u));                         // 外晕：u^1.5 收窄
    if (w > 0)
      gfx->fillRect(xx - w, H_BASE_Y - i, w * 2, 1,
                    hdim(H_AMBER, (int)(12 * u * flick * boost)));
    // 亮芯：按 u^0.7 衰减，顶端保留 2px，根部约 12px 宽
    float uc = powf(u, 0.7f);
    int w2 = (int)(5.8f * uc + 1.0f);
    gfx->fillRect(xx - w2, H_BASE_Y - i, w2 * 2, 1,
                  hdim((i % 7) ? H_HOLY : H_PALE, (int)(30 * u * flick * boost)));
  }
  // 根部强光
  gfx->fillEllipse(CX, 350, 22, 7, hdim(H_HOLY, (int)(16 * boost)));
  gfx->fillEllipse(CX, 350, 13, 5, hdim(H_HOLY, (int)(26 * boost)));
  gfx->fillEllipse(CX, 350, 6, 2, H_PALE);
}

// 光尘：随时间上升，越飘越淡、越飘越散；相位均匀分布，避免聚成一簇
static void hDust(unsigned long now, float boost) {
  for (int i = 0; i < H_DUST_N; i++) {
    float ph = fmodf(i / (float)H_DUST_N + now * 0.00011f, 1.0f);
    int y = 348 - (int)(ph * H_DUST_TOP);
    float spread = 8 + ph * 58;
    int x = CX + (int)(sinf(i * 2.7f + ph * 7.5f + now * 0.0012f) * spread);
    float fade = 1.0f - ph;
    int k = (int)(34 * fade * fade * boost);
    if (k <= 1) continue;
    aaDisc(x, y, ph < 0.3f ? 2.2f : 1.2f, hdim((i % 4) ? H_DUST : H_PALE, k));
  }
}

// 灵马：reveal 控制自下而上凝聚，a 控制整体亮度
static void hTorrent(float a, float reveal) {
  if (a <= 0.01f || reveal <= 0.01f) return;
  hBlit4bpp(TORRENT_BITS, TORRENT_W, TORRENT_H, TORRENT_X, TORRENT_Y, TORRENT_PAL, a, reveal);
}

// 召唤 / 送别：法阵向外扩散 + 光点向灵马汇聚
static void hSummonFx(unsigned long now, float p, int dir) {
  float t = dir > 0 ? p : 1.0f - p;
  int r = 24 + (int)(72 * t);
  gfx->drawEllipse(CX, 356, r, r / 4, hdim(H_SPECTRAL, (int)(6 + 16 * (1 - t))));
  for (int i = 0; i < 12; i++) {
    float ang = i * 0.524f + now * 0.0013f;
    float d = (1.0f - t) * (40 + i * 8);
    int px = CX + (int)(cosf(ang) * d);
    int py = 350 - (int)(sinf(ang) * d * 0.6f) - (int)(t * 60);
    aaDisc(px, py, 1.5f, hmix(i % 3 ? H_SPECTRAL_HI : H_PALE, 0.85f * t));
  }
}

// ================= 动画状态 =================
bool onWaitScreen = false;
bool sliding = false;                       // v5.5 正在拖动/滑动换页：别的画面先别画
int waitSt = WAIT_NOLINK;
bool catForce = true;                       // 首页刚重画：马上画一次
static bool   hInfoOn = false;              // 点击浮层是否展开
static unsigned long hInfoAt = 0;
static float  hHorseA = 0;                  // 灵马透明度 0~1
static float  hHorseR = 0;                  // 灵马显形进度 0~1
static float  hTransP = 1;                  // 召唤 / 送别进度
static int    hTransDir = 0;                // +1 召唤，-1 送别
static unsigned long hTransAt = 0;
static int    hSt = -1;                     // 上一次状态，用来判断是否需要过渡
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

// 整帧：地面 → 土堆 → 法阵 → 扩散波 → 灵马 → 光丝 → 光尘 → 浮层
static void hDrawScene(unsigned long now) {
  float breath = 0.88f + 0.12f * sinf(now * 0.0011f);
  float boost = 1.0f + (hTransDir > 0 ? 0.7f * (1.0f - hTransP) : 0.0f);   // 召唤瞬间光丝骤亮
  gfx->fillScreen(C_BLACK);
  hGraceGround(breath);
  hGraceMound();
  hGraceRing(breath);
  hGracePulse(now, boost);
  hTorrent(hHorseA, hHorseR);
  hGrace(now, breath, boost);
  hDust(now, boost);
  if (hTransDir && hTransP < 1.0f) hSummonFx(now, hTransP, hTransDir);
  if (hInfoOn) hDrawInfo();
}

void drawWaiting(int st) {
  waitSt = st;
  if (sliding) return;                                                 // v5.5 正在滑动：滑完再画
  if (page == 2) { onWaitScreen = false; musicDirty = true; return; }
  if (page == 1) { onWaitScreen = false; wxDirty = true; return; }   // v5.3 正在看天气：先不画首页
  onWaitScreen = true;
  catForce = true;
  const bool changed = hSt >= 0 && hSt != st;
  hSt = st;
  if (changed && st == WAIT_READY) {                 // v1.1 连上：光丝骤亮，灵马凝聚
    hTransDir = 1; hTransAt = millis(); hTransP = 0; hHorseA = 0; hHorseR = 0;
  } else if (changed) {                              // v1.1 断开：灵马散成光点
    hTransDir = -1; hTransAt = millis(); hTransP = 0; hHorseA = 1; hHorseR = 1;
  } else {                                           // 同一状态的静态帧（切页回来也走这里）
    hTransDir = 0; hTransP = 1;
    hHorseA = (st == WAIT_READY) ? 1.0f : 0.0f;
    hHorseR = hHorseA;
  }
  hInfoOn = false;
  hFrameAt = millis();
  hDrawScene(hFrameAt);
  needFlush = true;
  frameIsMap = true;
}

// 主页点击：展开 / 收起信息浮层（由 touchPoll 调用）
void homeToggleInfo() {
  if (sliding || page != 0 || inNav || !onWaitScreen) return;
  // 不在这里直接画：画布可能正被异步推屏任务读取，统一交给 animateCat
  // 不在这里直接画：画布可能正被异步推屏任务读取，统一交给 animateCat
  hInfoOn = !hInfoOn;
  hInfoAt = millis();
  catForce = true;
  // 浮层必须走整帧重画，不能在异步推屏途中改正在传输的画布
  needFlush = true;
  frameIsMap = true;
}

// 浮层展开时只有分钟变化才置脏；重画由 animateCat 统一完成
void drawHomeClock() {
  if (!hInfoOn) return;
  static int64_t drawnMinute = -2;
  const int64_t m = homeClock.minuteKey(millis());
  if (m == drawnMinute) return;
  drawnMinute = m;
  catForce = true;
  needFlush = true;
  frameIsMap = true;
}

// 每帧推进：过渡进度、整帧重画；浮层展开时冻结背景动画，只保留呼吸
void animateCat() {
  if (!onWaitScreen || sliding) return;
  const unsigned long now = millis();
  if (hInfoOn && now - hInfoAt >= 6000) {
    hInfoOn = false;
    drawWaiting(waitSt);
    return;
  }
  if (!catForce && now - hFrameAt < HOME_FRAME_MS) return;
  catForce = false;
  hFrameAt = now;
  if (hTransDir) {
    float p = (now - hTransAt) / (float)HOME_SUMMON_MS;
    if (p >= 1.0f) {
      p = 1.0f;
      hTransDir = 0;
      hHorseA = (waitSt == WAIT_READY) ? 1.0f : 0.0f;
      hHorseR = hHorseA;
    } else if (hTransDir > 0) {
      // 前 0.6 先显形，0.25 起再整体提亮：看起来像从脚到头凝聚
      float rp = p / 0.6f;
      hHorseR = rp > 1.0f ? 1.0f : rp;
      hHorseA = p < 0.25f ? p / 0.25f * 0.35f : 0.35f + (p - 0.25f) / 0.75f * 0.65f;
    } else {
      float rp = 1.0f - p;
      hHorseR = rp < 0.0f ? 0.0f : rp;
      hHorseA = 1.0f - p;
    }
    hTransP = p;
  }
  hDrawScene(now);
  needFlush = true;
  frameIsMap = true;                                       // 整帧重画，走异步推屏
}