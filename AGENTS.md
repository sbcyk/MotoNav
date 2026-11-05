# MotoNav 项目说明

摩托车圆屏导航。手机端跑高德 SDK 渲染地图，截屏压缩后经 BLE 推到 ESP32 圆屏显示。ESP32 不做导航计算，只做解码和绘制。

本文档**随仓库维护**，和代码一起提交。改代码、改版本、改约定时同步更新，不要另存副本。

---

## 1. 代码与材料位置

| 项 | 位置 |
|---|---|
| 本仓库 | `github.com/sbcyk/MotoNav`，public。**main 是自己的开发主线**，2026-11-03 起不再只做上游镜像 |
| 仓库地址（SSH） | `git@github.com:sbcyk/MotoNav.git` |
| 深度技术文档 | 仓库内 `docs/MotoNav-技术文档.md`（933 行，14 章，协议逐条、时序、地图管线、侧载方案） |
| iOS CI 工作流 | 仓库内 `.github/workflows/ios-quick.yml`，用法见 `docs/IOS-CI-GUIDE.md` |
| 许可证 | 非商业，见 `LICENSE.md` |
| 提交身份 | **仅本仓库 local 配置**：`sbcyk <126747153+sbcyk@users.noreply.github.com>`，全局配置仍是公司邮箱，不要改全局 |

仓库规模（`git ls-files` 实测）：`firmware/` 790 个文件，`android/` 307，`ios/` 129，`docs/` 51，合计 1294。

### 工作范围：只做 iOS 端

手机端**只用 iOS**，`ios/` 是唯一要维护的客户端，`android/` 保留但不改动（不删、不编、不参考其新特性）。看到 `android/` 里的实现差异时，不要当成"需要同步修复的问题"。

两端共享的是 BLE 协议：改协议字段必须同时改 `firmware/` 和 `ios/`，`android/` 跟着上游走即可。

### 版本号：语义化版本，不跟上游走

版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)：`主版本号.次版本号.修订号`，**不加功能后缀**（后缀会让 `package_flasher.py` 的版本比对和 tag 对应关系变复杂）。

| 位 | 什么时候动 |
|---|---|
| 主版本号 | 不兼容改动：BLE 协议字段或分包格式变化、NVS 键改名、手机端必须同步升级的改动 |
| 次版本号 | 向后兼容的新功能：新页面、新动画、新按键行为 |
| 修订号 | 向后兼容的缺陷修复 |

上游编号是 `7.12.10-phone.8` 这类，那是上游的第几版，与本仓库无关。上游血缘靠 tag `upstream-phone.8`（指向 `e122516`）和提交历史记录，不靠版本号。

**发版时必须更新 `CHANGELOG.md`**：把 `[未发布]` 下的条目移进新版本段，标注日期，更新文末比较链接。格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，分类只用新增 / 变更 / 弃用 / 移除 / 修复 / 安全。

**改版本号要同步 5 处**，漏一处就会在后面某个环节炸：

| 文件 | 作用 | 漏了会怎样 |
|---|---|---|
| `firmware/boards/175/MotoNav/src/core/FirmwareConfig.h` | `FW_VERSION`，编译进固件 | 屏幕上显示旧版 |
| `firmware/RELEASE_VERSION` | 打包脚本读它，**强校验必须等于 FW_VERSION** | `package_flasher.py` 直接报 `Source/version mismatch` |
| `firmware/windows-flasher/flash.ps1` | 第 46 行版本比对、第 52 行标题 | 生成的一键包运行时 `throw '固件清单版本不匹配'` |
| `firmware/macos-flasher/一键烧录.command` | 第 8 行 `task_version` | 打 mac 包时报 `Stale Mac version` |
| `firmware/windows-flasher/使用说明.txt` | 首行标题 | 只是文本过时，功能不受影响 |

验证方式：跑一次 `python package_flasher.py --tools-dir <含 esptool.exe 的目录>`，它内部会校验版本一致性、镜像格式、清单哈希，全过才算干净。产物在 `output/firmware/<版本>/`，用完可以删。

