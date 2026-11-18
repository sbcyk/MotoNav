#pragma once
// 车道图标缓存和绘制。由 MotoNav.ino 按依赖顺序包含，仅编译一次。
// ================= 车道 =================

// 高德车道方向码 → 方向位：1 直行，2 左转，4 右转，8 左掉头（左转掉头），16 右掉头（右转掉头）
// v2.8 编码含义逐条对照高德导航 SDK 文档（AMapNaviDriveDataRepresentable 的 showLaneBackInfo:laneSelectInfo:）：
//   0 直行 / 1 左转 / 2 直行和左转 / 3 右转 / 4 直行和右转 / 5 左转掉头 / 6 左转和右转 /
//   7 直行和左转和右转 / 8 右转掉头 / 9 直行和左转掉头 / 10 直行和右转掉头 / 11 左转和左转掉头 /
//   12 右转和右转掉头 / 13 直行、左侧道路变宽 / 14 左转和左转掉头、左侧变宽 /
//   16 直行和左转和左掉头 / 17 右转和左掉头 / 18 左转和左掉头和右转 / 19 直行和右转和左掉头 /
//   20 左转和右掉头 / 21 公交车道 / 23 可变车道
//   255 只出现在推荐串里，表示规划的路线不走这条车道（App 端转成 f）
uint8_t laneFlags(uint8_t code) {
  switch (code) {
    case 0:  return 1;
    case 1:  return 2;
    case 2:  return 1 | 2;
    case 3:  return 4;
    case 4:  return 1 | 4;
    case 5:  return 8;
    case 6:  return 2 | 4;
    case 7:  return 1 | 2 | 4;
    case 8:  return 16;
    case 9:  return 1 | 8;
    case 10: return 1 | 16;
    case 11: return 2 | 8;
    case 12: return 4 | 16;
    case 13: return 1;                                   // v2.8 直行、左侧变宽
    case 14: return 2 | 8;                               // v2.8 左转和左转掉头、左侧变宽
    case 16: return 1 | 2 | 8;                           // v2.8
    case 17: return 4 | 8;                               // v2.8
    case 18: return 2 | 8 | 4;                           // v2.8
    case 19: return 1 | 4 | 8;                           // v2.8
    case 20: return 2 | 16;                              // v2.8
    case 21: return 1;                                   // v2.8 公交车道：方向未知，按直行画
    case 23: return 1;                                   // v2.8 可变车道：方向未知，按直行画
    default: return 1;                                   // 没见过的码按直行，宁可画一条也不留空
  }
}

// v3.4 车道图标改成抗锯齿：先把线段/三角形“记录”下来（和大箭头同一套），按每个像素的覆盖率
//      算好颜色和透明度存进车道缓存；车道不变就直接用缓存，每帧和地图混合（边缘平滑，拐角是圆弧）
#define LANE_BUF_W 320
#define LANE_BUF_H 44
uint16_t *laneCol = nullptr;
uint8_t *laneA = nullptr;
int laneBX = 0, laneBY = 0, laneBW = 0, laneBH = 0;
uint32_t laneHash = 0;

// v2.8 车道条尺寸：地图页 HUD 和"别让电子眼图标压上来"的占位框共用一套，两处公式必须一致
#define LANE_MAP_H      36
#define LANE_MAP_MAXW   250
#define LANE_PAGE_H     36
#define LANE_PAGE_MAXW  330

// v2.8 配色：非推荐车道原来用 C_DIM(#6B6B6B)，5 条挤在一起时数不清有几条；
//      推荐车道除了箭头变白，再垫一块琥珀色底，一眼看出该走哪条
#define C_LANE_OFF 0x8C71    // #8C8C8C 能走、但不是规划要走的那条
#define C_LANE_SEP 0x4228    // #444444 分隔虚线（原来 #333333 太暗）
#define C_LANE_HL  0xF623    // 推荐车道底色（C_YELLOW）

int laneMapStripW() {
  if (laneN <= 0) return 0;
  return (int)(fminf(36.0f * LANE_MAP_H / 32, (float)LANE_MAP_MAXW / laneN) * laneN);
}

// 画一段圆弧（用几小段线连起来）；角度：0 = 朝右，90 = 朝下（屏幕坐标）
void arcLine(float ox, float oy, float r, float a0, float a1, float w, uint16_t col) {
  const int N = 4;
  float px = ox + r * cosf(a0 * PI / 180), py = oy + r * sinf(a0 * PI / 180);
  for (int i = 1; i <= N; i++) {
    float a = (a0 + (a1 - a0) * i / N) * PI / 180;
    float nx = ox + r * cosf(a), ny = oy + r * sinf(a);
    thickLine(px, py, nx, ny, w, col);
    px = nx; py = ny;
  }
}

