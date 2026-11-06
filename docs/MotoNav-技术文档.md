# MotoNav 技术文档

> 手机 + 微雪 ESP32-S3-Touch-AMOLED-1.75 圆屏的摩托车导航方案
> 文档版本：2026-11-02 ｜ 对应上游 commit `e1225162`（2026-11-01）｜ 固件 `7.12.10-phone.8`

---

## 0. 这份文档怎么来的

| 来源 | 具体内容 | 可信度 |
| --- | --- | --- |
| 本地材料 | `C:\Users\codem\Documents\MyFile\moto\` 下的烧录包、ZIP、QQ 群说明 PDF | 逐文件实测 |
| 上游仓库 | `github.com/zyn950929/MotoNav` @ `e1225162`，通过 API 拉取文件树（1490 项）与关键源码 | 直接读源码 |
| 你的分支 | `github.com/sbcyk/MotoNav`，通过 API 核对 HEAD 与分支 | 直接比对 |

**没有验证的部分会在正文明确标注**（例如 PSRAM 具体容量、iOS 实机行为、读秒数据源）。凡涉及"代码里写的"和"我推测的"，我都分开表述。

---

## 1. 一页速览

### 1.1 你现在的状态

| 项目 | 现状 | 说明 |
| --- | --- | --- |
| 你的 fork | **纯镜像，0 个自有提交** | `sbcyk/MotoNav` 的 `main` = `e1225162`，与上游 HEAD 完全一致；仓库 2026-11-02 创建，只有 `main` 一个分支 |
| 本地固件包 | pages.4（旧）+ **phone.8（已下载，2026-11-02）** | pages.4 落后 3 次迭代；phone.8 已存 `latest-2026.11.01-r2\`，两层 SHA256 均校验通过（详见 §10.4） |
| 固件完整性 | **校验通过** | pages.4 与 phone.8 的 bin SHA256 都与各自 manifest 逐字节一致（详见 §10、§10.4） |
| 手机端 | 安卓只有源码；**iOS IPA 已下载** | 安卓无预签名 APK，需自建；iOS `0.16.2 Build16` 未签名 IPA 已存本地，需自签安装（详见 §12） |
| 手机设备 | iPhone 16 Pro / iOS 27 | 可侧载，方案见 §12；**但 iOS 版没有红绿灯读秒**（§12.7） |
| 动手门槛 | 中 | 要装 JDK17 / SDK35 / Gradle 8.10.2；读秒版还要 apktool + Zig + 148MB 第三方组件 |

### 1.2 三句话理解这个项目

1. **ESP32 不是导航引擎，是显示终端。** 手机跑高德 SDK，把地图渲染成位图、把路线压成矢量，通过 BLE 推给圆屏；圆屏只负责解码、绘制、按状态机画 UI。
2. **协议是自研的极简二进制 + 井号文本指令**，没有版本号，靠"能力上报"（`CAP` / `#BC` / `#GB?`）做向后兼容。
3. **它是单人 + AI 辅助开发的项目**，注释就是变更日志（`v6.7`、`v7.12.10` 混在代码注释里），工程成熟度靠 24 个 C++ 单测 + GitHub Actions 撑着，但**没有实车回归**。

---

## 2. 项目全景

### 2.1 三方关系

```
┌─────────────────────────────────────────────────────────────┐
│  zyn950929/MotoNav          上游主仓（唯一真源）              │
│  · 137 stars / 33 forks / 7 open issues                      │
│  · 2026-10-16 创建，许可：非商业（NOASSERTION）               │
│  · 含：Android 双版本 + iOS + ESP32 固件 + 打包工具链          │
└───────────────┬─────────────────────────────┬───────────────┘
                │ fork（2026-11-02）           │ UI 来源（iOS）
                ▼                              ▼
┌───────────────────────────────┐  ┌──────────────────────────────┐
│  sbcyk/MotoNav（你的分支）     │  │ coolcoolmanman-design/MotoNav │
│  · main = e1225162（零差异）   │  │ · 0.15.21-tpms @ c01d6db1     │
│  · 目前只是备份/镜像           │  │ · iOS 四栏 UI 的设计来源       │
└───────────────────────────────┘  └──────────────────────────────┘
```

### 2.2 当前版本矩阵（上游 2026-11-01 r2）

| 组件 | 版本 | 分发形式 | 备注 |
| --- | --- | --- | --- |
| 安卓普通版 | 8.3.26 | 仅源码 | 无读秒，功能最全（网页摩托车规划、巡航、轨迹） |
| 安卓读秒版 | 8.3.26-single.32-fresh.1 | 仅源码 + 打包脚本 | 五栏精简 UI，红绿灯读秒（实验） |
| ESP32 固件 | 7.12.10-phone.8 | 一键烧录 ZIP（Win 14.6MB / Mac 27.3MB） | 两版安卓 + iOS 共用 |
| iOS | 0.16.2 Build16 | 未签名 IPA（43.6MB） | 无读秒，需自签 |
| 固件源码 | 7.12.10-phone.8 | ZIP 13.7MB | Arduino Core 3.3.10 |
| 纯镜像包 | 同上 | ZIP 1.3MB | 已有烧录环境用 |

### 2.3 许可与商业限制

- 仓库 `LICENSE.md`：**仅限非商业使用，禁止未经许可转售**。GitHub 标记为 `NOASSERTION`（非标准 OSI 许可）。
- 第三方部分各自独立：高德 SDK（商用需授权）、Espressif BLE/Arduino Core（Apache-2.0）、GFX Library、SensorLib、miniz、`provider.apk`（第三方构建依赖，148MB，**不属于开源代码**）。
- 你要做二次分发（哪怕免费），先看 `LICENSE.md` 与 `licenses/` 目录，不要默认"GitHub 上就是随便用"。

---

## 3. 系统架构

### 3.1 分层

```
┌────────────────────────── 手机端（Android / iOS） ──────────────────────────┐
│  UI 层        MainActivity / SwiftUI 四栏                                   │
│  导航层       NaviBridge（高德导航 SDK 回调 → 指令）                         │
│  地图供给层   MapFeeder（沿线预取、带宽预算、确认驱动）                       │
│  抓图层       AmapCaptureHost / AmapSdkRaster（渲染→截屏→降采样→编码）       │
│  链路层       BleLink（扫描/配对/MTU/分片队列/ACK/重连退避）                  │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │ BLE GATT（MTU 517，写 500B/包）
┌───────────────────────────────────▼─────────────────────────────────────────┐
│                      ESP32-S3 固件（单 .ino + 41 个头文件）                   │
│  接收      RxCB → 环形队列(48×512B) → 每循环最多消费 30 条                    │
│  分派      'B'位图 / 'M'大块 / 其余按文本指令                                 │
│  解码      矢量地图·路线·栅格(RLE+zlib)·文字位图，栅格走 16ms 分片工作队列     │
│  渲染      MapFrame（预测位姿→平滑→按缩放/朝向投影→绘要素→HUD）               │
│  显示      SwapCanvas 双缓冲 → QSPI(40/60/80MHz) → CO5300 AMOLED 466×466    │
│  外设      触摸(CST92xx) / PMU(AXP2101) / 电量 / 音乐 HID+AMS / 关机保护      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 关键设计取舍（为什么长这样）

| 决策 | 原因 | 代价 |
| --- | --- | --- |
| 地图在手机渲染，屏只收位图 | ESP32 跑不动矢量地图/瓦片解码；高德 SDK 只在手机上有 | 必须保持 BLE 连接，断连即"停在最后一帧" |
| 位图用 RLE + 4bit 调色板压缩 | 466×466@2m/px 一块约 200KB 原始数据，直接传太慢 | 边缘有量化误差，需要楼块继承补画质 |
| 路线用**增量坐标**（i16 dx/dy） | 24000 点如果用绝对 i32 要 192KB，增量只要 96KB | 依赖首点基准，丢包必须整块重传 |
| 大块数据"收齐才解析" | 解析失败可整块重发，不会出现半张图 | 需要 200KB~500KB 双缓冲（PSRAM） |
| 栅格解码拆成 16ms 分片 | 早期整块解码最长帧 339~358ms，肉眼可见卡顿 | 代码复杂度上升，需要工作队列 + 旧图保留 |
| 协议无版本号，只有能力上报 | 旧 App 配新固件、新 App 配旧固件都要能活 | 每个新特性都要写"旧客户端默认行为"分支 |

### 3.3 一次导航的数据流（时序）

```
手机                                 圆屏
 │  ① 连上、配对（6 位码，开机 2 分钟内可配）
 │ ─────────────────────────────────►│
 │  ② 能力查询：#GB? / CAP,HID,1      │
 │ ◄─────────────────────────────────│
 │  ③ 起终点点位：#p,frame,x,y,hdg,kmh │
 │ ─────────────────────────────────►│
 │  ④ 路线整块：'M' type=2            │
 │ ─────────────────────────────────►│  ── 收齐回 K,2,id
 │  ⑤ 地图块：'M' type=1 或 3（沿线预取）│  ── 收齐、解码完成回 K,1/3,id
 │ ─────────────────────────────────►│
 │  ⑥ 导航指令流：方向,距离 / #e / #j / #k / #g / #u
 │ ─────────────────────────────────►│  ── 每帧重绘
 │  ⑦ 文字位图 'B'（路名、车道、天气、音乐）
 │ ─────────────────────────────────►│
 │  ⑧ 心跳 "P"（6 秒无消息 → 屏显数据中断）
