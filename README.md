# MotoNav

iPhone + ESP32-S3 圆屏导航。手机用高德 SDK 渲染地图、压成 4bit 调色板 + RLE 走 BLE 推给圆屏，圆屏只做解码和绘制，不参与导航计算。

只适用 Waveshare ESP32-S3-Touch-AMOLED-1.75（ESP32-S3 / 32MB Flash / 8MB OPI PSRAM / CO5300 QSPI 466×466 / CST92xx 触摸 / AXP2101）。1.75C、1.85B、M5Stack 刷不了本仓库的镜像。

改地图、路线、语音 → `ios/`；改界面、动画、图标、按键 → `firmware/`；动 BLE 字段两端一起改。

## 固件：编译 + 烧录

日常一条命令（要用 **PowerShell 7**，即 `pwsh`，系统自带的 `powershell` 不行）：

```powershell
pwsh -File firmware/flash-dev.ps1 -Build
```

它会先用 `build.py` 编译，再自动找 Espressif 串口（VID 303A），把 `firmware/dist/175/panel0/` 里最新的 `*_app_0x10000.bin` 写到 app 分区（`0x10000`）。**只写 app 分区，NVS 不动**——配对、屏幕方向、开机品牌、主题包都保留，写完由 esptool 自己做 hash 校验。

| 参数 | 作用 |
| --- | --- |
| 不加参数 | 只刷 `dist` 里最新的 app 镜像，不编译 |
| `-Build` | 先编译再刷；改过代码必须带，否则刷上去还是旧固件 |
| `-DryRun` | 只打印要执行的命令，不碰硬件 |
| `-Port COM7` | 指定串口；默认按 VID 303A 自动找，找到多个会报错让你指定 |
| `-Bin <路径>` | 指定镜像，默认挑 `dist/175/panel0` 里时间最新的 |
| `-Full` | 整片刷，**清空 NVS**，救砖用，要输入 `yes` 确认 |
| `-Baud 230400` | 线材差、经常掉线时降速，默认 460800 |

分开跑也可以：

```powershell
python firmware/build.py --cli "C:\Program Files\Arduino CLI\arduino-cli.exe" --jobs 4
pwsh -File firmware/flash-dev.ps1
```

`python firmware/build.py` 里 `--cli` 只有 arduino-cli 不在 PATH 时才需要写全路径。

刷不进去先看这三条：

1. 串口被串口监视器或 Arduino IDE 占着——先关掉。
2. 板子不是 VID 303A 的原生 USB（走 CH340/CP210x 转接板），脚本找不到串口，用 `-Port` 手动指定。
3. 镜像比源码旧——脚本会警告（只比修改时间），带 `-Build` 重来。

工具链前提：`arduino-cli` 装在 `C:\Program Files\Arduino CLI\`（`flash-dev.ps1` 里写死，装别处要改 `Invoke-Build` 那个 `$cli`），`esptool.exe` 跟着 Arduino ESP32 core 落在 `%LOCALAPPDATA%\Arduino15\packages\esp32\tools\esptool_py\` 下，脚本会自动挑最新版。

给别人装用的 Windows 一键包由 `firmware/package_flasher.py` 生成，包里的 `flash.ps1` 会先校验版本再刷；首次安装或从 16MB 旧固件升级必须整片刷（清 NVS）。

## iPhone App

```sh
bash build-ios.sh          # 需 macOS + Xcode + CocoaPods 1.16.2，产出 output/ios/*.ipa（未签名）
```

或在 Actions 里手动跑 `iOS Quick Build (unsigned IPA)`，产物同样未签名，要自己签了才能装，免费签名一般 7 天续一次。

首次使用要在 App 设置页填高德 iOS Key（Key 要绑定签名后的 Bundle ID），不填时搜索框下面会常驻提示。

版本号：App 只改 `MARKETING_VERSION`（`ios/MotoNav.xcodeproj/project.pbxproj`），固件要 `FW_VERSION`、`RELEASE_VERSION`、`flash.ps1` 三处一起改，细则和 tag 规范见 `AGENTS.md`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `ios/` | iPhone App 源码，Swift + CocoaPods（高德 AMapNavi / AMapSearch） |
| `firmware/` | 固件源码、编译与烧录脚本、一键包生成 |
| `docs/` | 技术文档、需求清单、CI 与素材说明 |
| `scripts/` | iOS 打包、首页画面生成 |

## 文档

| 内容 | 位置 |
| --- | --- |
| 规范、架构、编译约束、内存预算 | `AGENTS.md` |
| 协议、时序、地图管线 | `docs/MotoNav-技术文档.md` |
| 需求、进度、验收状态 | `docs/需求清单.md` |
| 版本改动 | `CHANGELOG.md` |
| iOS CI 用法 | `docs/IOS-CI-GUIDE.md` |
| 媒体键协议 | `docs/BLE-HID.md` |

## 来源与许可

fork 自 [CharlesXu/MotoNav](https://github.com/CharlesXu/MotoNav)，iOS 端重写并继续开发固件；iOS 界面布局参考 [coolcoolmanman-design/MotoNav](https://github.com/coolcoolmanman-design/MotoNav)，参考范围见 [UI-SOURCE-NOTICE.md](ios/UI-SOURCE-NOTICE.md)。版本号与上游独立。

非商业使用，见 `LICENSE.md`；第三方 SDK、库与素材的许可见 `licenses/`。

行驶中不要操作设备，路线和图标不能代替现场信号与标志。
