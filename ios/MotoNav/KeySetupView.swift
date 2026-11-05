import SwiftUI

/// 版本：跟随 App 版本（见 Config.swift）
///
/// 「我的 → 通用」里的密钥卡片。iOS v1.0 起不再弹填写页：高德 Key 和和风天气
/// 都在这张卡里直接改，Key 只保存在这台手机上。
/// 缺高德 Key 时卡片自己描橙色边，不靠外部传状态。
struct KeySettingsCard: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject private var weather = Weather.shared      // displaySummary 跟着 info 变
    @State private var amapIn = Settings.shared.amapKey
    @State private var host = Weather.shared.host
    @State private var weatherIn = Weather.shared.key
    @State private var amapNote = ""
    @State private var weatherNote = ""
    @State private var weatherReady = !(Weather.shared.host.isEmpty || Weather.shared.key.isEmpty)
    @State private var copied = false
    @State private var showGuide = false

    private var bundleID: String { Bundle.main.bundleIdentifier ?? "" }
    private var amapMissing: Bool { settings.amapKeyInUse.isEmpty }

    var body: some View {
        CardView {
            titleRow
            Text("只保存在这台手机上；保存后马上生效，不用重启。")
                .font(.caption).foregroundColor(AppTheme.sub)
            amapBlock
            Divider().opacity(0.35)
            weatherBlock
        }
        .overlay {
            if amapMissing {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.orange.opacity(0.55), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("密钥设置").font(.headline).foregroundColor(AppTheme.text)
            if amapMissing { badge("未填", color: AppTheme.orange) }
            Spacer(minLength: 4)
            Text(Settings.mask(settings.amapKeyInUse)).font(.caption).foregroundColor(AppTheme.sub)
        }
    }

    // MARK: 高德

    private var amapBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("高德").font(.subheadline.weight(.semibold)).foregroundColor(AppTheme.text)
                badge("必填", color: AppTheme.accent)
                Spacer(minLength: 4)
            }
            Text("搜索、导航、巡航和卫星底图都用它，不填就用不了。")
                .font(.caption).foregroundColor(AppTheme.sub)
            keyField("粘贴高德 Key", text: $amapIn)
            // 和已保存的值不同才可点：既避免空点，也留着清空旧 Key 的路
            PillButton(title: amapMissing ? "保存密钥" : "更新密钥", color: AppTheme.accent,
                       enabled: trimmed(amapIn) != settings.amapKeyInUse) { saveAmap() }
            if !amapNote.isEmpty {
                Text(amapNote).font(.caption).foregroundColor(AppTheme.accent)
            }
            guide
        }
    }

    private var guide: some View {
        DisclosureGroup(isExpanded: $showGuide) {
            VStack(alignment: .leading, spacing: 10) {
                step(1, "打开高德开放平台，用手机号注册并完成实名认证")
                step(2, "控制台 → 应用管理 → 我的应用 → 创建新应用，再点「添加 Key」")
                step(3, "服务平台选「iOS 平台」，安全码（Bundle ID）填这个：")
                HStack(spacing: 8) {
                    Text(bundleID).font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppTheme.accent).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Button(copied ? "已复制" : "复制") {
                        UIPasteboard.general.string = bundleID
                        copied = true
                    }
                    .font(.caption.weight(.bold)).foregroundColor(AppTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.sunken))
                step(4, "把生成的 Key 粘到上面的输入框，点保存")
                Link(destination: URL(string: "https://console.amap.com/dev/key/app")!) {
                    Label("打开高德开放平台", systemImage: "safari")
                        .font(.caption).foregroundColor(AppTheme.accent).frame(minHeight: 44)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("怎么获取高德 Key？")
                .font(.footnote.weight(.semibold)).foregroundColor(AppTheme.accent)
        }
        .tint(AppTheme.accent)
    }

    // MARK: 和风天气

    private var weatherBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("和风天气").font(.subheadline.weight(.semibold)).foregroundColor(AppTheme.text)
                badge("可选", color: AppTheme.sub)
                Spacer(minLength: 4)
                Text(weatherReady ? "已配置" : "未配置").font(.caption).foregroundColor(AppTheme.sub)
            }
            Text("填了才能在圆屏看当前天气和逐小时预报。")
                .font(.caption).foregroundColor(AppTheme.sub)
            keyField("API Host：xxxx.qweatherapi.com", text: $host, secure: false)
            keyField("API Key", text: $weatherIn, secure: true)
            HStack(spacing: 10) {
                GlassButton(title: "保存", icon: "tray.and.arrow.down", style: .tinted) { saveWeather() }
                GlassButton(title: "刷新", icon: "arrow.clockwise", style: .clear) { weather.request(force: true) }
            }
            if !weatherNote.isEmpty {
                Text(weatherNote).font(.caption).foregroundColor(AppTheme.orange)
            } else {
                Text(weather.displaySummary).font(.caption).foregroundColor(AppTheme.sub)
            }
            Link("和风天气来源说明", destination: URL(string: "https://developer.qweather.com/attribution.html")!)
                .font(.caption).foregroundColor(AppTheme.accent)
        }
    }

    // MARK: 零件

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.caption.bold()).foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(AppTheme.accent))
            Text(text).font(.footnote).foregroundColor(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 和高德那张统一的输入框：下沉底色 + 描边 + 右边一个粘贴。
    private func keyField(_ placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack(spacing: 6) {
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .foregroundColor(AppTheme.text)
            .font(.system(.subheadline, design: .monospaced))
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
            Button("粘贴") {
                if let s = UIPasteboard.general.string {
                    text.wrappedValue = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .font(.footnote.weight(.bold)).foregroundColor(AppTheme.accent)
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.sunken))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke, lineWidth: 1))
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 保存

    private func saveAmap() {
        let v = trimmed(amapIn)
        let old = settings.amapKeyInUse
        settings.amapKey = v
        if settings.amapKeyInUse != old { settings.applyAmapKey() }     // 马上生效
        amapIn = settings.amapKeyInUse                                   // 写回去掉首尾空白后的值
        amapNote = v.isEmpty ? "已清空，搜索和导航要重新填" : "已保存，搜索和导航马上用新 Key"
    }

    private func saveWeather() {
        do {
            try weather.save(host: trimmed(host), key: trimmed(weatherIn))
            host = weather.host          // save 会把 Host 规范化，写回让输入框显示整理后的值
            weatherIn = weather.key
            weatherReady = true
            weatherNote = ""
        } catch {
            weatherNote = error.localizedDescription
        }
    }
}