`firmware/README.md`、`firmware/MAC_PACKAGE.json`、`docs/README.md`、`docs/RELEASE-IOS-FIRMWARE-2026-11-01.md` 里仍写着 `7.12.10-phone.8`，这些是**上游发布说明**，描述的是上游的 release 附件和下载链接，不随本仓库版本号变，不要顺手改。

### tag 规范

| tag | 含义 |
|---|---|
| `upstream-phone.8` | fork 起点：上游 phone.8 源码快照，指向 `e122516` |
| `fw-v1.0.0` | 固件发布版，版本号抄 `FW_VERSION` |
| `ios-1.0.0` | iOS App 发布版，版本号抄 `CFBundleShortVersionString` |

规则：

- `fw` = firmware 固件，`ios` = iPhone App。前缀标模块，因为两者版本号是**两套独立编号**（固件 1.0.0、App 0.16.2），混在一个序列里会看不懂
- `upstream-phone.8` 这个 tag 不带模块前缀是对的：它标的就是上游的代码，是历史事实
- 必须用 `-a` 打附注 tag，轻量 tag 不记录打标人、时间和说明
- `git push` 不会自动带 tag，要单独 `git push origin <tag>`
- tag 是否已推、指向哪个提交，用 `git tag -l` / `git describe --tags` 现查，不写进文档

---

## 2. 硬件

| 部件 | 参数 |
|---|---|
| 板子 | Waveshare ESP32-S3-Touch-AMOLED-1.75（圆屏） |
| MCU | ESP32-S3，32MB Flash，8MB OPI PSRAM（R8 版本） |
| 屏幕 | CO5300，QSPI 4 线，466×466，默认 40MHz，可切 60/80 |
| 触摸 | CST92xx（I2C），实机 X/Y 都反装，靠 `TOUCH_FLIP_X/Y=1` 纠正 |
| 电源 | AXP2101（电量轮询、插电不自动关机） |
| 音频 | ES8311（I2S），功放 PA 在 GPIO46 |
| 存储 | SDMMC + 32MB Flash，分区 `app5M_fat24M_32MB`（app 4.8MB，FAT 22MB） |

引脚表见 `firmware/boards/175/MotoNav/pin_config.h`。

---

## 3. 系统分层

```
Android / iOS App
  高德 SDK 渲染 → 抓图 → 栅格化 → 4bit 调色板 + RLE
        │
        │ BLE：分片 485B/包，MTU 517，'M' 头 15B
        ▼
ESP32-S3 固件
  收包 → 解码 → 画进 PSRAM 画布 → 一次性推屏
```

手机端是导航引擎，圆屏是显示器。这条边界决定了所有改动的位置：**改地图内容、路线、语音 → 改手机端；改界面、动画、图标、按键 → 改固件。**

---

## 4. 固件结构

```
firmware/
├── build.py / build.ps1        编译，产出 dist/175/panel0
├── libraries/                  随仓库走的依赖，不要用系统装的
│   ├── GFX_Library_for_Arduino
│   ├── SensorLib
│   └── MotoNavIpcStackGuard    链接期兜底，必须保留
├── windows-flasher/            Windows 一键烧录包生成器
├── macos-flasher/
├── tests/
└── boards/175/MotoNav/
    ├── MotoNav.ino             入口 + 主循环调度
    ├── pin_config.h            引脚
    ├── BootAnimation.h         开屏动画
    ├── HomeClock.h             首页时钟
    ├── src/core/               FirmwareConfig（版本号）· DeviceContext · FunctionDeclarations
    ├── src/connectivity/       Bluetooth · HID · Notifications
    ├── src/protocol/           CommandReceiver · BulkReceiver · TextBitmapReceiver
    ├── src/map/                矢量/路线/栅格/ghost 的解码与渲染
    ├── src/pages/              6 个页面
    ├── src/display/            DisplayPipeline（整屏刷新 / 旋转）
    ├── src/graphics/           矢量绘制、进度环、车道、路口、状态栏
    ├── src/power/              电量、关机
    ├── src/input/              Buttons.h：BOOT + PWR 两个侧键
    ├── src/diagnostics/
    └── resources/              BrandLogos.h(658KB) · CameraIconPixels.h(253KB) · HomeSprites.h · RiderSprites.h（旧像素骑手，已不引用）
```