```

---

## 4. 硬件平台

### 4.1 板子与器件（依据 `pin_config.h` + `DeviceContext.h`）

| 部件 | 型号/参数 | 在代码中的体现 |
| --- | --- | --- |
| MCU | ESP32-S3，构建要求 `PSRAM=opi`、`FlashSize=32M` | FQBN：`esp32:esp32:esp32s3:FlashSize=32M,PartitionScheme=app5M_fat24M_32MB,PSRAM=opi,CDCOnBoot=cdc` |
| 屏幕 | **CO5300** QSPI AMOLED，**466×466** | `Arduino_CO5300(bus, LCD_RESET, 0, 466, 466, 6, 0,0,0)` |
| 屏幕总线 | QSPI 4 线，默认 **40MHz**，可切 60/80MHz | `#q,60` 指令改并写 NVS 重启 |
| 触摸 | CST92xx（I2C），`TOUCH_FLIP_X/Y=1`（实机左右上下都反） | `TouchDrvCSTXXX`（SensorLib） |
| 电源管理 | **AXP2101** | 电量轮询、插电不自动关机 |
| 音频 | ES8311 codec（I2S） | 来电铃声/提示音 |
| 存储 | SDMMC + 32MB Flash（app5M_fat24M 分区） | 固件 4.8MB app 分区，FAT 22MB，NVS 存设置 |
| PSRAM | 板载 OPI PSRAM（该型号为 R8 版本，8MB；**容量未经我实测，按微雪规格书为准**） | 所有大缓冲 `ps_malloc` |

### 4.2 引脚（`firmware/boards/175/MotoNav/pin_config.h`）

| 功能 | 引脚 |
| --- | --- |
| LCD SDIO0/1/2/3 | 4 / 5 / 6 / 7 |
| LCD SCLK / CS / RST | 38 / 12 / 39 |
| 触摸 I2C SDA / SCL | 15 / 14 |
| 触摸 INT / RST | 11 / 40 |
| I2S MCK/BCK/DI/WS/DO | 16 / 9 / 10 / 45 / 8 |
| 功放 PA | 46 |
| SDMMC CLK/CMD/DATA/CS | 2 / 1 / 3 / 41 |

### 4.3 内存预算（这是能不能跑起来的硬门槛）

| 用途 | 大小 | 位置 |
| --- | --- | --- |
| 双帧缓冲 `fbBuf[2]` | 466×466×2 ×2 ≈ **868 KB** | PSRAM |
| 栅格位图工作缓冲 `RASTER_BUF_BYTES` | 82×82×128 ≈ **840 KB**（16×16 分块存储） | PSRAM |
| 栅格原始接收 `RASTER_MAX_BYTES` | **500 KB** | PSRAM |
| 矢量地图 `MAP_MAX` | **200 KB** | PSRAM |
| 路线 `ROUTE_MAX` | **96 KB** | PSRAM |
| 原路线 ghost `GHOST_MAX` | ~96 KB | PSRAM |
| 13 个文字位图栏（show+recv） | 13×8192×2 ≈ **208 KB** | PSRAM |
| 接收环形队列 | 48×512 = **24 KB** | 内部 RAM |

**结论**：没有 PSRAM 或 PSRAM 不足 4MB 的板子跑不动这套固件。这也是"只能刷 1.75 / 不能刷 M5Stack"的根本原因之一。

---

## 5. 固件工程

### 5.1 结构

```
firmware/boards/175/MotoNav/
├── MotoNav.ino                 入口 + 主循环调度（16.9KB）
├── pin_config.h                板级引脚
├── src/core/                   FirmwareConfig（版本号在此）· DeviceContext（全局状态）· FunctionDeclarations
├── src/connectivity/           Bluetooth（配对/HID/接收队列）· DeviceName · Notifications
├── src/protocol/               CommandReceiver（文本指令）· BulkReceiver（'M'分块）· TextBitmapReceiver（'B'位图）
├── src/map/                    MapState · VectorMapReceiver · RasterDecoder · RasterWorkQueue · MapFrame · RouteRenderer ...
├── src/pages/                  HomePage · PageNavigation · WeatherPage · IncomingCall · ArrivalAnimation · PairingPage
├── src/display/                DisplayPipeline（整屏刷新/旋转）· RowWorker
├── src/graphics/               VectorDrawing · ProgressRings · LaneDrawing · JunctionOverlay · StatusWidgets
├── src/power/                  Battery · BatteryPolling · Shutdown
├── resources/                  BrandLogos.h（658KB）· CameraIconPixels.h（253KB）· RiderSprites.h
└── 根目录若干 .h               BootAnimation · TrafficLightLab · AppleMediaClient · RasterBuildingCarry · 自测工具
```

依赖库（仓库自带，不依赖你本地安装）：
`firmware/libraries/GFX_Library_for_Arduino`、`SensorLib`、`MotoNavIpcStackGuard`。

### 5.2 主循环调度（`MotoNav.ino`）

每轮循环的关键动作：

1. 检测连接状态（断开 → 红色 `LINK LOST` 或 `WAIT_NOLINK`）
2. **最多消费 30 条**接收队列消息 → `handleMessage()`（限流，避免卡帧）
3. `pollRasterWork()`：推进栅格解码分片（每片目标 ~16ms，旧图继续显示）
4. `sendPendingAck()`：回 `K,type,id` 与帧率统计
5. 进度环动画 / 行程环
6. `touchPoll()`（含滑动换页、按住接听）+ `batPoll()`
7. 需要时重绘（`navDirty` 脏标记驱动，不是固定帧率）

**设计要点**：整套 UI 是**脏标记 + 按需重绘**，不是循环刷帧。因此"帧率"这个词在项目里指的是"重绘一次地图的耗时"，不是屏幕刷新率。

### 5.3 显示管线

- `SwapCanvas`（继承 `Arduino_Canvas`）：先画在 PSRAM 画布，再一次性推屏；`fbBuf[0]/[1]` 双缓冲。
- 快速刷屏可走后台任务 + 信号量（`flushDone`），刷屏占用 QSPI 总线时亮度调整会等它推完。
- 屏幕旋转支持 0/90/180/270（`#R` 四分之一圈）和**任意角度**（`#D`，394 项测试覆盖 0–359°）。
- 圆屏遮罩：每行算圆内半宽，圆外直接涂黑。

### 5.4 稳定性案例：IPC 栈越界（pages.4 的核心修复）

- 现象：蓝牙初始化时反复重启。
- 定位：系统 IPC 任务栈溢出（崩溃转储 CRC + ELF SHA256 匹配，异常栈指针低于栈底）。
- 修复：两个匹配任务的栈 1024 → 4096 字节（增加约 6KB 动态内存），并引入 `MotoNavIpcStackGuard` 库，链接时显式加 `-Wl,--wrap=xTaskCreatePinnedToCore` 兜底。
- 验证：8 次受控重启 + 纯电池关机再开机，NVS 刷前刷后逐字节相同。

**这条对你有用**：说明这类"偶发重启"不是玄学，设备端是能拿到转储的。你自己改固件后如果出现重启，先接串口看 `Reset reason` 和栈水位打印（`IPC stacks bytes=.../... free-min=.../...`）。

---

## 6. BLE 协议（全文核心）

### 6.1 连接与安全

