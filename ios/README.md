# MotoNav iOS

iPhone 端源码。最低 iOS 15，三栏目：导航、设备、我的；iOS 端不含红绿灯读秒。功能说明见[项目主页](../README.md)，改动记录见 [CHANGELOG](../CHANGELOG.md)，配套圆屏见[固件说明](../firmware/README.md)，两端协议见[技术文档](../docs/MotoNav-技术文档.md)。

## 构建

需 macOS + Xcode + CocoaPods 1.16.2，在仓库根目录执行：

```sh
bash build-ios.sh
```

输出 `output/ios/*.ipa`（未签名）。依赖由 `ios/Podfile.lock` 锁定（`AMapNavi`、`AMapSearch`），不要单独升级 pod。也可在 Actions 里手动跑 `iOS Quick Build (unsigned IPA)`。

M 系列 Mac 的模拟器只能编 x86_64（`Podfile` 已设 `EXCLUDED_ARCHS`），真机不受影响。

## 安装

本仓库不发布预签名 IPA。产物需用 iLoader、Sideloadly 等工具以自己的 Apple 账号签名后安装；免费签名通常 7 天续签一次。覆盖更新要沿用原签名身份和实际 Bundle ID，Key、配对、设置与记录才会保留；分享扩展是独立 target，也要签名。

## 运行前

- 高德 iOS Key 在 App 内填写，绑定的 Bundle ID 必须与签名后的实际 Bundle ID 一致；未填写时搜索框下方常驻提示，点它直通密钥设置。
- 天气按自己的服务填 Host，源码不含任何人的 Key、Cookie 或签名证书。
- 轨迹在真实导航或巡航开始时自动记录，模拟导航不记，不上传。

## UI 来源

界面参考移植并适配自 **[coolcoolmanman（@coolcoolmanman-design）的 MotoNav](https://github.com/coolcoolmanman-design/MotoNav)**，参考版本 0.15.21-tpms，固定提交 [c01d6db1](https://github.com/coolcoolmanman-design/MotoNav/tree/c01d6db1a323e91d0b0210b796d9bb6a0cd7bd0f)。参考范围、适配与许可见 [UI-SOURCE-NOTICE.md](UI-SOURCE-NOTICE.md)，感谢原作者的设计与实现。

## 许可

沿用仓库[非商业使用条款](../LICENSE.md)，第三方 SDK 与资源遵循各自许可。
