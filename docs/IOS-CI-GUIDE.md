# MotoNav iOS — GitHub Actions 出包指南

目标：在 Windows 上改 SwiftUI 布局/样式 → 云端 macOS 编译 → 下载 unsigned IPA → 本地自签装机。

---

## 0. 事实核对（2026-11-03）

| 项 | 值 |
|---|---|
| 你的 fork | `github.com/sbcyk/MotoNav`，public，main 为纯镜像 |
| fork 的 parent | `CharlesXu/MotoNav`（工作流里仍引用旧名 `zyn950929/MotoNav`，属正常） |
| iOS 源码 | `ios/` 172 个文件，`MotoNav.xcworkspace` + `Podfile` |
| 官方工作流 | `.github/workflows/release-ios.yml`（macos-26，跑全套测试，20~40 分钟） |
| **Actions 当前状态** | **未启用**（`/actions/workflows` 返回 `total_count: 0`），fork 默认关闭 |
| 构建脚本 | `scripts/build-ios-ipa.sh` → `CODE_SIGNING_ALLOWED=NO`，产物就是 unsigned IPA |
| 依赖 | CocoaPods **1.16.2**（写死），`pod install --deployment` |
| Pods | AMapNavi + AMapSearch（高德），平台 iOS 15.0 |
| 模拟器坑 | Podfile 强制 `EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64`，只影响模拟器，真机无碍 |

---

## 1. 启用 Actions（一次性，必做）

fork 出来的仓库 GitHub 不会自动注册工作流，必须先开：

1. 打开 `https://github.com/sbcyk/MotoNav/settings/actions`
2. **Actions permissions** 选 `Allow all actions and reusable workflows`
3. 点 **Save**
4. 打开 `https://github.com/sbcyk/MotoNav/actions`，若顶部出现 "Workflows aren't being run on this forked repository" 横幅，点 **I understand my workflows, go ahead and enable them**

验证：再访问 `/actions/workflows` 的 API 应该能看到 3 个 workflow。

---

## 2. 工作流已在仓库里

`.github/workflows/ios-quick.yml` 随仓库维护，不需要再复制或安装。clone 下来就有：

```bash
git clone git@github.com:sbcyk/MotoNav.git
cd MotoNav
```

要改构建行为（超时、缓存策略、产物命名）直接改这个文件。

> 这个工作流**只有手动触发**，没有 push / PR 触发器：推代码不会自动出包，要装机时到 Actions 页面点 `Run workflow`。

---

## 3. 触发构建

只有一种方式：手动。

Actions → 左侧 `iOS Quick Build (unsigned IPA)` → 右侧 `Run workflow` → 选分支（`main` 或你指定的分支），`note` 填本次改了什么（如 `boot-theme`，会进 artifact 文件名）→ Run。

**没有任何自动触发。** 这是刻意的：开发一批内容、自己确认没问题了，再出包装机。推代码不会占用构建时间。

`release-ios.yml`（官方那套，跑全套一致性测试）默认在网页上被禁用。改到协议层、需要完整回归时才临时 `Enable workflow` 手动跑一次，跑完再禁用。

---

## 4. 取包

构建完成后在 run 详情页底部 **Artifacts** 下载 `MotoNav-0.16.2-build16-unsigned-<note>-r<run号>.ipa`。
同时给了 `SHA256SUMS.txt` 和 `build-ios.log`（编译警告都在这）。

---

## 5. 自签装机

沿用你现在这套（文档第 12 章）：iLoader → SideStore → 装 IPA。

两点不能忘：
- **免费 Apple ID 证书 7 天过期**，每 7 天要在手机上续签一次；
- **Bundle ID 必须和签名后的实际 ID 一致**，否则 App 内的高德 iOS Key 校验不过（高德 Key 绑定 Bundle ID）。

---

## 6. 改 UI 到底改哪些文件

| 想改什么 | 改哪个 |
|---|---|
| 主题色、圆角、字体、整体配色 | `ios/MotoNav/AppTheme.swift` |
| 四栏主界面布局（导航/轨迹/圆屏/我的） | `ios/MotoNav/ContentView.swift`（53KB，逐段改，别整体重写） |
| 导航过程页样式 | `ios/MotoNav/NaviBridge.swift` 里的视图部分 |
| 图标 | `ios/MotoNav/Assets.xcassets/AppIcon.appiconset/icon.png`（必须 1024×1024 不透明） |
| 版本号 | `ios/MotoNav/Config.swift` |

**版本号陷阱**：`build-ios-ipa.sh` 会强校验主 App 与 `MotoNavShare.appex` 的 `CFBundleShortVersionString` / `CFBundleVersion` 完全一致，不一致直接 `exit 1`。改版本要同时改这两处（在 `project.pbxproj` 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`）。

---

## 7. 已知坑

| 现象 | 原因 / 处理 |
|---|---|
| `The workflow is not valid` 或 Actions 页看不到刚推的工作流 | fork 未启用 Actions，回到第 1 步 |
| `macos-26` label 报错 | 改成 `macos-15`，或抄官方 workflow 里的 label |
| `pod install --deployment` 失败 | `Podfile.lock` 与 `Podfile` 不一致。本地改过 Podfile 要同步提交 lock；实在不行临时改成 `pod install`（会改 lock，注意别提交） |
| 高德 SDK 下载慢/超时 | 首次构建常见，缓存命中后就快了；重跑一次通常能过 |
| 超时 40 分钟不够 | 官方 workflow 已设 40 分钟；精简版 30 分钟。首次冷缓存可能接近上限 |
| 装完闪退 | 分享扩展 `MotoNavShare.appex` 签名失败。可以删掉 `Payload/MotoNav.app/PlugIns/MotoNavShare.appex` 再签，主 App 不受影响（扩展只用 URL scheme 唤起主 App，不依赖 App Group） |
| 构建成功但 App 连不上设备 | 检查 `Info.plist` 的 `UIBackgroundModes` 是否含 `location`、`bluetooth-central`（重签名时若权限被裁会失效） |

---

## 8. 费用

- public 仓库 + 标准 runner：**免费，不消耗额度**
- 若哪天把仓库改成 private：macOS runner 按 **10 倍** 计费，免费额度 2000 分钟/月 → 实际只剩 200 分钟，跑 6~7 次就没了

---

## 9. 和安卓的关系

安卓不受这些限制，本地就能编：

```powershell
$env:JAVA_HOME='C:\tools\java\jdk\openjdk-17.0.2'
$env:GRADLE='C:\tools\gradle\gradle-8.10.2\bin\gradle.bat'
.\Build-Personal.ps1 -JavaPath $env:JAVA_HOME -GradlePath $env:GRADLE -SdkPath 'D:\Android\Sdk'
```

需要 Android SDK 35（不是 34/36）。`jdk-21` 和 `gradle-8.14.5` 版本不对，别用。
