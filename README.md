# MotoNav

iPhone + ESP32-S3 圆屏导航。手机端用高德 SDK 渲染地图并截屏压缩，经 BLE 推到圆屏显示；圆屏只做解码与绘制，不做导航计算。

## 硬件

| 项 | 参数 |
| --- | --- |
| 板子 | Waveshare ESP32-S3-Touch-AMOLED-1.75（圆屏） |
| MCU | ESP32-S3，32MB Flash，8MB OPI PSRAM，分区 `app5M_fat24M_32MB` |
| 屏幕 | CO5300 QSPI，466×466 |
| 触摸 | CST92xx（I2C） |
| 电源 | AXP2101 |

只适用这个板型。1.75C、1.85B、M5Stack 不能刷本仓库的镜像。

## 目录

| 路径 | 内容 |
| --- | --- |
| `ios/` | iPhone App，Swift + CocoaPods（高德 AMapNavi / AMapSearch） |
| `firmware/` | 固件源码、烧录包、打包脚本 |
| `android/` | 安卓普通版与读秒版源码，保留但不维护 |
| `docs/` | 技术文档、需求清单、CI 说明 |
| `scripts/` | iOS 打包脚本 |

## 构建

**iOS**（需 macOS + Xcode + CocoaPods 1.16.2）

```sh
bash build-ios.sh              # 产出 output/ios/*.ipa（未签名）
```

或在 Actions 里手动跑 `iOS Quick Build (unsigned IPA)`。IPA 需自行签名安装。

**固件**（需 arduino-cli + Espressif ESP32 Arduino Core 3.3.10）

```sh
python3 firmware/build.py      # 产出 firmware/dist/175/panel0/
```

FQBN 与版本同步要求见 `AGENTS.md`。

**烧录**：解压对应的 Windows / macOS 一键包，已有同分区固件时选“应用升级”写 `0x10000`；首次安装、救砖、从 16MB 分区旧固件升级必须整片刷，会清 NVS。

**安卓**：见 `android/standard/README.md`、`android/countdown/README.md`，本仓库不再发预签名 APK。

## 文档

| 内容 | 位置 |
| --- | --- |
| 规范、架构、构建约束、版本同步清单 | `AGENTS.md` |
| 协议、时序、地图管线 | `docs/MotoNav-技术文档.md` |
| 需求、进度、验收 | `docs/需求清单.md` |
| 版本改动 | `CHANGELOG.md` |
| iOS CI 用法 | `docs/IOS-CI-GUIDE.md` |
| 媒体键协议 | `docs/BLE-HID.md` |

## 许可

非商业使用，见 `LICENSE.md`。第三方 SDK、库与素材的许可见 `licenses/`；iOS UI 来源见 `ios/UI-SOURCE-NOTICE.md`。

行驶中不要操作设备。路线、图标、读秒均不能代替现场信号与标志。
