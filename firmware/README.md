# 1.75 圆屏固件

适用于 **微雪 ESP32-S3-Touch-AMOLED-1.75**。iOS 客户端直接使用这份固件，不需要按手机系统分别烧录。公开源码及镜像使用通用 MotoNav / 品牌开机，不包含私人开机资源。当前版本见 `firmware/RELEASE_VERSION`，与 `src/core/FirmwareConfig.h` 的 `FW_VERSION` 同步。

## 获取与烧录

本仓库不发布预打包 ZIP，产物按文末「自行编译与打包」生成。拿到一键包后完整解压，双击 `一键烧录.bat`，按提示选自己的串口。

已有同板型、同分区 MotoNav，选默认“应用升级”，写入 `0x10000`，保留配对和设置。首次安装或救砖才选完整安装，**会清空设置**。

**不能刷到 1.75C、1.85B 或 M5Stack。** `firmware/boards/185b/` 是另一块板子的旧镜像（7.12.3-185B），原样保留，不在维护范围。

## 收图与兼容

地图清空备用缓冲、解码和楼块继承拆成小步，主循环每轮目标处理约 16 毫秒；旧图继续显示，新图全部完成后才切换并确认。重复末包只查询确认，不会重启未完成任务；断连、换图、换风格、停止导航或改变楼块开关时取消旧任务。

地图格式、导航、路线、车道、摄像头、读秒、音乐和天气协议保持兼容。楼块保留仍由 `#BC` 显式开启，未发送该指令的旧客户端走默认行为。页面顺序、主页 24 小时时间与日期、旋转记忆、音乐、天气、电池空闲关机和插电保护都保留。

## 测试

生产解码器的像素/边界/进度回归和实际接收队列测试覆盖取消、重复包、会话变化与延迟确认；页面、旋转、电源和媒体测试继续运行。桌面计时不能当作圆屏帧率。打包时会跑包内校验 `firmware/tests/verify_windows_package.py`，只核对文件与清单，不访问串口、不写设备；历史构建与包校验记录见[发布存档](../docs/archive/RELEASE-IOS-FIRMWARE-2026-11-01.md)。

## 自行编译与打包

安装 Arduino CLI、Espressif ESP32 Arduino Core **3.3.10**；依赖库已放在 `libraries/`。在仓库根目录执行：

```sh
python3 firmware/build.py
```

Windows：`firmware/build.ps1 -Board 175`。输出 `firmware/dist/175/panel0`。

生成一键包还要 esptool 工具目录（`esptool.exe` 与官方说明）：

```sh
python3 firmware/package_flasher.py --tools-dir <Windows esptool 目录>
```

产物在 `output/firmware/<版本>/`，运行 `--help` 看全部参数。用一键包的人不需要另装 Arduino、Python 或 Xcode。
