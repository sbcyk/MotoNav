import SwiftUI

/// 版本：跟随 App 版本（见 Config.swift）
///
/// 自动白夜模式（和安卓版对齐后新增）：
/// - 界面的语义色不写死，而是浅色 / 深色两套值，用 UIColor 的 dynamic Provider 包起来
/// - 跟随系统深浅色自动切换；用户在「设置 → 外观」里也可以强制浅色或深色
///
/// iOS v0.15.21-tpms 冷淡科技（Apple-like cool muted）：
/// - 中性灰阶为主；点缀色仅系统蓝（Light `#007AFF` / Dark `#0A84FF`）
/// - 去掉粉 / 青双品牌色与霓虹 HUD；玻璃材质保留，染色克制
/// - 卡片 / 列表 / 选项卡：无灰色描边，靠间距与填充分层
/// - 按钮：Primary = 系统蓝实心；Secondary = 灰底；Destructive = 系统红字
extension Color {
    /// 浅色 / 深色两套值，跟随当前界面样式自动切换
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// 语义色板：界面里只用这些名字，不直接写死颜色
enum AppTheme {
    // MARK: 页面（跟随主题包：艾尔登中性灰 / 苔林低饱和绿）
    /// 所有语义色都从当前包的色板取。写成 static var 而不是 static let：
    /// 换包后要跟着变，存成 let 会在第一次访问时就把颜色定死。
    private static var pal: ThemePalette { pack.palette }
    /// 页面背景
    static var bg: Color { Color.dynamic(light: UIColor(hex: pal.bg), dark: UIColor(hex: pal.bgDark)) }
    /// 卡片（内容层：保持实色，玻璃只用在控制层）
    static var card: Color { Color.dynamic(light: UIColor(hex: pal.card), dark: UIColor(hex: pal.cardDark)) }
    /// 卡片内嵌的浅底（输入框、路线卡片的凹槽）
    static var sunken: Color { Color.dynamic(light: UIColor(hex: pal.sunken), dark: UIColor(hex: pal.sunkenDark)) }
    /// 描边
    static var stroke: Color { Color.dynamic(light: UIColor(hex: pal.stroke), dark: UIColor(hex: pal.strokeDark)) }
    /// Secondary 按钮 / 未选 chip 底
    static var secondaryFill: Color { Color.dynamic(light: UIColor(hex: pal.fill), dark: UIColor(hex: pal.fillDark)) }

    // MARK: 文字
    /// 主文字
    static var text: Color { Color.dynamic(light: UIColor(hex: pal.text), dark: UIColor(hex: pal.textDark)) }
    /// 次要文字（户外可读：浅色加深，深色提亮）
    static var sub: Color { Color.dynamic(light: UIColor(hex: pal.sub), dark: UIColor(hex: pal.subDark)) }
    /// 导航条选中软底
    static var selCapsule: Color {
        let a = pack.accent
        return Color.dynamic(light: UIColor(hex: a.light, alpha: 0.12),
                             dark: UIColor(hex: a.dark, alpha: 0.18))
    }

    // MARK: 强调色（跟随主题包：艾尔登暖金 / 苔林绿）
    /// 当前主题包。定义在文件末尾，语义只有一条：一套包同时决定 App 强调色、首页画面和默认地图配色。
    static var pack: ThemePack { ThemePack(rawValue: Settings.shared.appearance) ?? .elden }
    /// 主强调色
    static var accent: Color {
        let a = pack.accent
        return Color.dynamic(light: UIColor(hex: a.light), dark: UIColor(hex: a.dark))
    }
    /// 选中 chip 淡底
    static var accentSoft: Color {
        let a = pack.accent
        return Color.dynamic(light: UIColor(hex: a.light, alpha: 0.14),
                             dark: UIColor(hex: a.dark, alpha: 0.22))
    }

    /// 历史别名 → 强调色（旧代码里 pink / cyan 都指它）
    static var pink: Color { accent }
    /// 历史别名 → 强调色
    static var cyan: Color { accent }

    // MARK: Tab 选中态：三个 Tab 同一强调色
    static var tabAccents: [Color] { [accent, accent, accent] }