### 页面清单

| 文件 | 内容 |
|---|---|
| `src/pages/HomePage.h` | 骑行前默认界面：像素风黄昏赐福，两幅画面存在 `resources/HomeSprites.h`（8bpp 索引、233×233、各约 54KB 在 flash，显示按 2× 放大）：未连接=褪色者独坐赐福旁（远处废墟与远山），已连接=托雷特站在他身旁、他站着牵缰。两幅取自不同参考图，取景宽度按“主体一样大”定（512 / 683），赐福火落在同一个屏幕位置。连上 / 断开走抖动溶解过渡（600ms，按两图差异加权、马那块权重最高、锋面点成金色光点）并在赐福处闪一下（320ms 加色），光尘从火光升起。绘制分整帧（进页面 / 浮层）、溶解（状态切换 600ms）与局部（静置 10fps 只擦光尘那一小块），推屏走同步单缓冲；所有绘制裁到圆内（`hCircleSpan`）。点屏幕开信息浮层，6 秒自动收起。三态 `WAIT_READY / WAIT_NOLINK / WAIT_LOST`。**“连上没有”统一由 `homeLinkReady()`（`src/connectivity/Bluetooth.h`，= `bleConnected && bleAuthed`）判定**，主循环、`renderPage`、侧键回首页、状态栏小绿点、`#C` 共用，别再写裸的 `bleConnected`；溶解进度记在 `hMixT` + `hMixDir` 上，目标中途改回来时只把方向取反、原路退回；主循环每帧比对屏上状态与实际状态，切换被吞掉时下一帧自愈 |
| `src/pages/NavigationPage.h` | 导航主界面 |
| `src/pages/WeatherPage.h` | 天气页（第 2 页） |
| `src/pages/IncomingCall.h` | 来电界面 + **`touchPoll()` 全部触摸逻辑** |
| `src/pages/ArrivalAnimation.h` | 到达特效 |
| `src/pages/PairingPage.h` | 配对页 |
| `src/pages/PageNavigation.h` | 换页调度 |

### 主循环（`MotoNav.ino`，每轮）

1. 查连接状态，断开显示 `LINK LOST` / `WAIT_NOLINK`
2. 最多消费 30 条接收队列消息
3. `pollRasterWork()` 推进栅格解码分片（每片约 16ms，旧图继续显示）
4. `sendPendingAck()` 回 `K,type,id`
5. 进度环 / 行程环动画
6. `touchPoll()` + `buttonsPoll()` + `batPoll()`
7. `navDirty` 脏标记触发重绘

UI 是脏标记 + 按需重绘，不是固定帧率。项目里说的"帧率"指重绘一次地图的耗时。

### 触摸（屏幕）

全部逻辑在 `src/pages/IncomingCall.h` 的 `touchPoll()`（位置反直觉，改触摸行为认这里）：

- 滑动：`dragMove()` 跟手换页，三页循环
- 点击音乐键：`musicButtonAt()` 判定热区，`musicTap()` 执行
- 点击天气区：`weatherTap()`
- 来电长按接听：按住不动累计到 `HOLD_MS`，发 `T,A`
- 到达特效：点一下 `stopArriveFx()`
- 触摸采样节流 12ms，手指离开超过 80ms 才算松开

### 物理侧键（`src/input/Buttons.h`，2026-11-03 新增）

板子上只有两个侧键，原固件都没用起来：

| 键 | 硬件 | 原固件行为 | 现在 |
|---|---|---|---|
| BOOT | GPIO0，低有效 | 只在关机流程里当 ext0 唤醒源 | 短按翻页，长按 2000ms 回骑行前首页 |
| PWR | AXP2101 PWRKEY | 固件从未配置 PMU 中断 | 短按反向翻页 |