// 在一条车道里画方向符号（只记录图形）；cx = 车道中心 x，y0 = 顶部，h = 高度
// v2.8 sq = 横向收窄系数：车道多到 7、8 条时车道变窄，箭头臂按比例缩，免得压到隔壁
void drawLaneGlyph(float cx, float y0, float h, uint8_t flags, uint16_t col, float sq = 1.0f) {
  const float k = h / 32.0f;
  const float w = 5.0f * k, hs = 6.8f * k * sq;    // v2.8 线宽 4.6 → 5.0：远一点也看得出是箭头
  const float base = y0 + h, top = y0 + 3 * k;
  if (flags & 1) {                                         // 直行
    thickLine(cx, base, cx, top + hs, w, col);
    arrowHead(cx, top + hs, 0, hs, col);
  }
  if (flags & (2 | 4)) {                                   // 左转/右转：竖线 → 圆弧 → 横线 → 箭头
    const float rr = 4.5f * k, arm = 9.0f * k * sq;
    float cy = y0 + h * ((flags & 1) ? 0.6f : 0.42f);     // 和直行合在一起时拐点放低
    thickLine(cx, base, cx, cy + rr, w, col);
    if (flags & 4) {
      arcLine(cx + rr, cy + rr, rr, 180, 270, w, col);
      thickLine(cx + rr, cy, cx + arm, cy, w, col);
      arrowHead(cx + arm, cy, 90, hs, col);
    }
    if (flags & 2) {
      arcLine(cx - rr, cy + rr, rr, 0, -90, w, col);
      thickLine(cx - rr, cy, cx - arm, cy, w, col);
      arrowHead(cx - arm, cy, -90, hs, col);
    }
  }
  if (flags & (8 | 16)) {                                  // 掉头：竖线 → 半圆 → 向下 + 箭头
    const float u = 4.2f * k, ut = top + 6 * k + u, down = y0 + h * 0.62f;
    thickLine(cx, base, cx, ut, w, col);
    if (flags & 8) {
      arcLine(cx - u, ut, u, 0, -180, w, col);
      thickLine(cx - 2 * u, ut, cx - 2 * u, down - hs, w, col);
      arrowHead(cx - 2 * u, down - hs, 180, hs, col);
    }
    if (flags & 16) {
      arcLine(cx + u, ut, u, 180, 360, w, col);
      thickLine(cx + 2 * u, ut, cx + 2 * u, down - hs, w, col);
      arrowHead(cx + 2 * u, down - hs, 180, hs, col);
    }
  }
  if (!(flags & (1 | 2 | 4 | 8 | 16))) {                   // 没有方向位时画直行
    thickLine(cx, base, cx, top + hs, w, col);
    arrowHead(cx, top + hs, 0, hs, col);
  }
}

// 把记录好的车道图形算成“颜色 + 透明度”存进缓存
void laneRender() {
  float bx0 = 1e9f, by0 = 1e9f, bx1 = -1e9f, by1 = -1e9f;
  for (int i = 0; i < primN; i++) {
    bx0 = fminf(bx0, prims[i].x0); by0 = fminf(by0, prims[i].y0);
    bx1 = fmaxf(bx1, prims[i].x1); by1 = fmaxf(by1, prims[i].y1);
  }
  laneBX = max(0, (int)floorf(bx0)); laneBY = max(0, (int)floorf(by0));
  laneBW = min(LANE_BUF_W, (int)ceilf(bx1) + 1 - laneBX);
  laneBH = min(LANE_BUF_H, (int)ceilf(by1) + 1 - laneBY);
  if (laneBX + laneBW > LCD_WIDTH) laneBW = LCD_WIDTH - laneBX;
  if (laneBY + laneBH > LCD_HEIGHT) laneBH = LCD_HEIGHT - laneBY;
  if (laneBW <= 0 || laneBH <= 0) { laneBW = laneBH = 0; return; }
  for (int y = 0; y < laneBH; y++) {
    float py = laneBY + y + 0.5f;
    for (int x = 0; x < laneBW; x++) {
      float px = laneBX + x + 0.5f;
      float r = 0, g = 0, b = 0, A = 0;                  // 从透明开始，按顺序叠加每个图形
      for (int i = 0; i < primN; i++) {
        const Prim &p = prims[i];
        if (px < p.x0 || px > p.x1 || py < p.y0 || py > p.y1) continue;
        float a = primAlpha(p, px, py);
        if (a <= 0) continue;
        float cr = ((p.col >> 11) & 0x1F) / 31.0f, cg = ((p.col >> 5) & 0x3F) / 63.0f, cb = (p.col & 0x1F) / 31.0f;
        r += (cr - r) * a; g += (cg - g) * a; b += (cb - b) * a; A += (1 - A) * a;
      }
      int k = y * LANE_BUF_W + x;
      if (A < 0.01f) { laneA[k] = 0; continue; }
      r /= A; g /= A; b /= A;                              // 去掉透明度，得到纯颜色
      laneCol[k] = ((uint16_t)lroundf(fminf(r, 1) * 31) << 11) | ((uint16_t)lroundf(fminf(g, 1) * 63) << 5) | (uint16_t)lroundf(fminf(b, 1) * 31);
      laneA[k] = (uint8_t)lroundf(fminf(A, 1) * 255);
    }
  }
}

void drawLanes(int y0) { drawLanesAt(CX, y0, LANE_PAGE_MAXW, LANE_PAGE_H); }

