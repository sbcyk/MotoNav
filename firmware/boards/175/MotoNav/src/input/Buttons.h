#pragma once
// 两个侧键：BOOT(GPIO0) 与 PWR(AXP2101 电源键短按)。
// BOOT：短按翻页，长按 2 秒回骑行前首页。PWR：短按反向翻页。
// 由 MotoNav.ino 在 PageNavigation.h 之后包含，仅编译一次：本文件用到 HomePage.h 的
// page/wxDetail、PageNavigation.h 的 slide* 与 drag* 状态，这些都在它之前定义。

// 方向配置：装上后觉得左右反了，把 1 改成 0
#define BTN_BOOT_GOES_RIGHT 1

// PWR 开关：只想验证 BOOT 时改 0，完全不碰 PMU 寄存器
#define BTN_PWR_ENABLED 1

#define BTN_DEBOUNCE_MS    25      // 抖动窗口
#define BTN_LONG_MS        2000    // 长按判定
#define BTN_PWR_GUARD_MS   120     // 两次 PWR 短按的最小间隔
#define BTN_PWR_POLL_MS    30      // PMU 中断状态轮询间隔，避免每轮循环都发 I2C
#define BTN_SLIDE_MS       220     // 按键换页时长：比完整滑动（约 400ms）短，按下就有反馈
#define BTN_HOME_SLIDE_MS  260     // 回首页略慢：跨越的层级比翻页多

// AXP2101 中断：INTEN2 = 0x41 使能，INTSTS2 = 0x49 状态
// XPowersLib 里 PKEY_SHORT_IRQ = _BV(11)，落在第 2 组寄存器的 bit3
#define BTN_PMU_INTEN2     0x41
#define BTN_PMU_INTSTS2    0x49
#define BTN_PKEY_SHORT     0x08
#define BTN_PMU_CLR_ALL    0xFF    // 写 1 清除，不是写 0

// 参数始终参与求值，关掉日志时只是条件为常量 0，不会让调用处的变量变成未使用告警
#ifndef DEBUG_SERIAL
#define DEBUG_SERIAL 0
#endif
#define BTN_LOG(...) do { if (DEBUG_SERIAL) Serial.printf(__VA_ARGS__); } while (0)

static bool     btnArmed = false;
static bool     btnDown = false;
static bool     btnLongFired = false;
static uint32_t btnDownAt = 0;
static uint32_t btnEdgeAt = 0;
#if BTN_PWR_ENABLED
static uint32_t btnPwrAt = 0;
static uint32_t btnPwrPollAt = 0;

static inline void btnPmuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(PMU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}
#endif

// 页面环：音乐(2) - 主页(0) - 天气(1)，与 HomePage.h 的 drawPageDots 一致
static const int BTN_RING[3] = {2, 0, 1};

static int btnRingIndex(int p) {
  for (int i = 0; i < 3; i++) if (BTN_RING[i] == p) return i;
  return -1;
}

// 首页等待态。v2.1 起直接用 homeLinkReady()：主循环的状态触发、滑动落点、
// 状态栏小绿点用的都是同一个判定，不需要再靠注释提醒两处保持一致。
static int btnHomeWaitState() {
  return homeLinkReady() ? WAIT_READY : WAIT_NOLINK;
}

// 复用拖拽换页的动画管线。slideCompose/slideCommit 读的是全局 drag* 状态，
// 所以这里按 dragMove/dragEnd 的顺序把状态补齐。返回 false 表示 PSRAM 不足，没动画。
static bool btnStartSlide(int target, int detail, int sign, int ms) {
  if (!slidePrepare(target, detail)) {
    BTN_LOG("BTN slide: psram alloc failed, %d -> %d skipped\n", page, target);
    return false;
  }
  dragTarget = target;
  dragWeatherDetail = detail;
  dragHoriz = true;
  dragSign = sign;
  dragP = 0; dragV = 0; dragT = millis();
  dragging = true;
  slideAnimate(0, LCD_WIDTH, ms);
  slideCommit();
  return true;
}

