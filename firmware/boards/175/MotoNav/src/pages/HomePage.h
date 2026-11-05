#pragma once
// 首页：黄昏赐福。两态共用一张背景，只有人和马那一块不同：
// 未连接是褪色者独坐赐福旁，已连接是托雷特由蓝色粒子聚合现身、褪色者起身牵缰。
//
// v2.2 起不再用“两张整图抖动溶解”。素材侧把两态的**人马矩形之外**做成逐像素相同、
// 共用同一张调色板（scripts/home_sprites.py 会校验，失配就报错），所以：
//   · 状态切换只重绘人和马那一小块，天空、峡谷、王城、黄金树、赐福火一动不动；
//   · 人靠纵向扫描从脚往上“立”起来，马靠蓝色粒子从地面聚拢成形；
//   · 赐福光随姿态变：坐火（坐着）亮而盛，未坐火（站着）暗一档、火苗小一号、粒子稀少。
// v2.3 赐福分两档，读的是《黑暗之魂/艾尔登法环》那套规则：没坐下休息时赐福本身也发金光，
// 只是弱——所以站着不是"灭掉"，是火苗小一圈、亮度档 16→9、闪烁粒子 10→5、光尘 20→10。
// 素材里那根金色光柱是画进图里的（两态共用背景，见 v2.2），代码改不了它的高度；
// 想让它变矮只能重做母版图，纯像素修补会在山体上留下灰块/黑烟。
// 绘制仍分整帧（进度推进 / 进页面 / 浮层）和局部（静置的光尘与火光）两种。
// 推屏始终整屏一次；局部只擦上一帧特效那一小块再重画，静置时每帧只有几百个像素级操作。
// 画面走同步推屏（单缓冲），局部更新才不会画到屏幕没在显示的那块缓冲上。

#define WAIT_READY  0
#define WAIT_NOLINK 1
#define WAIT_LOST   2

#include "../../HomeClock.h"
HomeClock homeClock;

// ================= 配色（RGB565）=================
#define H_AMBER   0xFD46   // 外晕金 (255,168,48)
#define H_HOLY    0xFE90   // 光芯金 (255,210,132)
#define H_DUST    0xFDEB   // 光尘
#define H_SPECTRAL_HI 0xEFFF
#define H_SPARK_HI 0x8E5F  // 马粒子：亮蓝白
#define H_SPARK    0x3BDB  // 马粒子：蓝
#define H_SPARK_LO 0x19F1  // 马粒子：暗蓝
#define H_CARD    0x10A3   // 浮层卡片
#define H_CARD_ED 0x39E7   // 浮层描边

// ================= 构图 =================
#define H_DUST_N     20        // 光尘数量（未坐火只用前一半）
#define H_DUST_TOP_SIT   96    // 坐着时光尘上升行程（v2.3 从 150 压到 96：光别升那么高）
#define H_DUST_TOP_STAND 68    // 站着时行程更短：赐福没被交互
#define H_SPK_N      10        // 赐福闪烁粒子（未坐火只亮前一半）
#define H_FX_SPAN    44        // 特效包围盒半宽（粒子最远 35，留余量）
#define H_FX_TOP     128       // 特效最高处（相对火心）
#define H_MAN_UNTIL  0.55f     // 进度到 55% 时人已经站直，剩下的都留给马
#define H_HRS_FROM   0.25f     // 马从 25% 开始聚合，到 100% 成完
#define H_MAN_BAND   13        // 起身扫描带的半宽（源像素）：带内按噪声逐个翻，不是一刀切
#define HOME_FRAME_MS  100     // 静置 10fps：只重画光尘那一小块
#define HOME_FLASH_MS  320     // 切换状态时赐福闪一下的时长
#define HOME_SWITCH_MS 700     // 起身 / 坐下 + 马聚合消散的全程