| 项 | 值 |
| --- | --- |
| 设备名 | `MotoNav-XXXX`（XXXX 由 MAC 派生，`makeBleName()`） |
| 服务 | 原 128 位自定义服务 + 标准 HID `0x1812`（同一广播包，29 字节） |
| 特征 | `RX`（WRITE + WRITE_NR）、`TX`（NOTIFY） |
| 配对 | 6 位随机配对码，**开机 2 分钟内**允许配对；已配对设备随时可连 |
| 安全 | `encrypted && authenticated` 才算认证通过；未认证不接收控制类指令 |
| MTU | 固件 `setMTU(517)`，手机 `requestMtu(517)`，2M PHY 优先 |
| 遗忘配对 | `#UNPAIR`（只清"别的"手机，正在用的保留） |

### 6.2 传输参数（改协议前必须记住的数字）

| 参数 | 值 | 出处 |
| --- | --- | --- |
| 单包最大写入 `MAX_WRITE` | **500 B** | `BleLink.kt` |
| 实际写入 `min(mtu-3, 500)` | MTU 517 时 = **500** | 同上 |
| `'M'` 分块头 | **15 B** | `BulkReceiver.h` |
| 每片有效载荷 | 500-15 = **485 B** | 同上 |
| 单块最大分片数 | 4000（手机端限制）/ 4096（固件限制） | 两侧 |
| 接收队列 | 48 槽 × 512 B，满时丢最旧 | `DeviceContext.h` |
| 心跳 | 手机发 `"P"`；6000ms 无任何消息 → 显示数据中断 | `STALE_MS` |

### 6.3 二进制帧一：`'M'` 大块数据

```
偏移  0    1     2    3-4      5-6     7-10      11-14     15...
     'M' type  id  parts   seq   total    offset   payload
                   (LE16) (LE16)  (LE32)   (LE32)
```

| type | 内容 | 缓冲上限 |
| --- | --- | --- |
| 1 | 矢量地图块（无底图时用线条画路网） | 200 KB |
| 2 | 路线 | 96 KB |
| 3 | 栅格位图（高德截图，主力） | 500 KB（压缩后） |
| 4 | 原路线 ghost（走过的路线，灰色） | ~96 KB |

**确认与重传规则**（这部分近期改得最多，兼容性最敏感）：

- 全部收齐 → TX 回 `K,type,id`；手机收到才算这一块完成。
- **重复的末包**：只再回一次 `K`，不重启已完成的任务。
- type=3 且 **解码任务仍在进行**：收到的重复末包**不回 K**（否则手机会以为可发下一块，解码却还在跑）。
- 解码失败（`queueRasterWork` 拒绝）：把收到的标记清零，允许同 id 完整重发，不回 K。
- 新的 `id / total / parts` 组合 → 视为新的一份，从零开始收（并取消进行中的栅格任务）。

### 6.4 数据类型 1：矢量地图

```
u16 frame | i32 originX | i32 originY | u16 N
重复 N 次： u8 class | u16 pointCount | pointCount × (i16 x, i16 y)
```

- 坐标单位是 **0.1 米**（分米），相对 origin。
- `class & 0x80` → 填充面（`class&0x7F==11` 水面，其余绿地）；否则是线，`class&0x7F` = 1..5 对应 5 档路宽（15/12/10/7/5 像素基准）。
- 固件为每个要素预算外框，画的时候按视口裁剪，最多 7200 个要素。

### 6.5 数据类型 2：路线

```
u16 frame | i32 x0 | i32 y0 | u16 N | (N-1) × (i16 dx, i16 dy)
```

- **增量编码**，首点绝对、其后逐点累加。最多 24000 点。
- 固件额外算累计弧长 `routeCum[]`（路况上色用）和每 32 点一组的外框。

### 6.6 数据类型 3：栅格位图（重点）

```
u16 frame | i32 x0 | i32 y0 | u16 w | u16 h | u16 mm(|0x8000=带调色板)
[可选] 16 × u16 调色板（RGB565）
RLE 数据：每字节 = 高 4 位(长度-1) + 低 4 位(颜色索引)
          高 4 位 == 15 时，再读 1 字节作长度扩展（run = 16 + 扩展值）
[可选] "VCE" 扩展块（zlib 压缩的轮廓几何，miniz 解压）——新 App 不再发送
```

- `mm` = 每像素毫米数，实际使用 **2000**（2 米/像素）。
- 上限：1300×1300 像素、500KB 压缩数据。
- **楼块继承**：新图与旧图覆盖范围重叠时，可把旧图的建筑轮廓"继承"过来补画质，由手机显式发 `#BC,1` 开启（旧客户端不发 → 保持原行为）。
- 解码流程：解到**备用缓冲** → 成功后交换指针（旧图在新图就绪前一直显示）→ 处理边缘补齐。

### 6.7 二进制帧二：`'B'` 文字位图（13 栏）

```
偏移 0   1     2   3     4     5-6   7   8-9    10...
    'B' slot  id  part  parts  w    h   offset  data
```

- 点阵格式：宽 w、高 h，**每像素 4bit**，`total = ((w+1)/2) * h`，单图上限 8192 字节，最多 32 片。
- 收齐即切换（show/recv 交换），不阻塞。
- 栏位分配：

| slot | 内容 | slot | 内容 |
| --- | --- | --- | --- |
| 0 | 路名/转向文字 | 6 | 音乐-歌手 |
| 1 | 底部信息 | 7–11 | 天气扩展（降雨/预警等） |
| 2 | 来电人名字 | 12 | 逐句歌词（最长，独立开关） |
| 3 | 天气-地名 | | |
| 4 | 天气-风湿度 | | |
| 5 | 音乐-歌名 | | |

### 6.8 文本指令总表（全部来自 `CommandReceiver.h` 实测代码）