    /// 标题（实色字重，不做渐变；必须是计算属性，text 会随包变）
    static var titleGradient: LinearGradient {
        LinearGradient(colors: [text, text], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: 状态色（系统语义）
    static let green = Color.dynamic(
        light: UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1),   // #34C759
        dark:  UIColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1))   // #30D158
    static let amber = Color.dynamic(
        light: UIColor(red: 1.000, green: 0.584, blue: 0.000, alpha: 1),   // #FF9500
        dark:  UIColor(red: 1.000, green: 0.624, blue: 0.039, alpha: 1))   // #FF9F0A
    static let red = Color.dynamic(
        light: UIColor(red: 1.000, green: 0.231, blue: 0.188, alpha: 1),   // #FF3B30
        dark:  UIColor(red: 1.000, green: 0.271, blue: 0.227, alpha: 1))   // #FF453A
    /// 保留但降饱和，避免当品牌色用
    static let purple = Color.dynamic(
        light: UIColor(red: 0.686, green: 0.322, blue: 0.871, alpha: 1),
        dark:  UIColor(red: 0.749, green: 0.353, blue: 0.949, alpha: 1))
    static let orange = amber

    // MARK: 导航 HUD
    /// 转向卡深色半透明底
    static let hudCard = Color.black.opacity(0.78)
    /// HUD 次要字
    static let hudSub = Color.white.opacity(0.62)
}

/// 外观模式：0 跟随系统（默认），1 始终浅色，2 始终深色
enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var name: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// MotoNavApp 里 .preferredColorScheme 用
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 液态玻璃（iOS 26 Liquid Glass；旧系统降级为毛玻璃材质）

extension View {
    @ViewBuilder func liquidGlass<S:Shape>(_ shape:S,tint:Color?=nil,interactive:Bool=false)->some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*) {self.glassEffect(.regular,in:shape)}
        else {self.background(shape.fill(.ultraThinMaterial))}
        #else
        self.background(shape.fill(.ultraThinMaterial))
        #endif
    }
    func tabBarLiquidGlass<S:Shape>(_ shape:S)->some View {self.liquidGlass(shape)}
}

// MARK: - 冷淡科技按钮
//
// - Primary (prominent)：系统蓝实心 + 白字
// - Secondary (tinted / clear)：灰底 + 主文字
// - Destructive：红色软底 + 系统红字
// - Disabled：低对比灰

/// 按钮浓淡：clear 次要 / tinted 次操作 / prominent 主 CTA / destructive 危险
enum GlassButtonStyle {
    case clear
    case tinted
    case prominent
    case destructive
}

/// 统一按钮：冷淡科技实心 / 灰底胶囊
struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var style: GlassButtonStyle = .clear
    var tint: Color = AppTheme.accent
    var enabled = true
    var compact = false
    let action: () -> Void

    private var foreground: Color {
        switch style {
        case .prominent: return .white
        case .destructive: return AppTheme.red
        default: return AppTheme.text
        }
    }

    private var fill: Color {
        switch style {
        case .prominent: return tint
        case .destructive: return AppTheme.red.opacity(0.12)
        case .tinted: return AppTheme.secondaryFill
        case .clear: return AppTheme.secondaryFill.opacity(0.72)
        }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 8 : 12)
            .frame(minHeight: 44)
            .frame(maxWidth: (style == .prominent || (style == .tinted && !compact)) ? .infinity : nil)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }
}

// MARK: - 统一页眉

/// 弹窗 / 独立页的统一页眉：左侧圆形返回或关闭按钮，标题 + 副标题，右侧可选主操作。
/// 系统导航栏的贴边文字按钮不再使用，所有标题都落在 16pt 边距上，热区固定 40pt。
struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var back = false
    var actionTitle: String? = nil
    var actionEnabled = true
    let onClose: () -> Void
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onClose) {
                Image(systemName: back ? "chevron.left" : "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.secondaryFill.opacity(0.8)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(back ? "返回" : "关闭")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(AppTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppTheme.sub)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(actionEnabled ? AppTheme.accent : AppTheme.sub.opacity(0.5))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(actionEnabled ? AppTheme.accentSoft : AppTheme.secondaryFill.opacity(0.6)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!actionEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// 轻提示：操作已经生效，但页面结构不该跟着跳。
struct ToastBanner: View {
    let text: String
    var icon = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            Text(text).font(.footnote.weight(.semibold)).lineLimit(2)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// 地图缩放 / 全览按钮：圆形毛玻璃，内嵌预览和全屏共用。
struct MapControlButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 38
    let action: () -> Void

    private var iconSize: CGFloat { size >= 44 ? 15 : 14 }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(AppTheme.text)
                .frame(width: size, height: size)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(AppTheme.stroke.opacity(0.25), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }
}

/// 小芯片：选中 = 强调色软底 + 强调色字；默认 = 灰底
struct GlassChip: View {
    let title: String
    var icon: String? = nil
    var tint: Color? = nil
    var foreground: Color? = nil
    var enabled = true
    var compact = false
    let action: () -> Void

    private var labelColor: Color {
        if let foreground { return foreground }
        if tint != nil { return AppTheme.accent }
        return AppTheme.text
    }

    private var chipFill: Color {
        if tint != nil { return AppTheme.accentSoft }
        return AppTheme.secondaryFill
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(labelColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 9)
            .frame(minHeight: 44)
            .background(Capsule().fill(chipFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }
}

/// 电量条：按真实百分比填充，颜色随剩余电量变化；没收到电量时是空槽。
/// 圆屏只在连接后回传电量，所以 `percent` 是可选的。
struct BatteryGauge: View {
    var percent: Int?
    var charging = false
    var width: CGFloat = 32
    var height: CGFloat = 16

    private var level: Double {
        guard let percent else { return 0 }
        return Double(max(0, min(100, percent))) / 100
    }

    private var tint: Color {
        guard let percent else { return AppTheme.sub }
        if charging { return AppTheme.green }
        if percent <= 20 { return AppTheme.red }
        if percent <= 45 { return AppTheme.amber }
        return AppTheme.text
    }

    private var corner: CGFloat { height * 0.34 }

    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(tint.opacity(0.16))
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(tint)
                        .frame(width: g.size.width * level)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.62, weight: .bold))
                        .foregroundColor(.white)
                        // 电量很低时白色闪电会落在浅色空槽上，加一点投影保证两种底色都看得清
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 0.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1))
            Capsule()
                .fill(tint.opacity(0.45))
                .frame(width: max(1.5, height * 0.12), height: height * 0.42)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "电量 \($0)%" + (charging ? "，充电中" : "") } ?? "电量未知")
    }
}