// 在 framebuffer 上叠一块圆角半透明色块（alpha 0~255），只给车道底色用
void laneTintRect(int x, int y, int w, int h, int r, uint16_t col, int alpha) {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb || w <= 0 || h <= 0 || alpha <= 0) return;
  if (x < 0) { w += x; x = 0; }
  if (y < 0) { h += y; y = 0; }
  if (x + w > LCD_WIDTH) w = LCD_WIDTH - x;
  if (y + h > LCD_HEIGHT) h = LCD_HEIGHT - y;
  if (w <= 0 || h <= 0) return;
  if (r > h / 2) r = h / 2;
  if (r > w / 2) r = w / 2;
  for (int j = 0; j < h; j++) {
    int inset = 0;
    if (r > 0 && j < r) {                                // 上下两个圆角：按圆的弦长往外缩
      float dy = r - j - 0.5f;
      inset = r - (int)(sqrtf((float)r * r - dy * dy) + 0.5f);
    } else if (r > 0 && j >= h - r) {
      float dy = j - (h - r) + 0.5f;
      inset = r - (int)(sqrtf((float)r * r - dy * dy) + 0.5f);
    }
    if (inset < 0) inset = 0;
    if (inset * 2 >= w) continue;
    uint16_t *row = fb + (y + j) * LCD_WIDTH + x;
    for (int i = inset; i < w - inset; i++) row[i] = blend565(row[i], col, alpha);
  }
}

// v2.1 在指定位置画车道：cx = 中心 x，maxW = 最大总宽，h = 高度
void drawLanesAt(float centerX, float y0, float maxW, float h) {
  if (laneN <= 0) return;
  if (!laneCol) {
    laneCol = (uint16_t *)malloc(LANE_BUF_W * LANE_BUF_H * 2);
    laneA = (uint8_t *)malloc(LANE_BUF_W * LANE_BUF_H);
    if (!laneCol || !laneA) return;
  }
  float lw = fminf(36 * h / 32, maxW / laneN);
  float x0 = centerX - lw * laneN / 2;
  // v2.8 车道多的时候按比例收窄箭头横向尺寸（7、8 条时 lw 会被 maxW 压小）
  float sq = constrain(lw / (36.0f * h / 32), 0.55f, 1.0f);
  // 1. 记录所有车道的图形
  primN = 0; recIcon = true;
  for (int i = 0; i < laneN; i++) {
    float cx = x0 + lw * (i + 0.5f);
    bool rec = laneFr[i] != 0xF;
    drawLaneGlyph(cx, y0, h, laneFlags(laneBg[i]), C_LANE_OFF, sq);          // 底层：这条车道能走的方向
    if (rec) drawLaneGlyph(cx, y0, h, laneFlags(laneFr[i]), C_WHITE, sq);    // 推荐方向：白色压在上面
  }
  recIcon = false;
  // 2. 和上次一样就用缓存，否则重新计算
  uint32_t hs = 2166136261u;
  const uint8_t *bytes = (const uint8_t *)prims;
  for (size_t i = 0; i < sizeof(Prim) * primN; i++) { hs ^= bytes[i]; hs *= 16777619u; }
  hs ^= primN * 7919u;
  if (hs != laneHash) { laneRender(); laneHash = hs; }
  primN = 0;
  // 2.5 v2.8 推荐车道整条垫一块底色（连在一起的推荐车道合成一块，不切碎）
  for (int i = 0; i < laneN; ) {
    if (laneFr[i] == 0xF) { i++; continue; }
    int j = i;
    while (j + 1 < laneN && laneFr[j + 1] != 0xF) j++;
    int bx = rnd(x0 + lw * i) + 1;
    int bw = rnd(x0 + lw * (j + 1)) - bx - 1;
    laneTintRect(bx, rnd(y0) - 1, bw, rnd(h) + 2, 7, C_LANE_HL, 112);
    i = j + 1;
  }
  // 3. 和底下的画面按透明度混合
  uint16_t *fb = gfx->getFramebuffer();
  if (fb) {
    for (int y = 0; y < laneBH; y++) {
      uint16_t *dst = fb + (laneBY + y) * LCD_WIDTH + laneBX;
      const uint16_t *sc = laneCol + y * LANE_BUF_W;
      const uint8_t *sa = laneA + y * LANE_BUF_W;
      for (int x = 0; x < laneBW; x++) {
        uint8_t a = sa[x];
        if (!a) continue;
        dst[x] = a == 255 ? sc[x] : blend565(dst[x], sc[x], a);
      }
    }
  }
  // 4. 车道之间的虚线 + 上沿一条横杠（一眼能看出"车道条出现了"）
  for (int i = 1; i < laneN; i++)
    for (float y = y0; y < y0 + h; y += 8) gfx->drawFastVLine(rnd(x0 + lw * i), rnd(y), 4, C_LANE_SEP);
  gfx->fillRect(rnd(x0) - 4, rnd(y0) - 4, rnd(lw * laneN) + 8, 2, C_LANE_SEP);
}