| 指令 | 方向 | 作用 | 备注 |
| --- | --- | --- | --- |
| `方向,距离` | 手机→屏 | 导航转向 | **唯一不带 `#` 的指令**；`#` 开头的不认识就忽略，不会被误当方向 |
| `P` | 手机→屏 | 心跳 | 6 秒静默触发数据中断提示 |
| `C` | 手机→屏 | 结束导航、复位状态 | |
| `#p,frame,x,y,hdg,kmh` | 手机→屏 | 位置 | x/y 为**分米**；固件会做 0.4 秒平滑修正 + 转弯角速度估计 |
| `#v,kmh` | 手机→屏 | 车速 | |
| `#e,剩余米,ETA(HHMM),红绿灯数` | 手机→屏 | 行程信息 | 用于进度环、剩余时间 |
| `#k,限速,距离` / `#k` | 手机→屏 | 前方测速点 / 清除 | |
| `#c[,frame,(x,y,限速,类型)...]` / `#c` | 手机→屏 | 小地图电子眼 / 清空 | 同坐标沿用上次图标朝向 |
| `#g,距离` / `#g` | 手机→屏 | 前方红绿灯距离 / 隐藏 | |
| `#j,<16进制串>` | 手机→屏 | 车道提示 | 每车道 2 个 nibble（背景/前景），最多 8 车道 |
| `#u,起,止,状态,...` / `#u` | 手机→屏 | 路况着色 / 清空 | |
| `#w,0/1` | 手机→屏 | 清爽模式 | |
| `#z,0/1` | 手机→屏 | 巡航模式 | |
| `#r,1/2` | 手机→屏 | 走过路线：1 变灰 / 2 擦除 | |
| `#y,1/0` | 手机→屏 | 重新规划中 | |
| `#h[,分钟]` / `#h` | 手机→屏 | 更快路线提示 / 收起 | |
| `#x,0/1` | 手机→屏 | GPS 信号弱 | |
| `#n,0/1` | 手机→屏 | 夜间配色 | |
| `#m,0/1` | 手机→屏 | 地图开关 | |
| `#t,主题[,风格]` | 手机→屏 | 配色/风格 | 新 App 第三字段出现时，切换风格会清空旧地图数据 |
| `#Q,0/1` | 手机→屏 | 弯道上色 | |
| `#b,5..255` | 手机→屏 | 屏幕亮度 | 与刷屏任务互斥 |
| `#L,ms` | 手机→屏 | 位置预判提前量 0–800ms | 越小越"跟手" |
| `#O,米/分钟/最高车速` | 手机→屏 | 行程统计 | |
| `#M1` / `#M0` | 手机→屏 | 路程进度环 开/关 | |
| `#J` | 手机→屏 | 到达途经点动画 | |
| `#NW,1` / `#NW,0` | 手机→屏 | 等待定位中 / 结束 | 新客户端指令，旧固件不认识会忽略 |
| `#NA,1` | 手机→屏 | 已到达、停留显示 | 同上 |
| `#R,quarter` / `#D,角度` | 手机→屏 | 屏幕旋转 | `#R` 兼容旧版；`#D` 支持精确角度 |
| `#q,40/60/80` | 手机→屏 | QSPI 速率，**写 NVS 并重启** | |
| `#f,0/1` | 手机→屏 | 快速刷屏，**写 NVS 并重启** | |
| `#TIME,...` | 手机→屏 | 校时（主页时钟） | 断连继续走时，关机后等重新校时 |
| `#UNPAIR` | 手机→屏 | 忘记其他已配对手机 | |
| `#BC,0/1` | 手机→屏 | 楼块继承开关 | **能力开关，旧 App 不发** |
| `#GB?` | 手机→屏 | 查询楼块继承能力 | 固件回 `CAP,GB,1` 类响应 |
| `#B?` | 手机→屏 | 查询电量 | 固件立刻回一帧 `V,…`，不等 5 秒轮询 / 60 秒心跳；旧固件会忽略 |
| `#HM,0/1` | 手机→屏 | 媒体模式：0=App 控制 / 1=HID | 保存到 NVS |
| `#ML,0/1` | 手机→屏 | 逐句歌词开关 | 回执 `ML,0/1` |
| `#LY,gen,titleRev,artistRev` | 手机→屏 | 歌词图片绑定当前歌曲 | 不匹配的图会被拒收 |
| `#AMS?` | 手机→屏 | 请求 AMS 歌曲快照 | |
| `#Z,有会话,播放中,按钮掩码` | 手机→屏 | 音乐状态（App 模式） | |
| `#ZACK,n` | 手机→屏 | 音乐操作回执 | |
| `#TLA,id,ttl` | 手机→屏 | 中性灯卡片租约（无相位） | 只给几何，不给秒数 |
| `#TLP,1` | 手机→屏 | 读秒卡片占位预览 5 秒 | |
| `#TL,src,状态,剩余ms,方向,等待,显示,存活` | 手机→屏 | 单方向快照（旧格式） | |
| `#TLS,src,n,(方向,状态,剩余ms,等待,显示,存活)×n` | 手机→屏 | 多方向**原子**快照 | n≤4，方向不可重复 |
| `#W,..` / `#WX,..` / `#WXRESET` | 手机→屏 | 天气 / 天气扩展 / 复位 | |
| `#i,1,号码` / `#i,0` | 手机→屏 | 来电 / 挂断 | 号码截断 16 字符 |
| `K,type,id` | 屏→手机 | 大块收齐确认 | |
| `V,电量,充电,插电,电压` | 屏→手机 | 电量状态 | 电量/充电/插电变化时发一次，另有 60 秒心跳；认证通过和收到 `#B?` 时各补一帧。电量 `-1` = 没接电池（手机端丢弃） |
| `CAP,HID,1` | 屏→手机 | HID 能力上报 | 认证后重复发送 |
| `HID,模式,可发按键` | 屏→手机 | HID 实际状态 | |
| `ML,0/1` | 屏→手机 | 歌词开关回执 | |
| `AMS ...` | 屏→手机 | AMS 状态/快照（二进制帧 `A6`） | 见 §6.10 |

### 6.9 读秒协议的设计（值得单独说）

固件侧的关键设计思想：**"不预测、不累积、不持久化"**。

- `#TLS` 是**原子快照**：一次给出所有方向，缺失的方向立即清空，绝不跨包累加。
- 每个方向带 `life`（存活时长，≤3000ms），过期自动失效，屏上不显示陈旧秒数。
- 秒数用"下发时刻 + 本地时钟"推算：`seconds = ceil((remainingMs - age)/1000)`。
- 新数据与本地推算偏差超过 **±1800ms** 才重置基准（避免 GPS 抖动导致跳秒）。
- 缺数据时显示灰色实心圆/灰箭头，**不补造数字**（代码注释里明确写了这条原则）。

这就是为什么官方一直强调"读秒是实验功能、以现场信号为准"——它依赖手机端拿到的第三方数据，而固件这一侧已经做到"没数据就不编"。

### 6.10 媒体控制：HID over GATT + Apple AMS

- 在**同一个** BLE 连接上叠加标准 HID（`0x1812`），Report ID 1，Consumer Page `0x0C`，两字节小端。
- 按键码：上一首 `0x00B6`、播放/暂停 `0x00CD`、下一首 `0x00B5`；按下约 60ms 后发 `0x0000` 释放，键间隔 ≥40ms，四槽队列 + 120ms 防抖。
- 只有同时满足"已连接 + 已认证 + 已订阅 + 未 Suspend + Report Mode"才发送，否则显示 `HID NOT READY`，**不假装已就绪**。
- AMS 客户端读歌名/歌手/专辑/时长/播放状态，通过二进制帧 `A6 | gen(LE32) | rev(LE16) | field | part | count | flags | UTF-8` 分片通知手机（每片 ≤128B，20ms 一片），手机收到完整帧才解码渲染成图片栏 5/6/12。
- 歌词来自 LRCLIB 公开接口（默认关闭），匹配时校验歌名/歌手/专辑和约 2 秒时长差，避免现场版串词。
- **注意**：`HID SENT` 只代表 BLE 栈接受了一次按键报告，**不代表播放器执行了**。这个区分在文档里反复强调，做联调时不要被 UI 文字骗了。

---

## 7. 手机端

### 7.1 安卓两版的差异

| | 普通版 `android/standard` | 读秒版 `android/countdown` |
| --- | --- | --- |
| 版本 | 8.3.26 | 8.3.26-single.32-fresh.1（系统版本名保留兼容组件要求，App 内显示 single.32-fresh.1） |
| 界面 | 原版完整界面 | 五栏精简（首页搜索 / 圆屏显示 / 导航语音 / 圆屏设置 / 地图 Key） |
| 读秒 | 无 | 有（实验性，依赖第三方组件） |
| 构建 | `Build-Personal.ps1` | `Build-Countdown.ps1` + apktool 2.12.1 + Zig 0.13.0 + `provider.apk`(148MB) |
| 打包产物 | `output/MotoNav-personal.apk` | `output/MotoNav-8.3.26-single.32-fresh.1-release.apk` |
| 包名身份 | `personal.properties` + `keystore/` | `personal.properties` + `.local/debug.keystore` |
| 文件数 | ~170 | ~194 |

**读秒版的本质**：它是把官方高德 APK（`provider.apk`）的能力"嫁接"进来的完整包，通过 apktool 反编译/重打包 + Zig 编译的原生桥接实现。所以：

- `app/build/outputs/` 里的 Gradle 中间 APK **不是**可用成品（缺 provider 组件）。
- `provider.apk` 是第三方构建依赖，**不属于开源代码**，不能单独安装当 MotoNav 用。
- 个人包名形如 `com.mn.u` + 13 位随机 hex，且**原生路径长度限制 21 个 ASCII 字符**——这是硬约束，不是随便设的。

### 7.2 关键代码模块（读秒版，按体积）

| 文件 | 作用 |
| --- | --- |
| `MainActivity.kt` (104KB) | 主界面与生命周期 |
| `NaviBridge.kt` (65KB) | 高德导航 SDK ↔ 协议桥接（转向、车道、摄像头、路况） |
| `RoutePlanActivity.kt` (64KB) | 路线规划（驾车/骑行/摩托车网页规划） |
| `BleLink.kt` (45KB) | 扫描/连接/配对/MTU/分片队列/ACK/指数退避重连 |
| `SingleEngineSession.kt` (43KB) | 读秒引擎会话 |
| `MapFeeder.kt` (37KB) | 地图供给调度（核心算法，见 §7.4） |
| `AmapShare.kt` (36KB) | 高德能力共享/Key 校验 |
| `NavActivity.kt` (33KB) | 导航界面 |
| `MotorWebPlannerActivity.kt` (33KB) | 网页摩托车路线规划 |
| `AmapCaptureHost.kt` / `AmapSdkRaster.kt` | 渲染抓图与栅格化 |
| `TrafficLightOverlay.kt` | 读秒叠层 |
| `MusicBridge.kt` | 音乐控制（App 模式） |

### 7.3 iOS 结构

- SwiftUI，四栏（导航 / 轨迹 / 圆屏 / 我的），最低 iOS 15。
- 对应模块：`NaviBridge.swift`(61KB)、`ContentView.swift`(53KB)、`MapFeeder.swift`(42KB)、`BleLink.swift`(37KB)、`AmapShare.swift`(35KB)、`WebMotor.swift`(33KB)、`MapGeo.swift`、`RasterProcessing.swift`。
- 与安卓的差异：**无读秒**；UI 移植自 `coolcoolmanman-design/MotoNav`。
- `MotoNavShare` 是分享扩展（从高德/地图 App 分享路线进来），签名时要一起签。