// MARK: - 主题包

/// 一套包的界面语义色。每个字段一对：浅色 / 深色。
struct ThemePalette {
    let bg: UInt32, bgDark: UInt32
    let card: UInt32, cardDark: UInt32
    let sunken: UInt32, sunkenDark: UInt32
    let stroke: UInt32, strokeDark: UInt32
    let fill: UInt32, fillDark: UInt32
    let text: UInt32, textDark: UInt32
    let sub: UInt32, subDark: UInt32
}

/// 主题包：一套包 = App 强调色 + 首页画面 + 默认地图配色。
/// 编号写进手机偏好和圆屏 NVS，**只能追加、不能重排**，否则老设备会认成别的包。
enum ThemePack: Int, CaseIterable {
    case elden = 0
    case moss = 1

    var name: String {
        switch self {
        case .elden: return "艾尔登"
        case .moss:  return "苔林夜骑"
        }
    }

    var subtitle: String {
        switch self {
        case .elden: return "暖金 · 配罪恶都市地图"
        case .moss:  return "低饱和绿 · 配苔林地图"
        }
    }

    /// 换包时配套的地图风格编号（对应固件 THEMES 的下标）
    var defaultMapTheme: Int {
        switch self {
        case .elden: return 1
        case .moss:  return 12
        }
    }

    /// 强调色：浅色 / 深色。艾尔登的浅色必须压到 #8A5E1E，
    /// 亮金 #C08A2E 放在 #F3F3F8 底上只有 2.8:1，看不清。
    var accent: (light: UInt32, dark: UInt32) {
        switch self {
        case .elden: return (0x8A5E1E, 0xE0B25A)
        case .moss:  return (0x2F7D5A, 0x6FBF97)
        }
    }

    /// 界面语义色板
    var palette: ThemePalette {
        switch self {
        case .elden:
            return ThemePalette(
                bg: 0xF3F3F8, bgDark: 0x000000,
                card: 0xFFFFFF, cardDark: 0x1C1C1E,
                sunken: 0xF2F2F7, sunkenDark: 0x2C2C2E,
                stroke: 0xC7C7CC, strokeDark: 0x3C3C43,
                fill: 0xE5E5EA, fillDark: 0x3A3A3C,
                text: 0x000000, textDark: 0xFFFFFF,
                sub: 0x636366, subDark: 0x9E9EA3)
        case .moss:
            return ThemePalette(
                bg: 0xF4F7F4, bgDark: 0x0D1310,
                card: 0xFFFFFF, cardDark: 0x161E1A,
                sunken: 0xEDF2EE, sunkenDark: 0x1E2823,
                stroke: 0xD3DCD6, strokeDark: 0x2A3831,
                fill: 0xE4EBE6, fillDark: 0x22302A,
                text: 0x17211B, textDark: 0xE9EFEA,
                sub: 0x5B6B61, subDark: 0x8C9C92)
        }
    }
}

extension UIColor {
    /// 0xRRGGBB + 不透明度
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