- 改 PWR 要动 AXP2101 寄存器：`INTEN2(0x41) bit3` 打开短按中断，`INTSTS2(0x49) bit3` 读状态，写 `0xFF` 清除。这两个地址来自 XPowersLib，`PKEY_SHORT_IRQ = _BV(11)`，落在第 2 组寄存器 bit3
- `BTN_BOOT_GOES_RIGHT` 控制左右方向，装上后觉得反了就改 0
- `BTN_PWR_ENABLED` 改 0 可以完全不碰 PMU，只验证 BOOT
- 引脚 `BTN_BOOT` 在 `pin_config.h`，和其余板级引脚放在一起
- 翻页和回首页都复用 `slidePrepare → slideAnimate → slideCommit`，按键和手势共用一套动画；回首页 260ms，翻页 220ms
- PWR 中断状态每 30ms 轮询一次（`BTN_PWR_POLL_MS`），不跟电量轮询抢 I2C
- 长按回首页会先 `stopArriveFx()`，否则到达特效会继续往首页上画
- `DEBUG_SERIAL 1` 时串口会打印 `BTN page a -> b` / `BTN home` / `BTN pwr short`
- 开机动画在 `setup()` 里阻塞播放，`buttonsArm()` 在画面播完后才武装按键，避免上电按住 BOOT 进下载模式时误触发
- PWR 长按（约 6 秒）是 PMIC 硬件强制断电，软件改不了

### 开屏动画（`BootAnimation.h`）

- 17 个品牌：MOTONAV / HONDA / YAMAHA / SUZUKI / KAWASAKI / BMW / DUCATI / KTM / TRIUMPH / HARLEY-DAVIDSON / APRILIA / CFMOTO / QJMOTOR / VOGE / ZONTES / BENELLI / ROYAL ENFIELD
- 固定 `Duration = 1900` 毫秒
- 纯代码矢量绘制（`Painter` 类，line / arc / rect / light 抗锯齿），不是图片序列
- 品牌位图在 `resources/BrandLogos.h`，658KB
- 选中哪个品牌存在 NVS 键 `bootbrand`，值域 `0..17`：`0` 是 MOTONAV，`1..16` 是各车厂，`17` 不叠加任何品牌标（`drawBadge` 里 `if(id==Off) return`）
- 品牌 ID 是协议里的稳定 ID，改这里必须同步手机端 `BootBrand.swift` / `BootBrand.kt`

### 代码约定

- 缩进 **2 空格**，大括号同行，文件行尾 LF（和上游一致，仓库里 69/70 个 `.h` 都是这样）
- 每个头文件顶部一个 `#pragma once`，**头文件里直接写实现**，全工程只有一个编译单元
- 依赖靠 `MotoNav.ino` 的 include 顺序解决：头文件内部不 include 其它业务头，它用到的全局变量和函数必须在被 include 之前已经定义。新增文件要插在正确的位置，不是随便加一行 include
- 注释用中文、短。改动行为的地方按上游习惯在行尾标版本：`// v1.0 侧键：长按回首页`，版本号对应 `FW_VERSION` 的主次号，不是上游的版本号（上游原文件里 286 处都是 `// vX.Y 说明` 这个格式）
- 命名：函数和变量 camelCase（`touchPoll`、`navDirty`），宏 UPPER_SNAKE（`BTN_LONG_MS`），类型 PascalCase（`IdlePowerOffTimer`）
- 新功能放 `src/<模块>/Xxx.h`。现有模块：`pages/` `graphics/` `power/` `protocol/` `map/` `display/` `connectivity/` `input/`。不要往 `MotoNav.ino` 里堆实现，它只负责 include 和调度
- 时间比较一律写成 `now - last >= 间隔`（无符号相减），不要存绝对时间点再相减，`millis()` 回绕时会算出负数
- 片选/引脚一律进 `pin_config.h`，不要写在功能头文件里
- 提交信息用中文：标题一句话说做了什么，正文说为什么。不用 `fix` / `update` / `change` 这种没信息量的词
- 改完代码更新 `docs/需求清单.md` 对应条目；需求、进度、阻塞项只在那里记，不写进本文档
- 功能改动在 `CHANGELOG.md` 的 `[未发布]` 段随手记一条，发版时再归并
- 文档归属固定三处，不要再开新类型：**规范与架构 → 本文档**；**需求与进度 → `docs/需求清单.md`**；**版本改动摘要 → `CHANGELOG.md`**（Keep a Changelog 格式）。一处事实只写在一处，别处用链接指过去
- 过程草稿、方案对比、预览图不进仓库；`scripts/preview/` 已在 `.gitignore`
- 参考素材进仓库，统一放 `assets/reference/`（原始分辨率、原始字节，不改码率/尺寸），脚本只从那里读