// 进度分配：人先起身（前 55%），马在后段聚合（25%~100%）。
// 断开时进度反向走，于是“马先散、人后坐”，正好是想要的顺序。
static inline float hManProgress(float t) {
  float v = t / H_MAN_UNTIL;
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}
static inline float hHrsProgress(float t) {
  float v = (t - H_HRS_FROM) / (1.0f - H_HRS_FROM);
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

// ================= 素材 =================
#include "../../resources/HomeSprites.h"

// 整帧 / 局部都按源像素 2x 写画布，而 hCircleSpan 与 hPix 走显示坐标，
// 两套圆内判定只有在“显示尺寸 = 源尺寸 × 2”时才等价，这里锁死。
static_assert(LCD_WIDTH == SCENE_W * 2 && LCD_HEIGHT == SCENE_H * 2,
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
static float  hT = 0;                       // 0 = 未连接（坐、无马），1 = 已连接（站、有马）
static int8_t hDir = 0;                     // +1 朝已连接推进，-1 朝未连接退回，0 静置
static unsigned long hTAt = 0;
static int   hBox[4] = {0, 0, 0, 0};        // 上一帧特效矩形（显示像素），局部擦除用

// 取一个源像素的调色板下标。局部擦除只在静置时调用（过渡中一律整帧），
// 那时 hT 必定是 0 或 1，取哪张都干净。
static inline uint8_t hPixIdx(int sx, int sy) {
  const size_t o = (size_t)sy * SCENE_W + sx;
  return hT >= 0.5f ? SCENE_ON_BITS[o] : SCENE_OFF_BITS[o];
}

// 取一个显示像素（局部擦除用）
static inline uint16_t hPix(int x, int y) {
  return SCENE_PAL[hPixIdx(x >> 1, y >> 1)];
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

// 稳定的伪随机阈值（按源像素坐标），同一像素每帧都是同一个值，才能“一个一个长”而不是闪噪
static inline uint32_t hNoise(int x, int y) {
  // 先转 uint32_t 再乘：x * 73856093 在 int 里会溢出（x>29 就超），有符号溢出是未定义行为
  uint32_t v = ((uint32_t)x * 73856093u) ^ ((uint32_t)y * 19349663u);
  v ^= v >> 13; v *= 0x5bd1e995u; v ^= v >> 15;
  return v;
}

// 马像素的显形时刻：1~256，越小越早。按下半部优先、再叠一份随机，
// 读起来是“粒子先在地上聚拢，马从地面往上长出来”。
static inline int hHorseOrder(int sx, int sy) {
  const int fromBottom = (HOME_HRS_Y1 - sy) * 128 / (HOME_HRS_Y1 - HOME_HRS_Y0);
  return 1 + (int)(hNoise(sx, sy) & 127) + fromBottom;
}

// 人起身的判定位：扫描线附近的过渡带。整块横向替换会把人拦腰截成一条直线，
// 带内改成按像素噪声一个个翻，边上就是碎的，像素风下读作“人从光里长出来”。
static inline bool hStood(int sx, int sy, int manLine) {
  const int d = sy - manLine;
  if (d >= H_MAN_BAND) return true;
  if (d <= -H_MAN_BAND) return false;
  const int th = (d + H_MAN_BAND) * 255 / (2 * H_MAN_BAND);
  return (int)(hNoise(sx, sy) & 255) < th;
}

// 扫描线要带外起步：t=0 时整块必须全是坐姿、t=1 时整块必须全是站姿，
// 否则两端会残留几个过渡带里的杂点，静置画面就永远不干净。
static inline int hManLine(float manT) {
  const int span = HOME_MAN_Y1 - HOME_MAN_Y0 + 2 * H_MAN_BAND;
  return HOME_MAN_Y1 + H_MAN_BAND - (int)(manT * span + 0.5f);
}

// 整帧：背景两态逐像素相同，只有人和马那两块按进度换
static void hScene() {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) { gfx->fillScreen(C_BLACK); return; }
  const float manT = hManProgress(hT);
  const float hrsT = hHrsProgress(hT);
  const int manLine = hManLine(manT);
  const int hrsK = (int)(hrsT * 256.0f);
  for (int sy = 0; sy < SCENE_H; sy++) {
    int x0, x1;
    hScenePairSpan(sy, x0, x1);
    if (x0 >= x1) continue;
    const uint8_t *ro = SCENE_OFF_BITS + (size_t)sy * SCENE_W;
    const uint8_t *rn = SCENE_ON_BITS + (size_t)sy * SCENE_W;
    const bool manRow = (sy >= HOME_MAN_Y0 && sy < HOME_MAN_Y1);
    const bool hrsRow = (sy >= HOME_HRS_Y0 && sy < HOME_HRS_Y1);
    uint16_t *o0 = fb + (size_t)(sy * 2) * LCD_WIDTH + x0;
    uint16_t *o1 = o0 + LCD_WIDTH;
    for (int sx = x0 >> 1; sx < (x1 >> 1); sx++) {
      const uint8_t a = ro[sx], b = rn[sx];
      uint8_t idx;
      if (a == b) {
        idx = b;                                       // 背景：两态一样，取谁都行——这正是不跳的根据
      } else {
        const bool inMan = manRow && sx >= HOME_MAN_X0 && sx < HOME_MAN_X1;
        const bool inHrs = hrsRow && sx >= HOME_HRS_X0 && sx < HOME_HRS_X1;
        if (inMan && inHrs) {
          // 马头右缘和人手是连在一起的（母版里他正扶着马头），这块要两边都到位才翻，
          // 否则会出现“人已经站好、马头先于马身浮在半空”。
          idx = (hStood(sx, sy, manLine) && hHorseOrder(sx, sy) <= hrsK) ? b : a;
        } else if (inMan) {
          idx = hStood(sx, sy, manLine) ? b : a;       // 人：扫描线往上推，下半身先站起来
        } else if (inHrs) {
          idx = (hHorseOrder(sx, sy) <= hrsK) ? b : a; // 马：按各自的显形时刻一个个翻
        } else {
          idx = b;
        }
      }
      const uint16_t c = SCENE_PAL[idx];
      o0[0] = c; o0[1] = c; o1[0] = c; o1[1] = c;
      o0 += 2; o1 += 2;
    }
  }
}

// 马身上的蓝粒子：从落点向四周散开（或反向聚拢）。用固定落点表 + 坐标派生的
// 抖动量，不存粒子数组——退到哪一帧都能算出来，快速连断也不会留残影。
static void hHorseSparks(float hrsT) {
  if (hrsT <= 0.02f || hrsT >= 0.97f) return;
  const float w = 1.0f - fabsf(2.0f * hrsT - 1.0f);   // 中间最盛，两端收敛
  const float away = (1.0f - hrsT) * (1.0f - hrsT);   // 还没聚拢时的散开量
  const int kMax = (int)(26.0f * w) + 4;
  for (int i = 0; i < HOME_PTS_N; i++) {
    const int tx = HOME_PTS[i * 2], ty = HOME_PTS[i * 2 + 1];
    const uint32_t n = hNoise(i * 29 + 7, i * 13 + 3);
    const int dx = (int)(n & 63) - 32;                // -32..31
    const int dy = (int)((n >> 6) & 63) - 40;         // 往上飘得多一点
    const int x = tx + (int)(dx * away * 1.1f);
    const int y = ty + (int)(dy * away * 1.1f);
    if (x < 0 || x >= SCENE_W || y < 0 || y >= SCENE_H) continue;
    const uint16_t c = (i % 3) == 0 ? H_SPARK_HI : ((i % 3) == 1 ? H_SPARK : H_SPARK_LO);
    const int r = (i % 4) == 0 ? 2 : 1;
    hAddEllipse(x * 2, y * 2, r, r, c, kMax);
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

// 赐福粒子（v2.3）：围着火苗明灭的小光点，锚点固定、相位由下标派生，不存粒子状态。
// 前 5 颗贴着火苗，未坐火也亮着——赐福不休息时同样发光；后 5 颗更远，只在坐火时出现。
static const int8_t hSpkPts[H_SPK_N][2] = {
  {22, -32}, {-20, -40}, {34, -18}, {-28, -24}, {8, -58},
  {40, -56}, {-38, -62}, {30, -76}, {48, -38}, {-16, -88},
};

static void hBlessSparks(unsigned long now, float boost, float manT) {
  const int bx = HOME_BEAM_X * 2, by = HOME_BEAM_Y * 2;
  const bool rest = manT < 0.5f;                       // 坐火：多而亮
  const int n = rest ? H_SPK_N : H_SPK_N / 2;
  const int kMax = rest ? 15 : 9;
  for (int i = 0; i < n; i++) {
    const int x = bx + hSpkPts[i][0] + (int)(sinf(now * 0.00052f + i * 2.3f) * 3.0f);
    const int y = by + hSpkPts[i][1] + (int)(sinf(now * 0.00091f + i * 1.7f) * 4.0f);
    // 正弦负半周直接熄灭：读起来是"闪"，比整体明暗呼吸更灵
    const float tw = sinf(now * (0.0045f + (i & 3) * 0.0012f) + i * 2.399f);
    if (tw <= 0.2f) continue;
    const float q = (tw - 0.2f) * 1.25f;
    const int k = (int)(kMax * q * q * boost + 0.5f);
    if (k <= 0) continue;
    const uint16_t c = q > 0.85f ? H_SPECTRAL_HI : ((i & 3) ? H_HOLY : H_DUST);
    const int r = q > 0.6f ? 2 : 1;
    hAddEllipse(x, y, r, r, c, k);
  }
}

// 光尘 + 赐福火光：只动这两层，画完把包围盒交给局部重绘用。
// manT = 0 坐着（坐火：更亮、更高、火苗更大），1 站着（未坐火：暗一档、矮一截、火苗小一号）。
static void hEffects(unsigned long now, float boost, float manT) {
  const int bx = HOME_BEAM_X * 2, by = HOME_BEAM_Y * 2;
  const int lit = (int)(16.0f * (1.0f - 0.44f * manT) + 0.5f);     // 亮度档位 16 → 9（v2.3 原来只到 12）
  const int lift = (int)(6.0f * (1.0f - 0.55f * manT) + 0.5f);     // 光心离地高度 6 → 2.7
  const int dustTop = (int)(H_DUST_TOP_SIT + (H_DUST_TOP_STAND - H_DUST_TOP_SIT) * manT);
  const int fw = (int)(34.0f * (1.0f - 0.41f * manT) + 0.5f);      // 光晕 34×12 → 20×7（v2.3）
  const int fh = (int)(12.0f * (1.0f - 0.42f * manT) + 0.5f);
  // 火光呼吸
  const float breath = 0.75f + 0.25f * sinf(now * 0.0011f);
  const int k = (int)((1.5f + 1.5f * breath) * boost * lit / 16.0f + 0.5f);
  hAddEllipse(bx, by - lift, fw, fh, H_AMBER, k);
  hAddEllipse(bx, by - lift - 6, (fw * 15 + 17) / 34, (fh * 7 + 6) / 12, H_HOLY, k);
  if (boost > 1.05f) {                                    // 切换闪光（半径必须留在包围盒内）
    const int r = 20 + (int)(12 * (boost - 1.0f) / 0.6f);
    hAddEllipse(bx, by, r, r / 4, H_SPECTRAL_HI, (int)((boost - 1.0f) * 10));
  }
  // 光尘：加色点，压在亮天空上也只会更亮
  const int dustN = manT > 0.5f ? H_DUST_N / 2 : H_DUST_N;
  for (int i = 0; i < dustN; i++) {
    const float ph = fmodf(i / (float)dustN + now * 0.00009f, 1.0f);
    const int y = by - (int)(ph * dustTop);
    const float spread = 6 + ph * 26;
    const int x = bx + (int)(sinf(i * 2.7f + ph * 7.5f + now * 0.0011f) * spread);
    const float fade = 1.0f - ph;
    const int dk = (int)(7 * fade * fade * boost);
    if (dk <= 0) continue;
    const int r = ph < 0.3f ? 2 : 1;
    hAddEllipse(x, y, r, r, (i % 4) ? H_DUST : H_HOLY, dk);
  }
  hBlessSparks(now, boost, manT);
  hBox[0] = bx - H_FX_SPAN - 4;
  hBox[1] = by - H_FX_TOP - 4;
  hBox[2] = bx + H_FX_SPAN + 4;
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
static bool   hSnapOnce = false;            // 滑动合成要静态落点：这一次直接落地，不播过渡

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

// 整帧：画面 → 马粒子 → 赐福火光与光尘 → 浮层
static void hDrawFull(unsigned long now) {
  hScene();
  hHorseSparks(hHrsProgress(hT));          // 两端它自己会跳过，这里不再判一次
  hEffects(now, hBoost, hManProgress(hT));
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
  const float target = (st == WAIT_READY) ? 1.0f : 0.0f;
  // 进度状态机（三种情况互斥）：
  //   1. 滑动落点 hSnapOnce：必须是一张静态目标图，直接落地；
  //   2. 正在动：目标没变就继续推进，目标改回去就原路退回——画面从此刻的实际进度接着走；
  //   3. 没在动且目标与屏上不同：朝目标开始走。
  // 人站 / 马在 与 hT 的关系只由 hManProgress / hHrsProgress 决定，反向走自然就是
  // “马先散、人后坐”。
  if (hSnapOnce) {
    hSnapOnce = false;
    hDir = 0;
    hT = target;
  } else if (hDir != 0) {
    if ((hDir > 0) != (target > 0.5f)) { hDir = -hDir; hTAt = millis(); }   // v2.2 掉头时重取时基
  } else if (fabsf(hT - target) > 0.001f) {
    hDir = (target > hT) ? 1 : -1;
    hTAt = millis();
  }
  if (changed) {                                     // 换状态：赐福处闪一下
    hBoost = 1.6f;
    hBoostAt = millis();
  } else if (hDir == 0) {
    hBoost = 1.0f;
  }
  hInfoOn = false;
  hFrameAt = millis();
#if DEBUG_SERIAL
  Serial.printf("HOME st=%d changed=%d t=%.2f dir=%d page=%d on=%d sliding=%d\n",
                st, (int)changed, hT, (int)hDir, page, (int)onWaitScreen, (int)sliding);
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
  if (hDir != 0) {                                   // 按时间推进，方向可正可反
    unsigned long dt = now - hTAt;
    hTAt = now;
    if (dt > 100) dt = 100;                          // 浮层冻住 / 卡过帧：别一下跳到对面
    hT += hDir * (float)dt / (float)HOME_SWITCH_MS;
    if (hT >= 1.0f) {                                // 到已连接：整帧收尾
      hT = 1.0f;
      hDir = 0;
      hFullNext = true;
      catForce = true;
    } else if (hT <= 0.0f) {                         // 退回到未连接
      hT = 0.0f;
      hDir = 0;
      hFullNext = true;
      catForce = true;
    }
  }
  const bool full = hFullNext || hDir != 0;
  const int gap = hDir != 0 ? 33 : (hBoost > 1.0f ? 60 : HOME_FRAME_MS);
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
    hEffects(now, hBoost, hManProgress(hT));
  }
  needFlush = true;
  frameIsMap = false;
}
