# MotoNav

iPhone + ESP32-S3 圆屏导航。手机端用高德 SDK 渲染地图、抓图压成 4bit 调色板 + RLE，经 BLE 推到 1.75 英寸圆屏；圆屏只做解码与绘制，不参与导航计算。

## 分工

| 端 | 负责 |
| --- | --- |
| iPhone | 地图渲染、选路、搜索、收藏、轨迹、语音、媒体控制 |
| 圆屏 | 收图解码、导航页绘制、天气与来电页、侧键交互、首页动画 |

手机端是导航引擎，圆屏是显示器。改地图内容、路线、语音 → 改手机端；改界面、动画、图标、按键 → 改固件。两端共用一套 BLE 协议，改协议字段必须同时改两端。

## 硬件

| 项 | 参数 |
| --- | --- |
| 板子 | Waveshare ESP32-S3-Touch-AMOLED-1.75（圆屏） |
| MCU | ESP32-S3，32MB Flash，8MB OPI PSRAM，分区 `app5M_fat24M_32MB` |
| 屏幕 | CO5300 QSPI，466×466 |
| 触摸 | CST92xx（I2C） |
| 电源 | AXP2101 |

只适用这个板型。1.75C、1.85B、M5Stack 不能刷本仓库的镜像。

## 功能

**iPhone 端**（Swift + CocoaPods，最低 iOS 15，四栏目：导航、轨迹、设备、我的）

- 导航：地图渲染、抓图下推、剩余距离与路名、语音播报
- 路线规划：三条方案画在同一张图上，点选只换高亮；起终点两行都可点改
- 搜索：输入停顿自动查，结果走浮层，不把下面卡片顶走
- 收藏：自定义标签，标签自动收成筛选条
- 轨迹：本月里程与次数、最近一次缩略图与耗时，点进详情
- 圆屏设置：导航信息 / 地图与路线 / 夜间与弯道，开机动画 / 音乐与歌词 / 屏幕方向 / 亮度

**圆屏端**（ESP32-S3）

- 首页「赐福」：未连接独坐、已连接起身牵马，两态过渡带粒子；连上后叠一层常驻信息带（时间、日期、地点、天气）
- 导航主界面、天气页、来电页、到达特效、配对页
- 触摸 + BOOT / PWR 两个侧键；音乐走 HID over GATT（Apple AMS）

## 目录

| 路径 | 内容 |
| --- | --- |
| `ios/` | iPhone App 源码，Swift + CocoaPods（高德 AMapNavi / AMapSearch） |
| `firmware/` | 固件源码、烧录包生成、打包脚本 |
| `docs/` | 技术文档、需求清单、CI 说明 |
| `scripts/` | iOS 打包、首页画面生成 |
| `android/` | 更早的安卓版源码，仅存档，不随新功能维护 |

## 构建

**iOS**（需 macOS + Xcode + CocoaPods 1.16.2）

```sh
bash build-ios.sh              # 产出 output/ios/*.ipa（未签名）
```

或在 Actions 里手动跑 `iOS Quick Build (unsigned IPA)`。IPA 需自行签名安装，免费签名通常 7 天续签一次。

首次运行要去高德开放平台申请 iOS Key（绑定签名后的 Bundle ID），填在 App 设置页；不填时搜索框下方会常驻提示。

**固件**（需 arduino-cli + Espressif ESP32 Arduino Core 3.3.10）

```sh
python3 firmware/build.py      # 产出 firmware/dist/175/panel0/
```

FQBN 与版本同步要求见 `AGENTS.md`。

**烧录**：解压生成好的 Windows / macOS 一键包，已有同分区固件时选「应用升级」写 `0x10000`；首次安装、救砖、从 16MB 分区旧固件升级必须整片刷，会清 NVS。

## 文档

| 内容 | 位置 |
| --- | --- |
| 规范、架构、构建约束、改动点 | `AGENTS.md` |
| 协议、时序、地图管线 | `docs/MotoNav-技术文档.md` |
| 需求、进度、验收 | `docs/需求清单.md` |
| 版本改动 | `CHANGELOG.md` |
| iOS CI 用法 | `docs/IOS-CI-GUIDE.md` |
| 媒体键协议 | `docs/BLE-HID.md` |

## 来源

本项目 fork 自 [CharlesXu/MotoNav](https://github.com/CharlesXu/MotoNav)，在此基础上重做 iOS 端并继续开发圆屏固件；iOS 界面布局参考 [coolcoolmanman-design/MotoNav](https://github.com/coolcoolmanman-design/MotoNav)，参考范围与保留项见 [UI-SOURCE-NOTICE.md](ios/UI-SOURCE-NOTICE.md)。版本号与上游独立，改动历史见 `CHANGELOG.md`。

## 许可

非商业使用，见 `LICENSE.md`。第三方 SDK、库与素材的许可见 `licenses/`。

行驶中不要操作设备。路线、图标均不能代替现场信号与标志。
