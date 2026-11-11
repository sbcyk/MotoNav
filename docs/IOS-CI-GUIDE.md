# MotoNav iOS — GitHub Actions 出包指南

目标：在 Windows 上改 SwiftUI 布局/样式 → 云端 macOS 编译 → 下载 unsigned IPA → 本地自签装机。

---

## 0. 事实核对（2026-11-03）

| 项 | 值 |
|---|---|
| 你的 fork | `github.com/sbcyk/MotoNav`，public，main 是自己的开发主线 |
| fork 的 parent | `CharlesXu/MotoNav`；本仓库只保留来源声明，不同步上游 |
| iOS 源码 | `ios/` 129 个文件，`MotoNav.xcworkspace` + `Podfile` |
| 官方工作流 | `.github/workflows/release-ios.yml`（macos-26，跑全套测试，20~40 分钟），**已禁用** |
| Actions 状态 | `ios-quick` 启用，`release-ios` / `release-firmware` 禁用，三个都只手动触发 |
| 构建脚本 | `scripts/build-ios-ipa.sh` → `CODE_SIGNING_ALLOWED=NO`，产物就是 unsigned IPA |
| 依赖 | CocoaPods **1.16.2**（写死），`pod install --deployment` |
| Pods | AMapNavi + AMapSearch（高德），平台 iOS 15.0 |
| 模拟器坑 | Podfile 强制 `EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64`，只影响模拟器，真机无碍 |

---

## 1. Actions 开关状态

已配置好，不用再动。现在 3 个工作流全部只有手动触发，push 不会跑：

| 工作流 | 触发 | 状态 |
|---|---|---|
| `iOS Quick Build (unsigned IPA)` | 只有手动 | 启用 |
| `iOS Build and Verify`（release-ios） | 只有手动 | 禁用 |
| `Verify universal firmware`（release-firmware） | 只有手动 | 禁用 |

要改状态：`Actions` 页面 → 左侧点进工作流 → 右上角 `...` → `Disable workflow` / `Enable workflow`。

自动触发已经去掉（原来 push 改 `ios/**` 或 `firmware/**` 就各跑一轮 40 分钟），所以启用也不会被 push 打扰；平时关着，需要完整回归时手动开一次。

禁用状态记在 GitHub 上，不在代码里。

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

Actions → 左侧 `iOS Quick Build (unsigned IPA)` → 右侧 `Run workflow` → 选分支（`main` 或你指定的分支）→ Run。

**没有任何自动触发。** 这是刻意的：开发一批内容、自己确认没问题了，再出包装机。推代码不会占用构建时间。

`release-ios.yml`（官方那套，跑全套一致性测试）默认在网页上被禁用。改到协议层、需要完整回归时才临时 `Enable workflow` 手动跑一次，跑完再禁用。

---

## 4. 取包

构建完成后在 run 详情页底部 **Artifacts** 下载 `MotoNav-<版本>-build<build号>.ipa`，例如 `MotoNav-1.0.0-build42.ipa`。

- 版本来自工程的 `MARKETING_VERSION`（`ios/MotoNav.xcodeproj`），发版时改这一处，App 和分享扩展共用
- build 号由 CI 的 `github.run_number` 覆写，每次打包都不同，所以文件名不会撞车
- 包是未签名的（CI 里 `CODE_SIGNING_ALLOWED=NO`），装机要自己重签
- 同目录还有 `SHA256SUMS.txt` 和 `build-ios.log`（编译警告都在这）

---

## 5. 自签装机

沿用你现在的这套：iLoader → SideStore → 装 IPA。完整流程见 `docs/MotoNav-技术文档.md` 第 12 章。

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
| Actions 页看不到 `iOS Quick Build`，或点了没反应 | 工作流被禁用或未注册。去 Actions 页面左侧确认它的状态，`...` 里可以 `Enable workflow` |
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