### 7.4 地图供给策略（`MapFeeder` 的核心逻辑）

这是整个系统最"有含量"的部分：

1. **沿线预取**：按路线节点（`plan.nodes`）预取，而不是按当前位置临时抓。
2. **双阈值触发**：未确认时取"当前位置节点"，已确认且车速 ≥4km/h 时取"前一节点"，避免原地反复抓。
3. **跳过重复**：目标点与已确认块中心相差 <500m（或 <1 单位）且建筑已补齐 → 直接跳过。
4. **带宽预算**：按"待发字节 / 实测速率"估算传输时间，用来决定是否值得再抓一块。
5. **确认驱动**：`haveChunk && !chunkAcked` 时不抓新块——**必须等固件回 `K`**。这是防止"传一半又取消"的关键。
6. **失败退避**：抓图失败有冷却，锁屏时放宽（iOS Build16 重点修的就是这个）。
7. **取消语义**：换路线、换风格、停止导航 → `cancelBulk(TYPE_CHUNK, TYPE_RASTER)`，只取消地图，路线与位置继续。

---

## 8. 端到端地图管线

```
高德 SDK 渲染  →  截屏(TextureView/PixelCopy)  →  降采样到 2m/px
   →  RGB565 量化(4bit 调色板)  →  RLE 压缩  →  打包 'M' type=3 分片(485B/片)
   →  BLE 写入  →  固件收齐  →  回 K  →  备用缓冲解码(16ms/片)
   →  楼块继承  →  指针交换  →  下一帧地图直接画新图
```

**性能数据（上游实测，非同场景可比）**：

| 指标 | 早期 | 分步版本 |
| --- | --- | --- |
| 单次解码最长帧 | 339～358 ms | **约 123 ms** |
| 单次处理切片 | — | 最大 **16.35 ms** |
| 整图处理总时长 | — | 最长 **1.38 s**（低于 iOS 2 秒确认期限） |

官方明确说明：**这是桌面/模拟计时的数字，不是圆屏实际帧率，也不是全场景上限**。iOS 侧实测场景是 7.4km 路线、120km/h 模拟、手机锁屏，用户确认"无肉眼可见卡顿"。**安卓本轮没有实路复测**。

---

## 9. 构建与烧录

### 9.1 固件编译

```sh
# 依赖：Arduino CLI + Espressif ESP32 Arduino Core 3.3.10（必须是这个版本）
python3 firmware/build.py          # 或 firmware/build.ps1 -Board 175
# 输出：firmware/dist/175/panel0
```

FQBN：`esp32:esp32:esp32s3:FlashSize=32M,PartitionScheme=app5M_fat24M_32MB,PSRAM=opi,CDCOnBoot=cdc`

注意：必须保留 `firmware/libraries/MotoNavIpcStackGuard`，脚本会显式传 `-Wl,--wrap=xTaskCreatePinnedToCore`。

### 9.2 安卓普通版

```powershell
# 仓库根目录
.\一键打包-普通版.bat
# 或
.\Build-Personal.ps1 -JavaPath 'D:\Tools\jdk-17' -SdkPath 'D:\Android\Sdk' -GradlePath 'D:\Tools\gradle-8.10.2\bin\gradle.bat'
```

- 环境：**JDK 17**（不要 JDK 25）、Android SDK 35、Gradle 8.10.2。
- 产物：`output/MotoNav-personal.apk` + `output/Application-info.txt`（包名、证书 SHA1）。
- 首次自动生成个人包名 + 本机签名，务必备份 `android/standard/personal.properties` 与 `keystore/`。

### 9.3 安卓读秒版

```powershell
.\一键打包-读秒版.bat
# 或
python build-countdown.py --apktool 'D:\Tools\apktool.jar' --gradle 'D:\Tools\gradle-8.10.2\bin\gradle.bat' `
  --sdk 'D:\Android\Sdk' --java-home 'D:\Tools\jdk-17' --zig 'D:\Tools\zig-0.13.0\zig.exe'
```

- 额外依赖：**apktool 2.12.1、Zig 0.13.0、Python 3**。
- 脚本自动下载 `provider.apk`（约 148MB）到 `android/countdown/inputs/`，按 `provider.json` 校验。
  已核对到的 SHA256：`f0fe164279a6d60bd83d926a32d47f335f044faf9c0d37564b49655e95db0141`
  这个值来自 QQ 群说明 PDF，**与仓库 provider.json 是否一致请在构建时让脚本自己校验**——不要手填。
- 下载失败可手动放到 `inputs/provider.apk`，或加 `--provider` 指定路径。
- 备份项：`personal.properties` + `.local/debug.keystore`（**点号目录容易漏**）。

### 9.4 iOS

```sh
bash build-ios.sh     # Xcode + CocoaPods 1.16.2
# 输出：output/ios/MotoNav-0.16.2-build16-unsigned.ipa
```

IPA 未签名，需用 Sideloadly / iLoader 自签；免费账号 7 天续签。App 内需填自己的高德 iOS Key（Bundle ID 必须与签名后的实际 Bundle ID 一致）。

### 9.5 一键烧录包内部机制（你手上这份，逐行核对过）

`flash.ps1` 做了这些事，你可以据此判断它是否可信：

1. **清单校验**：读 `firmware-manifest.json`，强制 `schema==1`、只有一块板、`board.id=='175'`、版本必须是 `7.12.10-pages.4`——**版本不符直接退出**。
2. **路径穿越防护**：固件路径必须落在本包 `firmware\` 目录下，否则报"路径超出本包 firmware 目录"。
3. **双重完整性校验**：文件大小 + SHA256 必须与清单一致。
4. **镜像格式校验**：
   - 应用镜像：偏移处首字节必须是 `0xE9`（ESP32 镜像 magic），`offset+12` 的 chip id 必须是 9（ESP32-S3）。
   - 完整镜像：`0x0` 是 `0xE9`，`0x8000` 处是 `0xAA 0x50`（分区表 magic）。
5. **两种烧录模式**：
   | 模式 | 地址 | 参数 | 影响 |
   | --- | --- | --- | --- |
   | 应用升级（默认） | `0x10000` | 无 `--erase-all` | 保留配对与设置（NVS 不动） |
   | 首次安装/救砖 | `0x0` | `--erase-all` | 整片擦除，清空所有数据，需输入 `YES` 二次确认 |
6. **降级重试链**：460800 → 失败降 115200 → 再失败提示按住 BOOT 进下载模式，`--before no-reset` 再试一次。
7. **校验不动硬件**：`校验文件.bat` 只跑 `esptool version` + 文件检查，不访问串口。

**结论：这份脚本的工程质量高于一般"一键刷机包"，可以放心用。** 唯一注意：它硬编码只认 `7.12.10-pages.4`，你换成别的固件版本它不会跑——这是有意的防呆，不是 bug。

---

## 10. 你手上的材料逐项核对

### 10.1 文件清单

| 文件 | 大小 | 核对结果 |
| --- | --- | --- |
| `MotoNav-1.75-v7.12.10-pages.4-Universal-Flasher.zip` | 15,283,221 B | 与 Release `firmware-v7.12.10-pages.4` 的 14.6MB 包同名同版本 |
| 解压目录 | — | 含 `flash.ps1` / `backup.ps1` / 三个 .bat / `tools/esptool.exe`（5.3.0，无需本机 Python） |
| `firmware/panel0/..._app_0x10000.bin` | 1,288,656 B | SHA256 `6ee31c48...6da0b3` ✅ **与清单一致** |
| `firmware/panel0/..._full_0x0.bin` | 1,354,192 B | SHA256 `fc8d55d5...65e2210` ✅ **与清单一致** |
| `firmware-verification.json` | — | `imageHashesVerified: true`；`publicBinaryFlashedOnDevice: false`（公开镜像没在实物上验证过） |
| QQ 群说明 PDF | 10 页 | 2026-11-01 版新手说明：选版本 → 打包 → 申请 Key → 安装 → 烧录 → 天气配置 |

### 10.2 关键差异：你在 pages.4，上游在 phone.8

| 项目 | pages.4（你手上，10-27） | phone.8（上游，11-01） |
| --- | --- | --- |
| 开机稳定性（IPC 栈越界） | ✅ 已修 | ✅ 保留 |
| 固定页面顺序 + 主页时钟 | ✅ | ✅ |
| 换图流畅度 | 整块解码，最长帧 339~358ms | **分步解码，约 123ms**；整图 1.38s |
| 楼块继承 `#BC` | ❌ | ✅（旧 App 不发 → 行为不变） |
| 等待定位 `#NW` / 到达停留 `#NA` | ❌ | ✅ |
| 与 iOS Build16 配对 | 可用但换图会卡 | ✅ 官方联调版本 |
| 适用手机 | 安卓两版 | 安卓两版 + **iOS 0.16.2** |