---

## 5. 内存预算（改 UI 前先看这张）

| 用途 | 大小 | 位置 |
|---|---|---|
| 双帧缓冲 `fbBuf[2]` | 466×466×2×2 ≈ 868 KB | PSRAM |
| 栅格工作缓冲 | 82×82×128 ≈ 840 KB（16×16 分块） | PSRAM |
| 栅格原始接收 | 500 KB | PSRAM |
| 矢量地图 | 200 KB | PSRAM |
| 路线 / ghost | 96 KB / ~96 KB | PSRAM |
| 13 栏文字位图（收发各一份） | ≈ 208 KB | PSRAM |
| 接收环形队列 | 48×512 = 24 KB | 内部 RAM |

没有 PSRAM 或不足 4MB 的板子跑不动，这也决定了这套固件只能刷 1.75。

---

## 6. BLE 协议要点

| 项 | 值 |
|---|---|
| 设备名 | `MotoNav-XXXX`（XXXX 由 MAC 派生） |
| 服务 | 自定义 128 位服务 + 标准 HID `0x1812`（同一广播包，29 字节） |
| 特征 | RX（WRITE / WRITE_NR）、TX（NOTIFY） |
| 配对 | 6 位随机码，**开机 2 分钟内**允许配对；已配对设备随时可连 |
| 安全 | `encrypted && authenticated` 才算认证通过，未认证不接收控制指令 |
| 分包 | 485 字节/包，MTU 517，`'M'` 头 15 字节 |
| 确认 | `K,type,id`；重复末包只再确认一次 |
| 大块类型 | 1 矢量地图 / 2 路线（增量坐标）/ 3 栅格位图 / 4 ghost 原路线 |
| 文字位图 | `'B'` 帧，13 栏 |
| 文本指令 | 约 50 条，全部 `#` 前缀（唯一例外是"方向,距离"），未知 `#` 指令安全忽略 |
| 音乐 | HID over GATT + Apple AMS，键码 上一首 `0x00B6` / 播放暂停 `0x00CD` / 下一首 `0x00B5` |

要改这些数字，手机端和固件必须同时改，单改一端直接断连。

---

## 7. 编译与烧录

### 固件

```sh
# 本机已装好，可直接编（首次约 6.5 分钟，之后增量 1~2 分钟）
"C:/Users/codem/AppData/Local/Programs/Python/Python313/python.exe" firmware/build.py \
  --cli "C:/Program Files/Arduino CLI/arduino-cli.exe" --jobs 4

# 产物 firmware/dist/175/panel0/，文件名带 FW_VERSION
#   *_app_0x10000.bin    应用镜像，烧到 0x10000，保留 NVS（配对和设置不丢）
#   *_full_0x0.bin       整片镜像，烧到 0x0 并 --erase-all（救砖用，清空所有数据）
#   *_manifest.json      大小 + SHA256
```

烧录（只写 app 分区，不动 NVS）：

```sh
"C:/Users/codem/AppData/Local/Arduino15/packages/esp32/tools/esptool_py/5.3.0/esptool.exe" \
  --chip esp32s3 -p COM4 -b 460800 write-flash 0x10000 \
  firmware/dist/175/panel0/*_app_0x10000.bin
```

