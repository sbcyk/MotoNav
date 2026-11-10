#pragma once
// 主页信息层：金环 + 四向星芒 + 时间 / 日期 / 星期 / 地点 / 天气。v2.4 新增。
//
// 版式取自参考图：环贴着圆边走、四向星芒落在 12/3/6/9；时间最大居中，日期紧跟，
// 地点靠左下带一个菱点、天气靠右下。中间那条横带让给王城，不压主景。
//
// 可读性不靠描边：文字压在一层**椭圆柔和压暗**上——中心暗、边缘按 (1-d²)² 淡出，
// 从哪儿开始变暗看不出来，也就没有"贴了一块板子"的感觉。金色系配色跟画面里
// 唯一的光源同色，所以字是"亮在画上"的，不是"盖上去"的。
//
// 这些数据全都来自手机侧（时间走 #TIME，天气 #W，地点 #WL），所以只能画在
// WeatherPage 之后——那里的 wxIcon / wxTemp / wxPlace 才可见。HomePage.h 排在它前面，
// 不能直接引用，只能反过来由它调用这里。

// 依赖：homeClock（HomeClock.h）、hT / hInfoOn / CX / onWaitScreen / page / inNav（HomePage.h）、
// wxHave / wxIcon / wxTemp / wxPlace / drawWxIcon / drawTemp（WeatherPage.h）。
// 这些全部由 MotoNav.ino 在本文 include 之前按顺序引入，这里不再重复 include ——
// 用不同相对路径再引一次 HomeClock.h 会让编译器当成两个文件，直接报类重定义。

#define HB_GOLD_TXT   0xF6F5   // 暖白金：时间、温度
#define HB_GOLD_SUB   0xD5F1   // 暗金：日期、地点、星期
#define HB_GOLD_RING  0xCD04   // 环
#define HB_RING_R     224      // 环半径：星芒半高 7，r 必须 <= 225，否则 12/6 点尖端会画出屏
#define HB_SPARK_R    7        // 星芒半高；fillTriangle 不裁剪，越界会写坏画布后面的内存

#define HB_TIME_Y     52
#define HB_DATE_Y     128
#define HB_ROW_Y      156      // 地点 / 天气同一行

// 椭圆柔和压暗。kMax 是中心处的压暗档位（0~16），乘 (1-d²)² 往外淡掉。
static void hSoftDim(int cx, int cy, int rx, int ry, int kMax) {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) return;
  for (int y = cy - ry; y <= cy + ry; y++) {
    if (y < 0 || y >= LCD_HEIGHT) continue;
    const float dy = (float)(y - cy) / (float)ry;
    uint16_t *row = fb + (size_t)y * LCD_WIDTH;
    for (int x = cx - rx; x <= cx + rx; x++) {
      if (x < 0 || x >= LCD_WIDTH) continue;
      const float dx = (float)(x - cx) / (float)rx;
      const float d2 = dx * dx + dy * dy;
      if (d2 >= 1.0f) continue;
      const float fall = 1.0f - d2;
      const int k = (int)(kMax * fall * fall + 0.5f);
      if (k <= 0) continue;
      const uint16_t p = row[x];
      const int keep = 16 - k;
      row[x] = (uint16_t)(((((p >> 11) & 31) * keep >> 4) << 11) |
                          ((((p >> 5) & 63) * keep >> 4) << 5) |
                          (((p & 31) * keep >> 4)));
    }
  }
}

// 金环 + 四向星芒。环用极坐标逐点铺，两点一像素，不会有锯齿断口。
static void hDrawRing() {
  const float r = HB_RING_R;
  const int steps = 900;
  for (int i = 0; i < steps; i++) {
    const float t = (float)i * 2.0f * PI / steps;
    aaDisc(CX + cosf(t) * r, CX + sinf(t) * r, 1.3f, HB_GOLD_RING);
  }
  for (int i = 0; i < 4; i++) {                     // 12 / 3 / 6 / 9 四向星芒
    const float t = (float)i * PI * 0.5f;
    const int x = (int)(CX + cosf(t) * r + 0.5f);
    const int y = (int)(CX + sinf(t) * r + 0.5f);
    gfx->fillTriangle(x, y - HB_SPARK_R, x + 5, y, x, y + HB_SPARK_R, HB_GOLD_TXT);
    gfx->fillTriangle(x, y - HB_SPARK_R, x - 5, y, x, y + HB_SPARK_R, HB_GOLD_TXT);
  }
}

static void hTextAt(const char *s, int x, int y, int size, uint16_t c) {
  gfx->setTextSize(size);
  gfx->setTextColor(c);
  gfx->setCursor(x, y);
  gfx->print(s);
}

// 0 = 周日。Sakamoto 那套，不引 time.h。
static int hDayOfWeek(int y, int m, int d) {
  static const int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
  if (m < 3) y -= 1;
  return (y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7;
}

static const char *const H_WD[7] = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"};

// 画信息层。hT 不到 1 表示还没连上（或正在退回），整层留白——数据本来就来自手机。
// 浮层展开时也让位：浮层自带卡片，再叠一层就脏了。
void drawHomeBand(unsigned long now) {
  if (hT < 0.999f || hInfoOn) return;
  if (page != 0 || inNav || !onWaitScreen) return;

  hDrawRing();
  hSoftDim(CX, 88, 198, 66, 7);                     // 时间 + 日期那块
  hSoftDim(CX, HB_ROW_Y + 8, 168, 22, 5);           // 地点 / 天气那一行

  char time[6], date[11];
  const bool ok = homeClock.format(now, time, date);
  printCentered(ok ? time : "--:--", CX, HB_TIME_Y, 8, HB_GOLD_TXT);

  if (ok) {
    HomeClock::Reading rd;
    char line[24];
    if (homeClock.read(now, rd)) {
      snprintf(line, sizeof(line), "%s  %s", date, H_WD[hDayOfWeek(rd.year, rd.month, rd.day)]);
    } else {
      snprintf(line, sizeof(line), "%s", date);
    }
    printCentered(line, CX, HB_DATE_Y, 2, HB_GOLD_SUB);
  } else {
    printCentered("---- -- --", CX, HB_DATE_Y, 2, HB_GOLD_SUB);
  }

  // 地点：左侧一个菱点 + 文字。没收到 #WL 就整段不画，不留空图标。
  if (wxPlace[0]) {
    const int lx = CX - 132;
    gfx->fillTriangle(lx + 5, HB_ROW_Y + 2, lx + 9, HB_ROW_Y + 8, lx + 5, HB_ROW_Y + 14, HB_GOLD_SUB);
    gfx->fillTriangle(lx + 5, HB_ROW_Y + 2, lx + 1, HB_ROW_Y + 8, lx + 5, HB_ROW_Y + 14, HB_GOLD_SUB);
    hTextAt(wxPlace, lx + 14, HB_ROW_Y, 2, HB_GOLD_SUB);
  }

  // 天气：图标在左、温度右对齐到 CX+128。没数据整段不画——不写 "--°" 骗人。
  if (wxHave) {
    drawWxIcon(wxIcon, CX + 74, HB_ROW_Y + 8, 12);
    char t[8];
    snprintf(t, sizeof(t), "%d", wxTemp);
    const int tw = (int)strlen(t) * 6 * 2;
    hTextAt(t, CX + 128 - tw - 6, HB_ROW_Y, 2, HB_GOLD_TXT);
    aaDisc(CX + 126, HB_ROW_Y + 6, 2.2f, HB_GOLD_TXT);   // 度数小圈
  }
}