**结论**：如果你只用安卓，pages.4 完全够用；如果你要用 iPhone，或者受不了换图时的顿挫，升到 phone.8。升级走"应用升级"（0x10000）保留配对和设置。

⚠️ 注意一个仓库自身的小矛盾：`android/standard/README.md` 里写"当前 1.75 通用固件为 `7.12.10-pages.5`"，而 `firmware/RELEASE_VERSION` 和主 README 都是 `7.12.10-phone.8`。**以 `RELEASE_VERSION` 和 Release 页为准**，standard 那个 README 是上一轮（10-31）没同步的残留。

### 10.3 你的 fork 现状

```
sbcyk/MotoNav
├── fork: true, parent: zyn950929/MotoNav
├── created: 2026-11-02T05:51:32Z
├── pushed:  2026-11-01T16:23:46Z   ← 注意：早于创建时间，说明是创建时同步的上游提交
├── branches: main → e12251629c
└── 自有提交：0
```

**这意味着**：fork 目前只是"快照备份"。要真正开始改，建议：

```bash
git clone https://github.com/sbcyk/MotoNav.git
cd MotoNav
git remote add upstream https://github.com/zyn950929/MotoNav.git
git fetch upstream

# 建立自己的工作分支，永远不要直接改 main
git checkout -b feat/my-change

# 同步上游
git checkout main && git merge --ff-only upstream/main && git push origin main
```

这样你的改动和上游更新可以一直用 `rebase` 保持线性，出问题也能干净回退。

---

### 10.4 最新发布包已下载并校验（2026-11-02）

存放目录：`C:\Users\codem\Documents\MyFile\moto\latest-2026.11.01-r2\`

| 文件 | 大小 | 对发布页 SHA256SUMS 的校验 |
| --- | --- | --- |
| `MotoNav-1.75-v7.12.10-phone.8-Universal-Flasher.zip` | 15,337,216 B | ✅ `76ff0ce2…4fdd2d1a` |
| `MotoNav-0.16.2-build16-unsigned.ipa` | 45,694,573 B | ✅ `97e81921…04cba09c` |
| `MotoNav-Firmware-Source-1.75-v7.12.10-phone.8.zip` | 14,348,840 B | ✅ `95876063…9ec03b0` |
| `MotoNav-Android-Countdown-8.3.26-single.32-fresh.1-Source.zip` | 610,120 B | ✅ `8751de83…938b02` |
| `START-HERE.txt` | 1,770 B | ✅ `72157cc4…78e59d3` |

包**内**再校验一层（解压后比对 `firmware-manifest.json`）：

| 镜像 | 字节 | SHA256 | 结论 |
| --- | --- | --- | --- |
| `…_app_0x10000.bin` | 1,293,552 | `80942F65…FB6787DF` | ✅ 与 manifest 一致 |
| `…_full_0x0.bin` | 1,359,088 | `3EC3F1A4…68B395B6` | ✅ 与 manifest 一致 |

**和 pages.4 包的两处结构差异**：

1. **不再附带 `firmware-verification.json`**（pages.4 里那份写了"8 次受控重启""公开镜像未刷入实物"的验证记录）。phone.8 改为包内 `SHA256SUMS.txt` 覆盖全部 12 个文件，验证结论挪到了 `docs/RELEASE-IOS-FIRMWARE-2026-11-01.md`。
2. `flash.ps1` 仍然把版本串硬编码为 `7.12.10-phone.8`，版本不符直接退出——防呆逻辑与上一版一致，只是常量换了一个。

**IPA 内部实测**（解包读 Info.plist）：

| 项 | 值 |
| --- | --- |
| Bundle ID | `com.example.motonav` |
| 版本 | 0.16.2（Build 16） |
| MinimumOSVersion | 15.0 |
| `UIBackgroundModes` | `location`、`bluetooth-central`、`audio` |
| URL Scheme | `motonav://` |
| 内嵌扩展 | `Payload/MotoNav.app/PlugIns/MotoNavShare.appex` → `com.example.motonav.share` |
| 签名状态 | **无 `embedded.mobileprovision`**，确为未签名包，必须自签后才能装 |

---

## 11. 上手路线（按顺序，别跳）

### 第一步：让屏幕先亮起来（半天）

1. 下载 / 使用手头这份 `pages.4` 一键包，**完整解压**（不要在压缩包里双击）。
2. 用**能传数据**的 USB 线连接圆屏，关掉串口监视器等占用程序。
3. 双击 `一键烧录.bat`：
   - 屏幕上已有 MotoNav → 选 `1`（升级，写 0x10000）
   - 全新板子或救砖 → 选 `2`（完整刷写，会清空，输入 `YES`）
4. 输入实际 COM 号（先看窗口列出的串口列表）。

**验收**：圆屏出现开机动画 → 主页显示时间日期 → 蓝牙名 `MotoNav-XXXX` 可被手机搜到。
**失败处理**：换数据线 → 换 USB 口 → 按住 BOOT 再复位进下载模式 → 重试。**看到"没有串口"不等于刷成功。**

### 第二步：把 App 装到手机（半天到一天）

1. 装 WorkBuddy（或自己配环境），获取仓库源码。
2. 先打包**普通版**（步骤最少，不碰 provider.apk）：`一键打包-普通版.bat`。
3. 拿到 `output/MotoNav-personal.apk` + `Application-info.txt`。
4. 用 **Application-info.txt 里的包名 + 证书 SHA1**（大写十六进制、冒号分隔、20 组）申请自己的高德 Key。
5. 手机安装 → App 内填 Key → 授权定位/蓝牙/通知 → 连接圆屏。

**验收**：首页能定位、能规划路线、圆屏能显示地图和转向。
**地图不出图排查顺序**：包名/SHA1 与 Key 是否匹配 → Key 平台类型 → 网络/定位权限 → 是否覆盖安装了不同签名的包。

### 第三步：动源码（按需）

建议顺序：**先改手机端，再改固件**。原因：手机端改坏了重装就行；固件改坏了要重新烧录，且调试靠串口。

| 你想做的事 | 改哪里 | 风险 |
| --- | --- | --- |
| 换 UI 布局/配色 | Android `NavUi.kt` / `MainActivity`；iOS `ContentView` | 低 |
| 换地图源 | `MapFeeder` + `AmapCaptureHost`/`AmapShare` | 中（Key、坐标系、抓图 API 都耦合高德） |
| 加新的屏上显示项 | 手机加 `'B'` 图栏 + 固件加 `IMG_SLOTS` | 中（栏位是硬编码的） |
| 改地图编码/压缩 | 手机编码 + `RasterDecoder.h` 对称改 | **高**（两侧必须同时刷，无版本号兜底） |
| 加新指令 | `CommandReceiver.h` 加 `#X,` 分支 + 手机发送 | 低（旧固件会忽略未知 `#` 指令） |

**固件调试建议**：`FirmwareConfig.h` 里把 `DEBUG_SERIAL` 改成 1，串口 115200 能看到每条收到的文本指令。别在量产固件里留这个。

---

## 12. iOS 侧载部署（iPhone 16 Pro / iOS 27）

### 12.1 结论先行

| 问题 | 答案 |
| --- | --- |
| iPhone 16 Pro + iOS 27 能装吗？ | **能。** App 最低要求 iOS 15，设备与系统版本都在范围内；`0.16.2 Build16` 就是这个固件世代对应的版本 |
| iLoader + SideStore 可行吗？ | **可行，这是目前最稳的免费路线**（iLoader 负责首次装机 + 配对文件，SideStore 负责日常签名与续签） |
| 需要 LiveContainer 吗？ | **不需要，而且对这个 App 是负优化**（原因见 §12.3） |
| 代价是什么？ | 免费 Apple ID：证书 **7 天**、同时最多 **3 个 App**（含 SideStore）、每周 **10 个新 App ID**；到期不续签就打不开 |
| 还缺什么？ | **iOS 版没有红绿灯读秒**（见 §12.7），这是产品能力差异，不是部署问题 |