`COM4` 换成设备管理器里的实际串口。板子实测为 32MB Flash（`flash-id` 读回 GigaDevice `c8 4019`），2.0.0 起构建和分区表都按 32MB 来；从 16MB 旧固件升级只能整片刷。

每次出包后把 `dist/175/panel0/` 拷一份到本机的 `..\builds\<日期>-<分支>\`（仓库外）并生成 SHA256，换机器时可以不重编直接烧。

编译偶发 `internal compiler error: in try_forward_edges, at cfgcleanup.cc:580`（xtensa GCC 的已知缺陷，和代码内容无关），重跑一次即可，不必改代码。

`build.py` 只写新文件、不删旧文件。改过 `FW_VERSION` 之后 `dist/` 里会同时存在两个版本号的产物，按文件名挑，或者先清空目录再编。

### 生成物（都不进 git）

| 目录 | 体积 | 是什么 |
|---|---|---|
| `firmware/.build/` | ~205 MB | 编译中间产物（.o / 中间 bin），删掉只是下次首编慢 6 分钟 |
| `firmware/dist/` | ~2.6 MB | 打包产物 |
| `firmware/boards/175/MotoNav/build/` | — | arduino-cli 的临时构建目录 |
| `.idea/` | 73 KB | JetBrains 工程配置 |

这四个都在 `.gitignore` 里。`git status` 干净时 IDE 里仍会看到它们，那不是未提交内容。

首次装工具链的记法（换机器时照抄）：Arduino CLI 1.5.1 用 winget 装；ESP32 Core 3.3.10 的索引里
1247 个地址在 github.com，直连约 160 KB/s、arduino-cli 自带下载器约 200 KB/s，1.5 GiB 要两小时以上。
可行做法：把索引里的 URL 改写成 `https://ghfast.top/https://github.com/...`（实测 2~4.5 MB/s），
再用 `curl -K` 并行下载到 `%LOCALAPPDATA%\Arduino15\staging\packages\`，最后 `core install` 会直接吃缓存。
注意必须选 host 为 **`x86_64-mingw32`** 的包，选成 `x86_64-pc-linux-gnu` 装不上。

FQBN 固定为：

```
esp32:esp32:esp32s3:FlashSize=32M,PartitionScheme=app5M_fat24M_32MB,PSRAM=opi,CDCOnBoot=cdc
```

### 32MB 分区方案（ESP32 Core 3.3.10 可选菜单，取自 core 的 `boards.txt` 与 `tools/partitions/*.csv`）

| 菜单项 | 分区表 | app0 | app1（OTA） | 文件系统 | coredump |
| --- | --- | --- | --- | --- | --- |
| `app5M_fat24M_32MB`（当前） | `large_fat_32MB` | 4.50MB @0x10000 | 4.50MB @0x490000 | ffat 22.875MB @0x910000 | 64KB @0x1FF0000 |
| `app13M_data7M_32MB` | `default_32MB` | 12.50MB @0x10000 | 12.50MB @0xC90000 | spiffs 6.75MB @0x1910000 | 64KB @0x1FF0000 |

事实说明（不含取舍建议）：

- 分区表只决定代码和文件写入的地址与上限，不改变 Flash 模式/频率、PSRAM 模式、CPU 频率与 cache 配置，因此与运行速度无关。
- 切换方案必须整片刷（`--erase-all`），NVS 位于 `0x9000`，其余区域地址随方案变化，设置与手机配对会清空。
- 当前固件占用 app0 1,308,352 字节（镜像），约 4.50MB 方案的 28%、12.50MB 方案的 10%。
- 当前固件未挂载任何文件系统：源码中无 `FATFS`/`FFat`/`SPIFFS` 引用，上述 ffat / spiffs 分区目前均为未使用空间。
- `max_app_32MB.csv`（单槽 31.87MB，无 OTA、无文件系统）存在于 `tools/partitions/`，但不是菜单项，要使用需自定义分区表。

`build.py` 会从 `src/core/FirmwareConfig.h` 里正则抓 `#define FW_VERSION "v..."` 当版本号，格式必须带 `v` 前缀。链接参数 `-Wl,--wrap=xTaskCreatePinnedToCore` 来自 `MotoNavIpcStackGuard`，删了这个库会丢掉 IPC 栈越界的修复，表现为蓝牙初始化时反复重启。

### 安卓（不在维护范围）

只做 iOS 端，下面命令仅作参考，不主动编译或修改。

```powershell
$env:JAVA_HOME='C:\tools\java\jdk\openjdk-17.0.2'
$env:GRADLE='C:\tools\gradle\gradle-8.10.2\bin\gradle.bat'
.\Build-Personal.ps1 -JavaPath $env:JAVA_HOME -GradlePath $env:GRADLE -SdkPath 'D:\Android\Sdk'
```

两个环境已就位：Gradle 8.10.2、OpenJDK 17.0.2。还需要 Android SDK 35。首次构建会生成个人包名和本机签名，务必备份 `android/standard/personal.properties` 和 `keystore/`。

### iOS

```sh
bash build-ios.sh    # Xcode + CocoaPods 1.16.2
# 产物 output/ios/MotoNav-<ver>-build<n>-unsigned.ipa
```

Windows 编不了 iOS，走 GitHub Actions。Actions 已启用，工作流在 `.github/workflows/ios-quick.yml`，手动触发，下载 artifact，用 iLoader / SideStore 自签。详细步骤见 `docs/IOS-CI-GUIDE.md`。

### 打包时机：全手动

开发一批内容、自己确认没问题了，再主动出包装机测试。**任何 push 都不应该自动触发构建。**

仓库里有 4 个工作流，配置目标是「1 个启用 + 3 个禁用」：

| 工作流 | 触发条件 | 状态 |
|---|---|---|
| `ios-quick.yml` | 只有 `workflow_dispatch` | **启用**，手动点 |
| `release-ios.yml` | push main 且改 `ios/**` 或 `firmware/boards/175/MotoNav/**` | **已禁用** |
| `release-firmware.yml` | push main 且改 `firmware/**` | **已禁用** |
| `android-verify.yml` | push main 且改 `android/**` | **已禁用** |

`firmware/**` 这个匹配很宽，改一行固件就会命中；不禁用的话每推一次固件都要跑一轮 40 分钟的 iOS 构建加一轮打包。

那三个是上游的文件，**不要改它们的 yml**（会和上游同步冲突），直接在网页上禁用：
`Actions` 页面 → 左侧点进该工作流 → 右上角 `...` → `Disable workflow`。

禁用状态记在 GitHub 上，不在代码里，所以：

- 想临时跑一次官方 iOS 流程：先 `Enable workflow`，跑完记得再禁用
- **每次同步上游之后检查一遍 Actions 左侧列表**，上游新增的 workflow 进来后默认是启用的，会破坏"全手动"

iOS 出包：`Run workflow` → 选分支 → note 填本次改了什么 → 跑完在 run 页面下载 artifact。
固件出包：本地 `python firmware/package_flasher.py --tools-dir <含 esptool.exe 的目录>`，产物在 `output/firmware/<版本>/`。只给自己装机的话直接用 esptool 烧 app 分区即可，不必打包。

---

## 8. 硬约束（改代码前逐条过）

1. FQBN 四个参数一个都不能改，尤其 `PSRAM=opi` 和 `CDCOnBoot=cdc`
2. ESP32 Arduino Core 必须 3.3.10
3. `firmware/libraries/` 必须当依赖源，不用系统装的 GFX / SensorLib
4. `MotoNavIpcStackGuard` 不能删
5. 版本串保持 `v` 前缀，`build.py` 靠它抓版本
6. 改开屏品牌 ID，同步手机端 `BootBrand.swift` / `BootBrand.kt`
7. NVS 键名（`qspi` / `rot` / `rotd` / `bootbrand` / `mediahid` / `fastf`，命名空间 `motonav`）改名会让老设备设置丢失
8. 协议数字（485 / 517 / 15 / 13 栏）两端成对改
9. iOS 主 App 和 `MotoNavShare.appex` 的版本号必须完全一致，否则 `build-ios-ipa.sh` 直接失败
10. 烧 `0x0` 会 `--erase-all`，配对信息全丢，只有救砖才用

---

## 9. 调试手段

| 手段 | 怎么开 |
|---|---|
| 串口看每条文本指令 | `FirmwareConfig.h` 里 `DEBUG_SERIAL 1` |
| 帧率诊断 | `FPS_SERIAL_DIAGNOSTICS 1`（默认已开） |
| 数据中断阈值 | `STALE_MS 6000`，6 秒没收到任何消息（含心跳）提示中断 |
| 三阶段距离 | `STAGE_FAR_M 500` / `STAGE_NEAR_M 100` |
| QSPI 提速 | 发 `#q,60` 或 `#q,80`，写 NVS 后重启 |
| 屏幕旋转 | `#R` 四分之一圈，`#D` 任意角度（0–359°） |

改完固件出现偶发重启，先接串口看 `Reset reason` 和栈水位 `IPC stacks bytes=.../... free-min=.../...`。这条路径在 pages.4 修过一次真问题，能拿到转储。

---

## 10. 需求、进度与变更

需求、进度、阻塞项、验收记录**只在 `docs/需求清单.md` 维护**；每次发版改了什么**只在 `CHANGELOG.md` 维护**。本文档不记录做到哪一步，避免同一个状态在两处各写一遍然后互相过期。

排期或动手前现查：`git log -1`、`git status -sb`、`git tag -l`。

---

## 11. 相关文档

| 文件 | 内容 |
|---|---|
| `AGENTS.md`（本文件） | 项目总索引：架构、改动点、构建、硬约束、约定 |
| `docs/MotoNav-技术文档.md` | 933 行深度文档，协议逐条、时序、地图管线、侧载方案 |
| `CHANGELOG.md` | 版本改动摘要，Keep a Changelog 格式（发版时写） |
| `docs/需求清单.md` | 需求、进度、阻塞项、验收记录（唯一记录处） |
| `docs/IOS-CI-GUIDE.md` | iOS 云端出包 9 步操作 |
| `scripts/home_sprites.py` | 生成主页两幅画面 `resources/HomeSprites.h`（8bpp 233×233，两幅各约 54KB）。两张参考图在 `assets/reference/`：<br>· 未连接 ← `home-dual-pose.png` 的**上格**（1536×1024 双姿态图，上格人独坐无马），取 512×504<br>· 已连接 ← `home-standing.png`（1536×1024 紧凑构图，人站着牵马），取 683×683<br>683 是按“主体一样大”量出来的：两图火焰列高度都是 129 px。**不要为了把王城框进来把这个数放大到 1024**——那样已连接那张整体缩到 67%，切换时肉眼可见镜头拉远。两张都让火落在同一个屏幕位置（233 尺度 OFF x=151 / ON x=155），切换时人和火不跳。`HOME_BEAM_*` 锚点由脚本求出：x 取“暖色高亮行数最多的那一列”，y 取每张图各自的基线常数；换参考图或改取景框后要重新量基线，对不上脚本会报错而不是静默跑偏 |
| `scripts/home_preview.py` | PC 端预览主页画面，输出 `scripts/preview/*.png`，需 Pillow |
| `.github/workflows/ios-quick.yml` | 精简工作流，8~15 分钟出 unsigned IPA |
| `firmware/README.md` | 上游固件说明（描述上游 `7.12.10-phone.8`，不随本仓库版本变） |
| `docs/RELEASE-IOS-FIRMWARE-2026-11-01.md` | 上游 `phone.8` 发布说明 |

仓库外、仅本机存在的：`..\builds\<日期>-<分支>\`（每次出包归档的 bin + SHA256）、`..\arduino-setup\`（工具链安装缓存）、`..\latest-2026.11.01-r2\`（上游下载包）。这些不进 git，换机器要自带。