// 长按回首页：清导航状态后用换页动画过渡，避免整屏瞬间切换
static void btnGoHome() {
  if (callOn || pairOn) return;
  if (sliding) return;                             // 正在滑：这一帧不接受新动作
  if (dragging) dragAbort();
  if (fxOn) stopArriveFx();                        // 到达特效还在放：主循环会继续往 page 0 上画，必须先停
  const int from = page;
  const bool alreadyHome = (from == 0 && !inNav);
  resetNavState();                                 // 先清，renderPage(0) 才会画首页而不是导航帧
  if (!alreadyHome) {
    // 从音乐页回来让主页从右侧进，从天气页/导航画面回来从左侧进
    const int dir = (from == 2) ? -1 : 1;
    if (btnStartSlide(0, 0, dir, BTN_HOME_SLIDE_MS)) {
      BTN_LOG("BTN home from page %d\n", from);
      return;
    }
  }
  page = 0;
  wxDetail = 0;
  drawWaiting(btnHomeWaitState());
  needFlush = true;
}

// sign: -1 = 切到右侧页面（主页→天气），+1 = 切到左侧页面（主页→音乐）
static bool btnPage(int sign) {
  if (sliding || dragging) return false;
  if (callOn || pairOn || fxOn) return false;
  int target, dir = sign;
  if (page == 1 && wxDetail != 0) {
    target = 0;                                    // 天气详情页先回主页面，主页从左侧进来
    dir = 1;
  } else {
    const int i = btnRingIndex(page);
    if (i < 0) return false;
    target = BTN_RING[(i + (sign < 0 ? 1 : -1) + 3) % 3];
  }
  if (target == page) return false;
  const int from = page;
  if (!btnStartSlide(target, 0, dir, BTN_SLIDE_MS)) return false;
  BTN_LOG("BTN page %d -> %d\n", from, target);
  return true;
}

void buttonsInit() {
  pinMode(BTN_BOOT, INPUT_PULLUP);
#if BTN_PWR_ENABLED
  // 只打开 PWRKEY 短按的中断使能位，不改电源行为
  const int en = pmuRead(BTN_PMU_INTEN2);
  if (en >= 0 && !(en & BTN_PKEY_SHORT)) btnPmuWrite(BTN_PMU_INTEN2, (uint8_t)(en | BTN_PKEY_SHORT));
  if (pmuRead(BTN_PMU_INTSTS2) >= 0) btnPmuWrite(BTN_PMU_INTSTS2, BTN_PMU_CLR_ALL);   // 清开机残留
  BTN_LOG("BTN pwr irq enable: %d -> %d\n", en, en >= 0 ? (en | BTN_PKEY_SHORT) : -1);
#endif
}

// 开机画面播完再武装：BOOT 按住上电会进下载模式，启动阶段不能读它
void buttonsArm() {
  btnArmed = true;
  btnDown = (digitalRead(BTN_BOOT) == LOW);
  btnDownAt = millis();
  btnEdgeAt = btnDownAt;
  btnLongFired = btnDown;                          // 开机时就按着：不补触发长按
}

#if BTN_PWR_ENABLED
static void btnPwrPoll(uint32_t now) {
  if (now - btnPwrPollAt < BTN_PWR_POLL_MS) return;   // 限流：I2C 和电量轮询共用一条总线
  btnPwrPollAt = now;
  const int st = pmuRead(BTN_PMU_INTSTS2);
  if (st < 0 || !(st & BTN_PKEY_SHORT)) return;
  btnPmuWrite(BTN_PMU_INTSTS2, BTN_PMU_CLR_ALL);   // 先清状态，否则每轮都会重复触发
  if (now - btnPwrAt < BTN_PWR_GUARD_MS) return;
  btnPwrAt = now;
  BTN_LOG("BTN pwr short\n");
  btnPage(BTN_BOOT_GOES_RIGHT ? 1 : -1);
}
#endif

void buttonsPoll() {
  const uint32_t now = millis();
  if (!btnArmed) return;                           // PWR 也等开机动画结束再响应

#if BTN_PWR_ENABLED
  btnPwrPoll(now);
#endif

  const bool raw = (digitalRead(BTN_BOOT) == LOW);
  if (raw != btnDown) {
    if (now - btnEdgeAt < BTN_DEBOUNCE_MS) return;
    btnEdgeAt = now;
    btnDown = raw;
    if (raw) {
      btnDownAt = now;
      btnLongFired = false;
    } else if (!btnLongFired && now - btnDownAt < BTN_LONG_MS) {
      btnPage(BTN_BOOT_GOES_RIGHT ? -1 : 1);       // 短按在松手时执行，才能和长按区分
    }
    return;
  }
  if (btnDown && !btnLongFired && now - btnDownAt >= BTN_LONG_MS) {
    btnLongFired = true;
    btnGoHome();
  }
}