### 12.2 三个工具各自干什么

| 工具 | 运行位置 | 它解决什么 | 你是否需要 |
| --- | --- | --- | --- |
| **iLoader** | 电脑（Win/Mac/Linux，Rust + Tauri，MIT） | 把 SideStore 装进手机；自动生成并把 `rppairing` / `lockdown` 配对文件塞进 App 沙盒；也能直接签任意 IPA | **需要**，只在第一次（和重置后）用 |
| **SideStore** | 手机 | 用你自己的 Apple ID 给 IPA 签名并安装；7 天续签在手机上完成，不用电脑 | **需要**，日常主力 |
| **LiveContainer** | 手机 | 在一个已签名宿主里跑多个 guest App，绕过"3 个 App"上限 | **不需要** |

关键理解：iLoader 不是"安装器替代品"，它是 SideStore 的**配对环境搭建器**。SideStore 装好并配好之后，装 MotoNav 这件事跟电脑再无关系。

### 12.3 为什么单装一个 App 不需要 LiveContainer（四条硬理由）

1. **名额根本用不完。** 免费账号 3 个名额：SideStore 占 1、MotoNav 占 1，还剩 1 个。LiveContainer 存在的唯一意义就是突破 3 个上限，你没这个问题。
2. **后台模式不跟着走。** guest App 继承的是**宿主**的 entitlement，不是自己的。我解包核过 MotoNav 的 `Info.plist`（`Payload/MotoNav.app/Info.plist`）：

   ```xml
   <key>UIBackgroundModes</key>
   <array>
     <string>location</string>
     <string>bluetooth-central</string>
     <string>audio</string>
   </array>
   ```

   锁屏后继续接收定位、继续往圆屏发地图，全靠这三条。放进容器后，系统认的是 LiveContainer 的后台权限——**这个 App 的核心体验正好落在容器最容易出问题的地方**。
3. **扩展与深链都不支持。** LiveContainer 官方 FAQ 明确写：guest App 不支持 widget / app extension；guest 的 URL scheme 也不注册进 LaunchServices。MotoNav 的 `motonav://` 深链和分享扩展会一起失效。
4. **权限是全局共享的。** 你在容器里给的定位/蓝牙授权，是对 LiveContainer 整体的授权；以后再往容器里塞别的 App，数据边界就混了（官方 README 也承认 guest 之间不是强沙箱）。

> 一句话：**LiveContainer 是给"想装十几个 App 又不买证书"的人用的；你只装一个，它只会给你增加故障面。**

### 12.4 四条路线对比

| 路线 | 首次成本 | 后续维护 | 评价 |
| --- | --- | --- | --- |
| **A. iLoader → SideStore → 装 IPA** | 一台 Windows + 约 30 分钟 | **每周在手机上点一次 Refresh**（需 Wi-Fi + LocalDevVPN） | ✅ **推荐** |
| B. iLoader 直接签 IPA 装 | 更短 | **每 7 天必须插电脑重签** | 只适合试水 |
| C. 付费开发者账号（$99/年） | 注册 + 付费 | 一年一次，且解除 3 个 App 限制 | 真当车载设备用就值 |
| D. SideInstaller（iOS 27 免电脑） | 纯手机，需装 DNS 描述文件 + 第三方证书 | 同 A | 没电脑时的备选；你有 PC，iLoader 更稳 |

补充：iOS 27 的一个新变化是**设备可以自配对**（SideInstaller 的 `deviceCanSelfPair` 在 27 及以上为真），所以"D 路线不需要电脑"才成立。你在 iOS 27 上走 A 路线时，iLoader 依然会走 USB 完成配对，成功率更高。

### 12.5 A 路线操作步骤

**前置（10 分钟）**

1. 手机：设置 → 隐私与安全性 → **开发者模式** → 打开 → 重启。
2. **准备一个专用 Apple ID**，不要用你的主账号。免费证书反复签发、被风控、被锁都不是新闻，用小号是最省心的隔离手段。
3. Windows：装 iTunes（微软商店版即可）或"Apple 设备"组件，保证 iLoader 能通过 USB 认到手机。
4. 手机连 Wi-Fi，从 App Store 装 **LocalDevVPN**（SideStore 的本地回环通道，不经过外部服务器）。

**装 SideStore（15 分钟）**

5. 电脑打开 iLoader → 登录那个小号（开了双重认证会要验证码）→ 选中设备 → 点 **SideStore (Stable)**。
6. iLoader 会自动完成：下载 → 签名 → 安装 → 把配对文件放进 SideStore 沙盒。
7. 手机：设置 → 通用 → VPN 与设备管理 → **信任**你的 Apple ID 证书。
8. 打开 LocalDevVPN → **Connect**（安装和刷新期间必须保持连接）。
9. 打开 SideStore → 选配对文件（`On My iPhone → SideStore → ALTPairingFile.mobiledevicepairing`）→ My Apps → 登录**同一个**小号 → 点一次 Refresh 验证链路通。

**装 MotoNav**

10. 把 `MotoNav-0.16.2-build16-unsigned.ipa` 传到手机（文件 App / 隔空投送 / 数据线）。
11. SideStore → My Apps → 左上角 **+** → 选这个 IPA → 提示扩展时选 **Keep App Extensions (Use Main Profile)**。
12. 首次打开按提示授权：**定位选"始终允许"**（锁屏导航必需）、蓝牙、通知。
13. App 内填自己的**高德 iOS Key**。Key 的 Bundle ID 必须与签名后的实际 Bundle ID 一致——默认是 `com.example.motonav`；如果你在 SideStore 里改过 App ID，就要按新 ID 重新申请。

### 12.6 五个坑（按发生概率排）

| # | 现象 | 原因 | 处理 |
| --- | --- | --- | --- |
| 1 | 安装失败，报签名/扩展相关错误 | 分享扩展 `com.example.motonav.share` 需要独立 App ID 与 profile，免费账号下最容易卡这里 | **兜底**：解压 IPA → 删掉 `Payload/MotoNav.app/PlugIns/MotoNavShare.appex` → 重新压成 zip 改后缀 `.ipa` → 再装。主 App 完整可用，只失去"从高德/地图 App 分享路线进 MotoNav" |
| 2 | 地图一片空白 | 高德 Key 与 Bundle ID 不匹配，或 Key 平台类型选错 | 核对 App 实际 Bundle ID → 重新申请 Key → 重填 |
| 3 | 第 8 天 App 打不开/闪退 | 7 天证书过期 | 连 Wi-Fi + LocalDevVPN → SideStore → Refresh All。**骑车前一定先看一眼剩余天数** |
| 4 | 报 "Maximum App ID limit has been reached" | 每周 10 个新 App ID 用完了 | iLoader 的 App IDs 管理里删掉不用的；或等下周 |
| 5 | 登录报 503 / -80045 / 账号被锁 | Apple 登录风控或 Anisette 服务波动 | 换 Anisette 服务器、换个时间段重试；这也是建议用小号的原因 |

> 关于坑 1，我核过代码：分享扩展**不使用 App Group**，它只是读取分享内容、拼一个 `motonav://...` URL，再用私有 `openURL:options:completionHandler:` 唤起主 App。所以删掉扩展不会破坏主 App 的任何数据，只是少一个入口。

### 12.7 必须先接受的产品事实：iOS 没有读秒

- 红绿灯读秒只存在于**安卓读秒版** `8.3.26-single.32-fresh.1`，且官方定性为实验功能，不保证每个路口都有数据。
- iOS 0.16.2 明确写"**不含红绿灯读秒**"。
- 所以：**如果你就是冲着读秒来的，iPhone 这条路直接不成立。** 可选方案是拿一台安卓机当导航主机，iPhone 只当备用。这是产品能力问题，跟侧载工具无关。

### 12.8 什么时候该掏 99 美元

| 信号 | 说明 |
| --- | --- |
| 你已经把它当"车载设备"而不是"玩具" | 周更这件事，在出门骑车前发现 App 打不开是不可接受的 |
| 你不想每周记着连 Wi-Fi 点刷新 | 付费后证书 1 年有效，SideStore 仍可用，只是不用周更 |
| 你想装到第二台设备 / 帮朋友装 | 免费账号只有 3 个 App 名额，且绑定你的 Apple ID |

注意：付费也不能绕过"必须自己签名安装"这一步，只是把 7 天变成 1 年、把 3 个变无限。

### 12.9 一个务实的长期组合

```
圆屏固件：7.12.10-phone.8（Windows 一键包）
手机端　：iOS 0.16.2 Build16（SideStore 签名安装）
账号　　：专用小号（不要用主 Apple ID）
维护　　：每周固定一天连 Wi-Fi + LocalDevVPN → Refresh All
备份　　：把 IPA、固件 ZIP、SHA256SUMS 一起存好（上游删包或改版时不至于断供）
```

---

## 13. 改造要点与坑

### 13.1 协议扩展的三条铁律

1. **新指令必须 `#` 开头**。`CommandReceiver.h` 最后有一句 `if (m.startsWith("#")) return;`——未知 `#` 指令会被安全忽略；但不带 `#` 的会被当成"方向,距离"导航指令，直接把 UI 弄乱。
2. **能力先上报，再使用**。参考 `CAP,HID,1` / `#GB?` / `#BC` 的模式：新固件主动报能力，手机收到才发新指令。这样旧固件 + 新 App 不会互相伤害。
3. **改动对称改**。手机编码和固件解码是两份代码，没有共享 schema 文件。你改了 `'M'` 头或 RLE 规则，必须同时刷固件和装新 App，中间状态一定出问题。

### 13.2 已知的坑

| 坑 | 说明 |
| --- | --- |
| 包名/签名绑定 | 覆盖升级必须同包名同签名；读秒版签名丢了脚本会**直接报错停止**（不会偷偷生成新的），这是好事 |
| 21 字符限制 | 读秒版自定义包名有原生路径长度限制（21 个 ASCII），超长直接拒绝 |
| `app/build/outputs` 的 APK | 只是编译验证产物，**不是**可安装的读秒版 |
| NVS 布局 | `Preferences` 命名空间 `motonav`，键 `qspi`/`rot`/`rotd`/`bootbrand`/`mediahid`/`fastf`。改键名会导致老设备设置丢失 |
| 分区表 | 必须是 `app5M_fat24M_32MB`。分区不同时“应用升级”会失败，只能整片刷（16MB 旧固件升 2.0.0 即属此例） |
| 1.85B 分支 | 仓库里有 `firmware/boards/185b`，但固件停在 7.12.3-185B，**不能混刷 1.75 的镜像** |
| iOS 后台限制 | 锁屏能继续发**已准备**的地图；偏航进未缓存区域仍需回到前台补图 |
| 无实车回归 | 官方自己写明"测试回放不等于实路验证"，你的改动更需要自己上路测 |

### 13.3 代码质量评估（客观说）

**好的地方**：
- 缓冲区边界检查做得认真（每个 `parse*` 函数开头都校验 `len`、上限、`n < x`）。
- 大块接收有幂等设计（重复末包只再确认，不重启任务），这类分布式思路在个人项目里少见。
- 有 24 个 C++ 单测（HID 46 项、AMS 33 项、旋转 394 项、栅格工作队列专项 fixture），GitHub Actions 跑 build + 包校验。
- 文档极其详尽，甚至写了"哪些没验证"。

**要注意的地方**：
- **注释即变更日志**：`v6.7`/`v7.12.10` 混在注释里，没有 CHANGELOG 结构，读代码要连注释一起读。
- 单文件巨大：`MainActivity.kt` 104KB、`NaviBridge.kt` 65KB，几乎没有分层。
- 魔术数字多：`200*1024`、`485`、`16ms`、`1.8s` 散落各处，没有集中配置。
- 全部逻辑在一个 `.ino` 里按 include 顺序展开（作者明确说这是为了保持编译顺序和内联优化）——你加新头文件必须注意包含位置。
- CI 覆盖构建与包校验，**不覆盖实机行为**。

---

## 14. 风险与红线

1. **许可**：非商业使用。二次分发、售卖、商用集成前先读 `LICENSE.md`，必要时联系作者。
2. **读秒的合规性**：读秒数据来自第三方组件与公开数据源，官方反复声明"不保证有效、不补造数据、以现场信号为准"。**不要把它当成交通信号依据**。
3. **行车安全**：行驶中不要操作设备。这句话在文档里出现多次，不是免责套话——圆屏在强光下的可读性、手套操作的准确性都是真实问题。
4. **第三方 SDK**：高德 SDK 有商用授权要求；你申请的是个人开发者 Key，别用在商业产品上。
5. **`provider.apk`**：148MB 第三方构建依赖，不属于开源代码。不要传播、不要当成品安装、不要替换成"随便一个最新版高德"（有 SHA256 校验会拒绝）。
6. **隐私**：源码不含作者的个人 Key、Cookie、签名和天气 Host。你也不要把自己的这些提交到公开仓库（`.gitignore` 已覆盖，但读秒版的 `personal.properties` 容易误提交）。

---

## 15. 附录

### A. 关键常量速查

| 常量 | 值 | 位置 |
| --- | --- | --- |
| `LCD_WIDTH/HEIGHT` | 466 / 466 | pin_config.h |
| `MAP_MAX` | 200 KB | MapState.h |
| `ROUTE_MAX` | 96 KB | MapState.h |
| `RASTER_MAX_BYTES` | 500 KB | MapState.h |
| `RASTER_MAX_PX` | 1300×1300 | MapState.h |
| `RASTER_BUF_BYTES` | 82×82×128 ≈ 840 KB | MapState.h |
| `FEAT_MAX` / `ROUTE_PTS` / `POLY_PTS` | 7200 / 24000 / 4096 | MapState.h |
| `IMG_SLOTS` / `IMG_MAX` | 13 / 8192 | DeviceContext.h |
| `RXQ_SLOTS` / `RXQ_MAX` | 48 / 512 | DeviceContext.h |
| `STALE_MS` | 6000 | FirmwareConfig.h |
| `STAGE_FAR_M` / `STAGE_NEAR_M` | 500 / 100 | FirmwareConfig.h |
| 循环内最多消费消息 | 30 条 | MotoNav.ino |
| 栅格单片目标耗时 | ~16 ms | release notes |

### B. 术语

| 术语 | 含义 |
| --- | --- |
| pages / junction / phone | 固件版本代号后缀，`phone.8` 是当前跨平台共用版本 |
| ghost | "原路线"，走过的路线用灰色画的那条 |
| 楼块继承 / building carry | 新旧地图块重叠时复用旧图的建筑轮廓，减少闪烁与缺失 |
| VCE | 旧版"罪恶都市"轮廓扩展块（zlib），新 App 不再发送 |
| single.32-fresh.1 | 读秒版的构建代号 |
| AMS | Apple Media Service，读 iPhone 当前播放器元数据 |
| provider.apk | 读秒版依赖的第三方基础包（148MB） |

### C. 参考链接

- 上游仓库：https://github.com/zyn950929/MotoNav
- 你的分支：https://github.com/sbcyk/MotoNav
- 最新发布页：https://github.com/zyn950929/MotoNav/releases/tag/motonav-2026.11.01-r2
- 文档目录：https://github.com/zyn950929/MotoNav/blob/main/docs/README.md
- 蓝牙/媒体协议：https://github.com/zyn950929/MotoNav/blob/main/docs/BLE-HID.md
- iOS UI 来源：https://github.com/coolcoolmanman-design/MotoNav
- esptool（烧录工具）：https://github.com/espressif/esptool

### D. 待确认事项（我未能验证的部分）

| 项 | 状态 | 建议 |
| --- | --- | --- |
| 板载 PSRAM 具体容量 | 按微雪规格应为 8MB（R8），**未在我这边实测** | 拿到板子后 `esptool flash_id` / Arduino 串口打印确认 |
| 读秒数据来源与覆盖率 | 文档只写"第三方组件 + 公开数据"，未说明具体源 | 实际路测几个常走路口再判断可用性 |
| iOS 实机行为 | 无 Apple 设备验证 | 只在需要 iOS 时再投入 |
| pages.4 → phone.8 升级后的实际差异 | 仅有官方文字描述 | 可先备份 NVS（包内有 `备份原厂.bat`）再升级 |
| 1.85B 板型 | 仓库有源码目录，固件停在 7.12.3-185B | 不打算用就不用管，**千万别混刷** |
| `provider.apk` SHA256 与仓库 `provider.json` 是否一致 | PDF 里的值与仓库文件我未逐一比对 | 让构建脚本自己校验，别手填 |

---

*本文档基于 2026-11-02 的仓库状态与本地材料编写。上游更新频繁（近两周有 10+ 次提交），引用具体行号或常量前建议先核对当前 HEAD。*
