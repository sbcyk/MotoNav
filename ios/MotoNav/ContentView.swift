import SwiftUI
import AVFoundation
import UIKit

/// 版本：跟随 App 版本（见 Config.swift）
///
/// 主界面：圆屏连接状态、搜索目的地 / 导入高德分享路线、选路线、开始导航、巡航、屏幕显示 / 屏幕设置、密钥设置
/// 0.16.0 UI alignment: four tabs, semantic colours, device card and grouped settings.
struct ContentView: View {
    @ObservedObject var ble = BleLink.shared
    @ObservedObject var navi = NaviBridge.shared
    @ObservedObject var independent = WebMotorSession.shared
    @ObservedObject var search = SearchService.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var map = MapFeeder.shared
    @ObservedObject private var rides=RideRecorder.shared
    @ObservedObject private var connectAnim=ConnectAnimationCoordinator.shared
    @AppStorage("ui_appearance") private var appearance=0
    @AppStorage("ui_tab_placement") private var tabPlacement=0
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var uiStarted=false
    @AppStorage("ui_selected_tab") private var page = 0
    @State private var showWebMotor = false
    @State private var independentDestination: SearchService.Place?
    @State private var showRides = false
    @State private var showFavorites = false
    @State private var showScreens=false
    @State private var confirmForgetPhones=false
    @State private var showMapReport=false
    @AppStorage("voice_rate") private var voiceRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("voice_pitch") private var voicePitch = 1.0
    @AppStorage("voice_id") private var voiceID = ""

    @State private var query = ""
    @FocusState private var searchFocused: Bool           // 输入框聚焦时把结果面板浮出来
    @State private var searchDebounce: DispatchWorkItem?  // 边输入边查的防抖
    @State private var keyboardTop: CGFloat = 0           // 键盘顶边（全局 y），0 = 没弹
    @State private var naviTab = 0                       // 导航页卡片：0 导航模式，1 巡航模式
    @State private var showNavi = false
    @State private var settingsPush: SettingsHubItem?   // 缺密钥时直接把「通用」推开，不再弹填写页
    private static var keyPrompted = false              // 这次打开 App 已经提醒过填 key 了
    @State private var shareBusy = false
    @State private var shareStatus = ""
    @State private var pendingShare=""
    @State private var shareImportID=UUID()
    @State private var showShareVerification=false
    @State private var cruiseNote = ""

    static let bg=AppTheme.bg,card=AppTheme.card,stroke=AppTheme.stroke
    static let pink=AppTheme.accent,cyan=AppTheme.accent,sub=AppTheme.sub

    var body:some View {
        GeometryReader { geo in
            let wide=TabLayout.isWide(size:geo.size,hSizeClass:hSizeClass)
            let rail=TabLayout.useSideRail(size:geo.size,hSizeClass:hSizeClass,placement:tabPlacement)
            NavigationView {
                ZStack(alignment:.bottom) {
                    if rail {
                        HStack(spacing:0) {
                            VStack(spacing:0){activeNavigationBanner;pages(wide:wide)}
                            rightRail(systemEdge:0)
                        }
                    } else {
                        VStack(spacing:0){activeNavigationBanner;pages(wide:wide)}
                        bottomBar
                    }
                }.background(Self.bg.ignoresSafeArea()).navigationBarHidden(true)
            }.navigationViewStyle(.stack).id(page)
        }
        .fullScreenCover(isPresented: $showWebMotor) {
            WebMotorView(initialDestination: independentDestination)
        }
        .sheet(isPresented: $showRides) { NavigationView { RideHistoryView() } }
        .sheet(isPresented: $showFavorites) { favoritesSheet }
        .sheet(isPresented:$showScreens) { screenPicker }
        .sheet(isPresented:$showMapReport){MapSampleReportView()}
        .confirmationDialog("清除其他手机的配对？",isPresented:$confirmForgetPhones,titleVisibility:.visible) {
            Button("清除其他手机",role:.destructive){ble.forgetOtherPhones()}
            Button("取消",role:.cancel){}
        } message: {Text("这台手机保留配对；其他手机以后要重新配对才能连上导航屏。")}
        .fullScreenCover(isPresented: $showNavi) { NaviScreen() }
        .sheet(isPresented:$showShareVerification){
            ShareVerificationView(page:AmapShare.findUrl(pendingShare).flatMap{URL(string:$0)}){
                let text=pendingShare
                DispatchQueue.main.asyncAfter(deadline:.now()+0.35){importShare(text)}
            }
        }
        .overlay(alignment: .top) {
            if connectAnim.showReconnectBanner {
                ReconnectBanner().transition(.opacity).zIndex(40)
            }
        }
        .overlay {
            if connectAnim.isPresented {
                ConnectSheetView()
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(50)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9), value: connectAnim.isPresented)
        .onAppear {
            softenSegmentedChrome()
            if !uiStarted {
                uiStarted=true
                if !settings.keysMissing && !ble.isReady && ble.bluetoothAvailable {connectAnim.connectAutomatically()}
            }
            if !ContentView.keyPrompted && settings.keysMissing {
                // iOS v0.7 起开 App 提醒一次；v1.0 起不再弹填写页，直接切到密钥卡片
                ContentView.keyPrompted = true
                openKeySettings()
            }
        }
        .onOpenURL { url in                            // iOS v0.4 高德里“分享到导一导”：motonav://share?t=分享的文字
            guard url.scheme == "motonav",
                  let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" })?.value
            else { return }
            importShare(t)
        }
        .onChange(of: page) { now in
            // 没退「通用」就直接点了别的 tab：清掉待推项，否则下次回到「我的」会被再推一次
            if now != 3 { settingsPush = nil }
            // 换页就把搜索浮层收掉，别让它盖在新页面上
            closeSearch()
        }
        // 搜索结果面板要贴在搜索框下方、又不越过屏幕底部，得知道键盘占了多少
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let f = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // 收起时这个 y 会落到屏幕外，后面和页面底取 min 会被截住，不用另判
            keyboardTop = f.minY
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardTop = 0
        }
    }

    private var activeNavigationBanner: some View {
        Group {
            if navi.navigating || independent.running {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text("导航继续运行中").bold()
                        Text(independent.running ? independent.instruction : "\(navi.uiDir) · \(navi.uiDist) 米")
                            .font(.caption).lineLimit(1)
                    }
                    Spacer()
                    Button("回到导航") {
                        if independent.running { showWebMotor=true } else { showNavi=true }
                    }.foregroundColor(Self.pink)
                }.padding(12).background(Self.card).foregroundColor(AppTheme.text)
            }
        }
    }

    private var screenPicker:some View {
        NavigationView {
            List {
                Section {
                    Text("选择要连接的圆屏，圆屏上的编号就是这里的名字。").font(.subheadline).foregroundColor(Self.sub)
                    if ble.availableScreens.isEmpty {Text("正在搜索附近的圆屏…")}
                    ForEach(ble.availableScreens){screen in
                        Button(screen.name){ble.selectScreen(screen.id);showScreens=false;connectAnim.connectAutomatically()}
                    }
                }
            }.navigationTitle("切换设备").toolbar {
                ToolbarItem(placement:.cancellationAction){Button("取消"){showScreens=false}}
                ToolbarItem(placement:.confirmationAction){Button("重新搜索"){ble.beginScreenSelection()}}
            }
        }.onAppear{ble.beginScreenSelection()}.onDisappear{ble.endScreenSelection()}
    }

    private func pages(wide: Bool) -> some View {
        Group {
            if page == 0 && !wide {
                // 导航页固定一屏：上半搜索，下半轨迹卡吃满剩余高度，整页不再上下滑
                naviPage
            } else {
                ScrollView {
                    Group {
                        if page == 0 && wide {
                            // 宽屏：左侧完成摩托规划，右侧放收藏地点与轨迹入口
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 16) {
                                    header
                                    naviModeCard
                                }
                                VStack(alignment: .leading, spacing: 16) {
                                    GlassChip(title: "收藏地点", icon: "mappin.and.ellipse") {
                                        closeSearch()
                                        showFavorites = true
                                    }
                                    GlassChip(title: "导航轨迹", icon: "location.north.line", tint: Self.cyan) { page = 1 }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                if page == 1 {
                                    ridesTabContent
                                } else if page == 2 {
                                    deviceTabContent
                                } else {
                                    settingsTabContent
                                }
                            }
                        }
                    // 内容滚过悬浮玻璃条后方，留白 ≈ 条高 + 安全区
                    }.padding(.horizontal, 16).padding(.top, 16)
                        .padding(.bottom, page == 2 ? 104 : 128)     // 设备页一屏放得下，留白收窄
                }
                .scrollBounceBehaviorIfFits()
            }
        }
        .frame(maxWidth: wide ? 1080 : .infinity)
        .frame(maxWidth: .infinity)
        // 搜索浮层挂在这一层：竖屏的导航页和宽屏的两栏都能贴到各自的搜索框下面。
        // 位置走全局坐标再换算成局部偏移，不用 coordinateSpace(name:)，那个在 iOS 17 已废弃。
        .overlayPreferenceValue(SearchFieldAnchorKey.self) { anchor in
            GeometryReader { g in
                let origin = g.frame(in: .global)
                if anchor.width > 0 {
                    let top = anchor.maxY - origin.minY + 8
                    // 键盘弹着就以键盘顶为底：这时 pages 被键盘压过，g.size 不能反映真实底边
                    let bottom = keyboardTop > 0 ? keyboardTop - origin.minY - 12 : g.size.height - 92
                    let room = bottom - top                             // 面板最多能有多高
                    // 高度按内容算：状态行 54，一行 52，超过 8 条才轮到面板自己滚。
                    // 不能直接用 room，否则只有一条结果时也是一整块空白卡片。
                    let statusRow: CGFloat = (!search.status.isEmpty && search.results.isEmpty) ? 54 : 0
                    let rowsH = CGFloat(min(search.results.count, 8)) * 52
                    let visible = searchPanelVisible && room >= 52
                    searchResultsPanel
                        .frame(width: anchor.width,
                               height: max(52, min(min(420, room), statusRow + rowsH)))
                        .offset(x: anchor.minX - origin.minX, y: top)
                        .opacity(visible ? 1 : 0)
                        .allowsHitTesting(visible)
                        .accessibilityHidden(!visible)     // opacity 0 读屏仍会读到，必须显式藏掉
                }
            }
        }
    }

    // MARK: 导航页（固定一屏）
    /// 导航页不再放 ScrollView：标题 + 导航卡 + 轨迹概览卡，卡与卡之间留 14，
    /// 轨迹卡吃掉剩下的高度。搜索结果是浮层，不参与这里的排版。
    private var naviPage: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 14) {
                header
                naviModeCard
                rideGlanceCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)                     // 加上 header 自带的 8，和其余 tab 的 16 对齐
            .padding(.bottom, 92)                 // 悬浮玻璃条的落点，不让内容钻到它下面
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .clipped()                                    // 极端字号下内容溢出时别画到悬浮玻璃条上
        // 只让导航页忽略键盘：不加的话键盘一弹，轨迹卡会被压到最小高度。
        // 别的页（比如密钥输入）要保留系统的避让，所以不能提到 pages 那一层。
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// 搜索浮层什么时候在：聚焦且有内容（结果或“搜索中/没找到”这类状态）
    private var searchPanelVisible: Bool {
        searchFocused && (!search.results.isEmpty || !search.status.isEmpty)
    }

    private var ridesTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("轨迹")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(AppTheme.text)
                    Text(monthRideSummary)
                        .font(.caption)
                        .foregroundColor(AppTheme.sub)
                }
                Spacer()
                GlassChip(title: "全部", icon: "list.bullet", tint: Self.cyan, compact: true) { showRides = true }
            }
            .padding(.top, 8)

            if let active = rides.active {
                CardView {
                    Text("记录中 · \(active.mode) · \(Int(active.meters)) 米")
                        .foregroundColor(AppTheme.accent).bold()
                    Text("真实导航或巡航中自动写入轨迹点")
                        .font(.caption).foregroundColor(AppTheme.sub)
                }
            }

            if let latest = rides.rides.first {
                NavigationLink(destination: RideDetailView(ride: latest)) {
                    RideFeatureCard(ride: latest)
                }
                .buttonStyle(.plain)
            } else if rides.active == nil {
                CardView {
                    Text("还没有导航记录")
                        .foregroundColor(AppTheme.text).bold()
                    Text("真实导航或巡航开始时自动记录；模拟导航不记录。")
                        .font(.caption).foregroundColor(AppTheme.sub)
                }
            }

            if rides.rides.count > 1 {
                Text("更早的导航")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.sub)
                    .padding(.top, 4)
                let earlier = Array(rides.rides.dropFirst().prefix(12))
                VStack(spacing: 0) {
                    ForEach(Array(earlier.enumerated()), id: \.element.id) { idx, ride in
                        NavigationLink(destination: RideDetailView(ride: ride)) {
                            RideListRow(ride: ride)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if idx < earlier.count - 1 {
                            Divider().padding(.leading, 88).opacity(0.35)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18).fill(AppTheme.card))
            }

        }
    }

    private var monthRideSummary: String {
        let cal = Calendar.current
        let monthRides = rides.rides.filter { cal.isDate($0.started, equalTo: Date(), toGranularity: .month) }
        let meters = monthRides.reduce(0.0) { $0 + $1.meters }
        let km = meters / 1000.0
        return String(format: "本月 %.1f km · %d 次导航", km, monthRides.count)
    }

    private var deviceTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("设备", subtitle: "圆屏的连接、电量与屏幕设置")
            DeviceConnectionCard(
                displayDestination: { secondaryPage(title: "屏幕显示") { displayCard } },
                systemDestination: { secondaryPage(title: "屏幕设置") { settingsCard } }
            )
            deviceManagementCard
        }
    }

    private var settingsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("我的", subtitle: "通用 · 导航语音 · 关于")
            SettingsHubList(activeItem: $settingsPush) { item in
                secondaryPage(title: item.title) {
                    switch item {
                    case .general:
                        // 密钥缺了搜索和导航都用不了，放在最前；从导航页跳过来落地就能填
                        keyCard
                        appearanceCard
                        layoutCard
                    case .voice:
                        voiceCard

                    case .about:
                        CardView {
                            Text("关于").foregroundColor(AppTheme.text).bold()
                            Text("\(APP_VERSION) · Build \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "2")").font(.footnote).foregroundColor(AppTheme.sub)
                            Text("AI 辅助开发 · 仅供非商业使用")
                                .font(.caption).foregroundColor(AppTheme.sub)
                        }
                        Link("项目与使用说明",destination:URL(string:"https://github.com/sbcyk/MotoNav")!).font(.subheadline)
                    }
                }
            }
        }
    }

    private func secondaryPage<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 128)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationBarHidden(false)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(InteractivePopEnabler())
    }

    private func softenSegmentedChrome() {
        let app = UISegmentedControl.appearance()
        app.selectedSegmentTintColor = UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.518, blue: 1.000, alpha: 0.28)
                : UIColor(red: 0.000, green: 0.478, blue: 1.000, alpha: 0.16)
        }
        app.backgroundColor = UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)
                : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
        }
        app.setDividerImage(UIImage(), forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
        app.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
        app.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .selected)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(AppTheme.text)
            Text(subtitle).font(.caption).foregroundColor(ContentView.sub)
        }
        .padding(.top, 8)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("准备开导")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(AppTheme.text)
                Text("摩托车路线 · 圆屏导航")
                    .font(.footnote)
                    .foregroundColor(AppTheme.sub)
            }
            Spacer(minLength: 8)
            Button { page = 2 } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(ble.isReady ? AppTheme.green : AppTheme.amber)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ble.isReady ? "圆屏已连接" : "圆屏未连接")
                            .font(.caption.weight(.semibold))
                        HStack(spacing: 4) {
                            BatteryGauge(percent: ble.screenBattery, charging: ble.screenCharging, width: 20, height: 10)
                            Text(ble.screenBattery.map { "\($0)%" } ?? "查看设备")
                                .font(.caption2)
                        }
                    }
                }
                .foregroundColor(AppTheme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(AppTheme.secondaryFill.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ble.isReady
                ? "圆屏已连接" + (ble.screenBattery.map { "，电量 \($0)%" + (ble.screenCharging ? "，充电中" : "") } ?? "") + "，查看设备"
                : "圆屏未连接，查看设备")
        }
        .padding(.top, 8)
    }

    private var appearanceCard: some View {
        CardView {
            Text("外观").foregroundColor(AppTheme.text).bold()
            Picker("外观", selection: $appearance) {
                Text("跟随系统").tag(0); Text("浅色").tag(1); Text("深色").tag(2)
            }
            .pickerStyle(.segmented)
            Text("跟随系统时，界面随手机的深色模式自动切换浅色 / 深色；也可以一直用浅色或深色。圆屏小地图的昼夜由「设备 → 屏幕显示 → 夜间与弯道」控制。")
                .font(.caption2).foregroundColor(AppTheme.sub)
        }
    }

    private var deviceManagementCard:some View {
        CardView {
            Text("设备管理").font(.headline).foregroundColor(AppTheme.text)
            deviceActionRow(icon: "arrow.triangle.2.circlepath", title: "切换设备",
                            detail: "搜索附近的圆屏") { showScreens = true }
            Divider().opacity(0.35)
            deviceActionRow(icon: "iphone.slash", title: "清除其他手机",
                            detail: "其他手机需重新配对",
                            destructive: true, enabled: ble.isReady && ble.verified) { confirmForgetPhones = true }
        }
    }

    /// 设备管理里的一行：图标 + 标题 + 一句说明，整行可点，触控高度 44。
    private func deviceActionRow(icon: String, title: String, detail: String,
                                 destructive: Bool = false, enabled: Bool = true,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(destructive ? AppTheme.red : (enabled ? AppTheme.accent : AppTheme.sub))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(destructive ? AppTheme.red : AppTheme.text)
                    Text(detail).font(.caption).foregroundColor(Self.sub).lineLimit(2)
                }
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
    private var layoutCard:some View {
        CardView {
            Text("导航栏").font(.headline).foregroundColor(AppTheme.text)
            Picker("导航栏位置",selection:$tabPlacement) {
                Text("自动").tag(0);Text("底部").tag(1);Text("右侧").tag(2)
            }.pickerStyle(.segmented)
            Text("自动模式在宽屏横向布局中使用侧栏。").font(.caption).foregroundColor(Self.sub)
        }
    }

    // MARK: 导航与巡航
    /// 导航页的主卡：上面切「导航模式 / 巡航模式」，下面各一套内容，不再并排放两张卡。
    private var naviModeCard: some View {
        CardView {
            Picker("导航或巡航", selection: $naviTab) {
                Text("导航模式").tag(0)
                Text("巡航模式").tag(1)
            }
            .pickerStyle(.segmented)
            if naviTab == 0 { naviModeBody } else { cruiseModeBody }
        }
        // 巡航一开始就亮出那一页：「结束巡航」以前是常驻按钮，别让它藏进 tab 里
        .onChange(of: navi.cruising) { now in if now { naviTab = 1 } }
        // 切 tab / 重进页面时 naviTab 会回到 0，巡航中要重新落到那一页
        .onAppear { if navi.cruising { naviTab = 1 } }
        .onChange(of: naviTab) { _ in closeSearch() }   // 切到巡航时把搜索浮层和键盘一起收掉
    }

    /// 卡里的「导航模式」：搜索目的地、缺 Key 提示、两个快捷入口。
    /// 输入即查（防抖 0.4 秒），不再按「搜索」；结果改成搜索框下方的浮层，不把这里的内容顶下去。
    private var naviModeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.sub)
                    .accessibilityHidden(true)
                TextField("搜索地点、地址", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .foregroundColor(AppTheme.text)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { runSearchNow() }          // 键盘上的「搜索」仍然立刻查一次
                if !query.isEmpty {
                    Button {
                        query = ""
                        search.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.sub.opacity(0.65))
                            .frame(minWidth: 44, minHeight: 44)   // 触控热区按规范给满，图标本身只有 16
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.sunken))
            .background(SearchFieldAnchor())
            .onChange(of: query) { text in scheduleSearch(text) }

            // 没密钥时边打字边查是静默失败的，这里明说一句，点一下直接去填
            if settings.amapKeyInUse.isEmpty {
                Button { openKeySettings() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("搜索需要高德密钥，点这里去填")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(AppTheme.orange)
                    .frame(minHeight: 44)                 // 一行提示也是可点入口，热区按 44 来
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // 快捷入口并排一行，不再用“文字链接 + 长段说明”堆在一起
            HStack(spacing: 10) {
                naviQuickAction(title: "收藏地点", icon: "mappin.and.ellipse") {
                    closeSearch()
                    showFavorites = true
                }
                naviQuickAction(title: shareBusy ? "正在读取…" : "导入高德路线",
                                icon: "doc.on.clipboard", enabled: !shareBusy) { pasteShare() }
            }
            Text("在高德规划摩托车路线后，分享到导一导，或复制链接后点「导入高德路线」。")
                .font(.caption2)
                .foregroundColor(AppTheme.sub)

            if !shareStatus.isEmpty {
                Text(Self.userMessage(shareStatus))
                    .font(.footnote)
                    .foregroundColor(AppTheme.sub)
            }
            if !pendingShare.isEmpty && !shareBusy {
                GlassChip(title: "网页验证后重试", icon: "safari", tint: AppTheme.accent) {
                    showShareVerification = true
                }
            }
        }
    }

    /// 边输入边查：0.4 秒没再动键盘才发一次，拼音输入的每个字母不会各查一次高德。
    private func scheduleSearch(_ text: String) {
        searchDebounce?.cancel()
        // 选完地点后程序会把名字写回输入框，那一次不算用户输入，不查
        guard searchFocused else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { search.clear(); return }
        // 没填高德 key 就只提示，不在打字时把人踢去设置页
        guard !settings.amapKeyInUse.isEmpty else { search.clear(); return }
        let work = DispatchWorkItem { search.search(t) }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// 收起搜索：停掉待发的查询、注销焦点、收键盘，浮层跟着消失
    private func closeSearch() {
        searchDebounce?.cancel()
        searchFocused = false
        hideKeyboard()
    }

    /// 键盘的「搜索」键：不等防抖，立刻查
    private func runSearchNow() {
        searchDebounce?.cancel()
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { search.clear(); return }
        if needAmapKey() { return }
        search.search(t)
    }

    /// 搜索结果浮层：贴在搜索框下方，最多到键盘顶 / 页面底，内容多时自己滚。
    private var searchResultsPanel: some View {
        VStack(spacing: 0) {
            if !search.status.isEmpty && search.results.isEmpty {
                HStack(spacing: 8) {
                    if search.status.hasPrefix("搜索中") {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.sub)
                            .accessibilityHidden(true)
                    }
                    Text(Self.userMessage(search.status))
                        .font(.footnote)
                        .foregroundColor(AppTheme.sub)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 54, alignment: .leading)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(search.results.enumerated()), id: \.element.id) { idx, p in
                        Button { choose(p) } label: { searchPanelRow(p) }
                            .buttonStyle(.plain)
                        if idx < search.results.count - 1 {
                            // 和行内图标右边对齐：行内边距 12 + 图标 26 + 间距 10
                            Divider().padding(.leading, 48).opacity(0.35)
                        }
                    }
                }
            }
            .keepKeyboardOnScroll()      // 滚结果时别把键盘收掉，收掉浮层会跟着消失
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.stroke.opacity(0.55), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
    }

    /// 浮层里的一行：比正文里的结果卡更紧，一屏能多看两条。
    private func searchPanelRow(_ p: SearchService.Place) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "mappin")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(AppTheme.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.text)
                    .lineLimit(1)
                if !p.address.isEmpty {
                    Text(p.address)
                        .font(.caption)
                        .foregroundColor(AppTheme.sub)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let d = distanceTo(p) {
                Text(d).font(.caption.weight(.semibold)).foregroundColor(AppTheme.accent).fixedSize()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.sub.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 导航卡里的快捷入口：灰底圆角、整块可点。
    private func naviQuickAction(title: String, icon: String, enabled: Bool = true,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundColor(enabled ? AppTheme.accent : AppTheme.sub)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.sunken))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    /// 导航页下半：轨迹概览。卡片吃掉剩余高度，缩略图弹性伸缩，页面不整体滑。
    /// 卡片够高才补「更早的记录」，那一段在卡内自己滚；不够高就只留缩略图和最近一次。
    private var rideGlanceCard: some View {
        GeometryReader { g in
            // 108 = 上下内边距 28 + 标题行 44 + 两段间距 20 + 指标行 16；记录中多一行占 26
            let fixedH: CGFloat = 108 + (rides.active == nil ? 0 : 26)
            let earlier = max(0, rides.rides.count - 1)
            let cap = 12                                          // 卡里最多列 12 条更早的
            let listRoom = g.size.height - fixedH - 110 - 10       // 缩略图至少留 110，轨迹形状才看得清
            let showList = earlier > 0 && listRoom >= 72
            let listH = showList ? min(150, min(listRoom, CGFloat(min(earlier, cap)) * 72)) : 0
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("轨迹").font(.headline).foregroundColor(AppTheme.text)
                        if !rides.rides.isEmpty {
                            Text(monthRideSummary).font(.caption).foregroundColor(AppTheme.sub)
                        }
                    }
                    Spacer(minLength: 8)
                    GlassChip(title: "全部", icon: "list.bullet", tint: Self.cyan, compact: true) { showRides = true }
                }

                if let active = rides.active {
                    HStack(spacing: 6) {
                        Circle().fill(AppTheme.green).frame(width: 7, height: 7)
                        Text("记录中 · \(active.mode) · \(NaviBridge.distText(Int(active.meters)))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.accent)
                    }
                }

                if let latest = rides.rides.first {
                    NavigationLink(destination: RideDetailView(ride: latest)) {
                        RideTrackMapView(fixes: latest.fixes, interactive: false, lineWidth: 3, compactMarkers: true)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 84, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 6) {
                        Text("最近一次").font(.caption.weight(.semibold)).foregroundColor(AppTheme.text)
                        Text("\(timeLabel(latest.started)) · \(NaviBridge.distText(Int(latest.meters))) · \(durationText(latest))")
                            .font(.caption).foregroundColor(AppTheme.sub).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "location.north.line")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(AppTheme.sub.opacity(0.7))
                        Text(rides.active == nil ? "还没有轨迹" : "这条轨迹正在记录")
                            .font(.subheadline.weight(.semibold)).foregroundColor(AppTheme.text)
                        Text(rides.active == nil
                             ? "真实导航或巡航开始时自动记录，模拟导航不记。"
                             : "结束导航或巡航后，缩略图和里程会出现在这里。")
                            .font(.caption).foregroundColor(AppTheme.sub)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 更早的记录在卡片里自己滚，不把整页顶长
                if showList {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(rides.rides.dropFirst().prefix(cap).enumerated()), id: \.element.id) { idx, ride in
                                NavigationLink(destination: RideDetailView(ride: ride)) {
                                    RideListRow(ride: ride)
                                        .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                if idx < min(earlier, cap) - 1 {
                                    Divider().padding(.leading, 76).opacity(0.3)
                                }
                            }
                        }
                    }
                    .keepKeyboardOnScroll()
                    .frame(height: listH)
                }
            }
            .padding(14)
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(AppTheme.card))
        }
        .frame(minHeight: 200, maxHeight: .infinity)
        // 浮层盖在这张卡上方；点卡片空白处顺手收掉浮层，不然用户会以为卡点不动了
        .contentShape(Rectangle())
        .onTapGesture { if searchFocused { closeSearch() } }
    }

    /// 「收藏地点」：收藏地点（自定义标签、按标签筛选、改/删标签）与最近搜索都收进这个弹窗。
    private var favoritesSheet: some View {
        FavoritesSheet { place in
            showFavorites = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                page = 0
                choose(place)
            }
        }
    }

    /// 离现在位置的直线距离（搜索结果、最近搜索右边显示）
    private func distanceTo(_ p: SearchService.Place) -> String? {
        guard let me = navi.myPosition() else { return nil }
        return NaviBridge.distText(Int(NaviBridge.distM(me.lat, me.lng, p.lat, p.lng)))
    }

    /// 搜索、收藏和最近目的地统一进入摩托车路线规划。
    private func choose(_ p: SearchService.Place) {
        guard !navi.navigating else {
            // 先把浮层收掉，否则这句提示会被结果面板盖住
            closeSearch()
            shareStatus = "导航仍在运行；如需更换目的地，请先结束导航"
            return
        }
        guard !independent.running else {
            closeSearch()
            shareStatus = "请先结束当前摩托车导航"
            return
        }
        search.clear()
        closeSearch()             // 停查询、收浮层、收键盘
        query = p.name
        shareStatus = ""
        History.shared.add(p)
        if needAmapKey() { return }
        independentDestination = p
        independent.arrived = false
        showWebMotor = true
    }

    /// 读剪贴板里的高德分享链接，还原路线后按它规划
    private func pasteShare() {
        closeSearch()             // 导入的提示写在卡片里，别让搜索浮层压在上面
        guard let t = UIPasteboard.general.string, AmapShare.findUrl(t) != nil else {
            shareStatus = "剪贴板里没有高德的分享链接：先在高德里打开路线 → 分享 → 复制链接"
            return
        }
        importShare(t)
    }

    /// 导入高德分享的路线（剪贴板粘贴，或者从高德“分享到导一导”过来）
    private func importShare(_ t: String) {
        guard AmapShare.findUrl(t) != nil else { closeSearch(); shareStatus = "分享的内容里没有高德链接"; return }
        if navi.navigating || WebMotorSession.shared.running {
            closeSearch(); shareStatus = "正在导航：先结束导航，再导入分享的路线"; return
        }
        hideKeyboard()
        shareBusy = true
        shareStatus = "正在读取高德分享的路线…"
        pendingShare=t
        let sequence=UUID();shareImportID=sequence
        Task { @MainActor in
            defer{if shareImportID==sequence{shareBusy=false}}
            do{
                let r=try await AmapWebSession.loadShare(t)
                guard shareImportID==sequence,!navi.navigating,!WebMotorSession.shared.running else{shareStatus="导航状态已改变，请结束后重新导入";return}
                pendingShare=""
                let name=r.endName.isEmpty ? "分享的目的地":r.endName
                query=name;search.clear()
                guard r.kind == "摩托车" else {
                    shareStatus="这个版本只保留摩托出行，请在高德中选择摩托车路线后重新分享"
                    return
                }
                shareStatus="已读取摩托车路线 \(NaviBridge.distText(r.distance>0 ? r.distance:Int(r.total)))" +
                    (r.restored ? "":"（高德未确认原样还原，请核对地图）")
                History.shared.add(SearchService.Place(name:name,address:"",lat:r.endLat,lng:r.endLng))
                independentDestination=nil
                independent.arrived=false
                WebMotorSession.shared.route=MotorRoutes.fromShare(r)
                showWebMotor=true
            }catch{
                guard shareImportID==sequence else{return}
                shareStatus="读取失败：\(error.localizedDescription)；可完成网页验证后重试"
            }
        }
    }

    // MARK: 巡航
    /// 卡里的「巡航模式」：不设目的地也能看地图和道路提醒。
    private var cruiseModeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("不设目的地，也能查看地图和道路提醒")
                    .font(.caption).foregroundColor(ContentView.sub)
                Spacer(minLength: 4)
                if navi.cruising {
                    Text("进行中 · \(navi.uiSpeed) km/h")
                        .font(.caption.weight(.semibold)).foregroundColor(AppTheme.accent)
                }
            }
            PillButton(title: navi.cruising ? "结束巡航" : "开始巡航", color: navi.cruising ? Color.gray : ContentView.cyan.opacity(0.8),
                       enabled: !navi.navigating && !WebMotorSession.shared.running) {
                cruiseNote = ""
                if navi.cruising { navi.stopCruise() }
                else if !needAmapKey(), let err = navi.startCruise() { cruiseNote = err }
            }
            Text("连续停车 10 分钟后自动结束。")
                .font(.caption).foregroundColor(ContentView.sub)
            if !cruiseNote.isEmpty { Text(cruiseNote).font(.footnote).foregroundColor(AppTheme.orange) }
        }
    }

    // MARK: 圆屏设置
    /// 屏幕设置按功能拆卡：开机动画 / 音乐与歌词 / 屏幕方向 / 屏幕亮度。
    private var settingsCard: some View {
        VStack(spacing: 16) {
            bootCard
            musicControlCard
            screenRotationCard
            screenBrightnessCard
        }
    }

    private var bootCard: some View {
        CardView {
            Text("开机动画").font(.headline).foregroundColor(AppTheme.text)
            Picker("开机动画", selection: $settings.bootBrand) {
                ForEach(Settings.bootBrands.indices, id: \.self) { i in Text(Settings.bootBrands[i]).tag(i) }
            }.tint(AppTheme.accent)
            Text(settings.bootStatus).font(.caption).foregroundColor(AppTheme.sub)
        }
    }

    private var musicControlCard: some View {
        CardView {
            Text("音乐与歌词").font(.headline).foregroundColor(AppTheme.text)
            Toggle("音乐控制", isOn: $settings.musicHID).foregroundColor(AppTheme.text).tint(AppTheme.pink)
            if settings.musicHID {
                Text(ble.mediaHIDSupported
                     ? (ble.mediaHIDReady && ble.mediaHIDMode ? "媒体按键已就绪" : ble.mediaAMSControls > 0 && ble.mediaHIDMode ? "音乐控制已就绪" : "请在 iPhone 设置 → 蓝牙中配对 MotoNav；按圆屏配对码提示完成")
                     : "请连接圆屏并更新到支持音乐控制的固件")
                    .font(.caption).foregroundColor(AppTheme.sub)
                if !ble.mediaSongInfo.isEmpty {
                    Text(ble.mediaSongInfo).font(.caption).foregroundColor(AppTheme.accent)
                }
                Toggle("显示逐句歌词", isOn: $settings.musicLyrics).foregroundColor(AppTheme.text).tint(AppTheme.pink)
                Text("开启后自动匹配歌词，未匹配到时显示歌名和歌手。")
                    .font(.caption).foregroundColor(AppTheme.sub)
                if !settings.musicLyrics && ble.mediaLyricsActive { Text("正在关闭圆屏歌词…").font(.caption).foregroundColor(AppTheme.sub) }
                if settings.musicLyrics {
                    Text(ble.mediaLyricsSupported ? "播放音乐后自动匹配歌词" : "请更新圆屏固件以显示歌词")
                        .font(.caption).foregroundColor(AppTheme.accent)
                }
                Text("先在音乐 App 中播放，再用圆屏切歌或暂停。歌名和歌手由播放器提供。")
                    .font(.caption).foregroundColor(AppTheme.sub)
            } else {
                Button("授权 Apple Music 圆屏控制") { MusicBridge.shared.authorize() }
                    .foregroundColor(AppTheme.accent)
            }
        }
    }

    private var screenRotationCard: some View {
        CardView {
            Text("屏幕方向").font(.headline).foregroundColor(AppTheme.text)
            RotationDial(degrees: $settings.rotationDeg)      // iOS v0.5.1 按住圆盘转动调角度
            Text("拖动圆盘调整方向，蓝色指针代表画面上方。")
                .font(.caption2).foregroundColor(AppTheme.sub)
        }
    }

    private var screenBrightnessCard: some View {
        CardView {
            Text("屏幕亮度").font(.headline).foregroundColor(AppTheme.text)
            Toggle("亮度跟着昼夜自动调", isOn: $settings.brightAuto).foregroundColor(AppTheme.text).tint(AppTheme.pink)
            if settings.brightAuto {
                HStack {
                    Text("白天").foregroundColor(AppTheme.text)
                    Slider(value: $settings.brightDay, in: 5...255, step: 5).tint(AppTheme.pink)
                    Text("\(Int(settings.brightDay))").font(.caption).foregroundColor(AppTheme.sub).frame(width: 34)
                }
                HStack {
                    Text("夜间").foregroundColor(AppTheme.text)
                    Slider(value: $settings.brightNight, in: 5...255, step: 5).tint(AppTheme.pink)
                    Text("\(Int(settings.brightNight))").font(.caption).foregroundColor(AppTheme.sub).frame(width: 34)
                }
                if !settings.brightDesc.isEmpty { Text(settings.brightDesc).font(.caption2).foregroundColor(AppTheme.sub) }
            } else {
                HStack {
                    Text("亮度").foregroundColor(AppTheme.text)
                    Slider(value: $settings.brightness, in: 5...255, step: 5).tint(AppTheme.pink)
                    Text("\(Int(settings.brightness))").font(.caption).foregroundColor(AppTheme.sub).frame(width: 34)
                }
            }
        }
    }

    /// 屏幕显示按功能拆卡：导航信息 / 地图与路线 / 夜间与弯道。
    private var displayCard: some View {
        VStack(spacing: 16) {
            navigationInfoCard
            mapDisplayCard
            nightCurveCard
        }
    }

    private var navigationInfoCard: some View {
        CardView {
            Text("导航信息").font(.headline).foregroundColor(AppTheme.text)
            Toggle("路程进度环", isOn: $settings.progressRing).foregroundColor(AppTheme.text).tint(Self.pink)
            Picker("预判", selection: $settings.leadMs) {
                Text("关闭").tag(0); Text("0.3秒").tag(300); Text("0.6秒").tag(600)
            }.pickerStyle(.segmented)
            HStack {
                Text("风格").foregroundColor(AppTheme.text)
                Spacer()
                Picker("风格", selection: $settings.theme) {
                    ForEach(Settings.themeOrder, id: \.self) { t in Text(Settings.themeName(t)).tag(t) }
                }
                .tint(AppTheme.accent)
            }
            Text(Settings.themeDesc(settings.theme)).font(.footnote).foregroundColor(AppTheme.sub)
        }
    }

    private var mapDisplayCard: some View {
        CardView {
            Text("地图与路线").font(.headline).foregroundColor(AppTheme.text)
            Toggle("小地图", isOn: $settings.mapOn).foregroundColor(AppTheme.text).tint(AppTheme.pink)
            if settings.mapOn {
                if settings.mapSource == MapFeeder.SRC_AMAP && settings.theme == 1 {
                    Toggle("俯视建筑轮廓", isOn: $settings.buildings).foregroundColor(AppTheme.text).tint(AppTheme.pink)
                    if ble.isReady && !ble.buildingsSupported {
                        Text("当前圆屏暂不支持建筑轮廓，将显示普通地图。")
                            .font(.caption).foregroundColor(Self.sub)
                    }
                }
                Text(Self.userMessage(map.offlineStatus)).font(.caption).foregroundColor(AppTheme.sub)
                Text("前台优先准备整条路线的道路底图，随后补充建筑。道路全部就绪后可锁屏；未缓存区域需回前台补充。")
                    .font(.caption2).foregroundColor(AppTheme.sub)
                Text("走过的路线").foregroundColor(AppTheme.text)
                Picker("走过的路线", selection: $settings.trail) {
                    Text("变灰").tag(1); Text("擦除").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("清爽模式", isOn: $settings.clean).foregroundColor(AppTheme.text).tint(AppTheme.pink)
                Text("仅保留地图和路线，隐藏其他提示").font(.caption2).foregroundColor(AppTheme.sub)
                Button("地图显示问题"){showMapReport=true}
            }
        }
    }

    private var nightCurveCard: some View {
        CardView {
            Text("夜间与弯道").font(.headline).foregroundColor(AppTheme.text)
            Picker("夜间配色", selection: $settings.nightMode) {
                Text("自动（日出日落）").tag(0); Text("白天").tag(1); Text("夜间").tag(2)
            }
            .pickerStyle(.segmented)
            if !settings.nightDesc.isEmpty { Text(settings.nightDesc).font(.caption2).foregroundColor(AppTheme.sub) }
            Toggle("弯道急缓上色", isOn: $settings.curve).foregroundColor(AppTheme.text).tint(AppTheme.pink)
        }
    }
    private var voiceCard: some View {
        CardView {
            Text("导航语音").foregroundColor(AppTheme.text).bold()
            Toggle("导航静音", isOn: $settings.voiceMuted)
            Toggle("播报时压低音乐", isOn: $settings.duck)
            Picker("系统音色", selection: $voiceID) {
                Text("自动优选中文").tag("")
                ForEach(Self.zhSpeechVoices, id: \.identifier) { voice in
                    Text(voice.name).tag(voice.identifier)
                }
            }
            Text("语速"); Slider(value: $voiceRate, in: 0.3...0.6)
            Text("音调"); Slider(value: $voicePitch, in: 0.7...1.4)
            Button("试听播报") { Speech.shared.test() }
        }.foregroundColor(AppTheme.text).tint(Self.pink)
    }

    private static let zhSpeechVoices=AVSpeechSynthesisVoice.speechVoices().filter{$0.language.hasPrefix("zh")}

    // MARK: 密钥设置（卡片内直接维护，不再弹填写页）
    private var keyCard: some View { KeySettingsCard() }

    /// 没填高德密钥：切到「我的」并把「通用」推开，不再弹填写页。
    /// 密钥卡片在缺 Key 时自己描橙边，落地就能看见要填哪里。
    private func openKeySettings() {
        hideKeyboard()
        page = 3
        // 切页那一帧「我的」还没建出来，NavigationLink 尚不存在；等它建好再推。
        // 等的时候用户可能已经点了别的 tab，那就别再强推，否则下次进「我的」会自动弹进「通用」。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard page == 3 else { return }
            settingsPush = .general
        }
    }

    /// 没填高德 key：跳到密钥设置，返回 true（调用的地方就不往下做了）
    private func needAmapKey() -> Bool {
        if settings.amapKeyInUse.isEmpty { openKeySettings(); return true }
        return false
    }

    /// Product-facing recovery hints; raw SDK, URL and transport details stay out of the interface.
    static func userMessage(_ raw:String)->String {
        let value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.range(of:#"https?://|NSURLError|Error Domain=|AMapError|HTTP|\bSDK\b|\bGCJ|\bWGS|数据包|毫秒|字节|0x[0-9a-fA-F]+"#,options:.regularExpression) != nil {
            if value.contains("登录") || value.contains("验证") { return "请完成高德登录或验证后重试" }
            if value.contains("地图") { return "地图暂未准备完成，请保持 App 在前台后重试" }
            return "暂时未能完成，请检查网络和服务配置后重试"
        }
        return value.replacingOccurrences(of:#"（-?\d+）"#,with:"",options:.regularExpression)
    }

    // MARK: 底部导航条（对齐 Apple Music：悬浮液态玻璃胶囊，内容从后方穿过时实时透色）
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<TabSpec.count, id: \.self) { i in tabButton(i) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .tabBarLiquidGlass(Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func tabButton(_ i: Int) -> some View {
        let selected = page == i
        let accent = AppTheme.tabAccents[i]
        return Button {
            hideKeyboard()
            page = i
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    // Apple Music：选中态是图标后的软色圆晕，不是整格白胶囊（白胶囊会盖死玻璃折射）
                    if selected {
                        Circle()
                            .fill(accent.opacity(0.18))
                            .frame(width: 44, height: 32)
                    }
                    Image(systemName: selected ? TabSpec.fillIcons[i] : TabSpec.icons[i])
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(selected ? accent : AppTheme.sub)
                        .frame(width: 44, height: 28)
                }
                Text(TabSpec.titles[i])
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? accent : AppTheme.sub)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 右侧竖栏（Duo 外屏：同系液态玻璃竖条）
    private func rightRail(systemEdge: CGFloat) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: systemEdge > 0 ? 170 : 12)
            ForEach(0..<TabSpec.count, id: \.self) { i in railButton(i) }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 10)
        .frame(width: max(66, systemEdge))
        .tabBarLiquidGlass(Capsule())
        .padding(.vertical, 8).padding(.trailing, 6)
    }

    private func railButton(_ i: Int) -> some View {
        let selected = page == i
        let accent = AppTheme.tabAccents[i]
        return Button {
            hideKeyboard()
            page = i
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if selected {
                        Circle()
                            .fill(accent.opacity(0.18))
                            .frame(width: 46, height: 34)
                    }
                    Image(systemName: selected ? TabSpec.fillIcons[i] : TabSpec.icons[i])
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(selected ? accent : AppTheme.sub)
                        .frame(width: 46, height: 30)
                }
                Text(TabSpec.titles[i])
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? accent : AppTheme.sub)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 收藏地点弹窗

/// 「收藏地点」弹窗：收藏地点（自定义标签、按标签筛选、改/删标签）与最近搜索。
/// 标签存在本机，只影响筛选和显示，不参与规划。
struct FavoritesSheet: View {
    @ObservedObject private var favorites = Favorites.shared
    @ObservedObject private var history = History.shared
    /// 选中地点后交回 ContentView：先关弹窗，再进规划页。
    let onPick: (SearchService.Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0                    // 0 收藏地点，1 最近搜索
    @State private var filter = ""                // 空 = 全部
    @State private var editing: Favorites.Place?
    @State private var tagDraft = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("来源", selection: $tab) {
                    Text("收藏地点").tag(0)
                    Text("最近搜索").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

                if tab == 0 { favoritesList } else { recentList }
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle(tab == 0 ? "收藏地点" : "最近搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .sheet(item: $editing) { place in tagEditor(place) }
        // 筛选中的标签被删光后回到「全部」，不给用户留一个空列表
        .onChange(of: favorites.tags) { tags in
            if !filter.isEmpty && !tags.contains(filter) { filter = "" }
        }
    }

    // MARK: 收藏地点

    private var favoritesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !favorites.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tagChip("全部", active: filter.isEmpty) { filter = "" }
                            ForEach(favorites.tags, id: \.self) { tag in
                                tagChip(tag, active: filter == tag) { filter = filter == tag ? "" : tag }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                let shows = favorites.taggedPlaces(filter)
                if shows.isEmpty {
                    emptyHint(filter.isEmpty
                              ? "还没有收藏地点。选好目的地后，可在规划页点「收藏目的地」。"
                              : "这个标签下还没有地点。")
                } else {
                    VStack(spacing: 8) {
                        ForEach(shows) { place in favoriteRow(place) }
                    }
                }
            }
            .padding(16)
        }
    }

    /// 一条收藏：左边点开去规划，右边菜单管标签和删除。
    private func favoriteRow(_ place: Favorites.Place) -> some View {
        HStack(spacing: 8) {
            Button { onPick(place.searchPlace) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        // 标签单独一行，长标签不会把名称挤成一条缝
                        if !place.tagText.isEmpty { tagBadge(place.tagText) }
                        if !place.address.isEmpty {
                            Text(place.address).font(.caption).foregroundColor(AppTheme.sub).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.sub.opacity(0.55))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button { beginEditing(place) } label: {
                    Label(place.tagText.isEmpty ? "添加标签" : "修改标签", systemImage: "tag")
                }
                if !place.tagText.isEmpty {
                    Button { favorites.setTag(nil, for: place) } label: { Label("移除标签", systemImage: "tag.slash") }
                }
                Button(role: .destructive) { favorites.remove(place) } label: { Label("删除收藏", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.sub)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("管理「\(place.name)」的标签")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.card))
    }

    private func tagChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundColor(active ? .white : AppTheme.accent)
                .background(Capsule().fill(active ? AppTheme.accent : AppTheme.accentSoft))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppTheme.accentSoft))
            .fixedSize()
    }

    // MARK: 标签编辑

    private func beginEditing(_ place: Favorites.Place) {
        tagDraft = place.tagText
        editing = place
    }

    private func tagEditor(_ place: Favorites.Place) -> some View {
        NavigationView {
            Form {
                Section {
                    TextField("标签，例如 家、公司", text: $tagDraft)
                        // 与 Favorites.setTag 的上限一致，输入时就截住，避免保存时静默变短
                        .onChange(of: tagDraft) { if $0.count > 16 { tagDraft = String($0.prefix(16)) } }
                } header: {
                    Text(place.name).lineLimit(1)
                } footer: {
                    Text("标签只存在本机，同一个标签可以标多个地点，最多 16 个字。")
                }
                if !favorites.tags.isEmpty {
                    Section {
                        ForEach(favorites.tags, id: \.self) { tag in
                            Button { tagDraft = tag } label: {
                                HStack {
                                    Text(tag).foregroundColor(AppTheme.text)
                                    Spacer()
                                    if tag == tagDraft {
                                        Image(systemName: "checkmark").foregroundColor(AppTheme.accent)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("已有标签")
                    }
                }
                if !place.tagText.isEmpty {
                    Section {
                        Button("移除标签", role: .destructive) {
                            favorites.setTag(nil, for: place)
                            editing = nil
                        }
                    }
                }
            }
            .navigationTitle("标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        favorites.setTag(tagDraft, for: place)
                        editing = nil
                    }
                }
            }
        }
    }

    // MARK: 最近搜索

    private var recentList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if history.places.isEmpty {
                    emptyHint("搜索并选择目的地后会出现在这里。")
                } else {
                    VStack(spacing: 8) {
                        ForEach(history.places.prefix(12)) { p in recentRow(p) }
                    }
                    Button { history.clear() } label: {
                        Text("清除记录")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(AppTheme.sub)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func recentRow(_ p: SearchService.Place) -> some View {
        Button { onPick(p) } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.sub)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppTheme.sunken))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name).font(.subheadline.weight(.semibold)).foregroundColor(AppTheme.text).lineLimit(1)
                    if !p.address.isEmpty {
                        Text(p.address).font(.caption).foregroundColor(AppTheme.sub).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let d = distanceText(p) {
                    Text(d).font(.caption.weight(.semibold)).foregroundColor(AppTheme.accent).fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.sub.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.card))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func distanceText(_ p: SearchService.Place) -> String? {
        guard let me = NaviBridge.shared.myPosition() else { return nil }
        return NaviBridge.distText(Int(NaviBridge.distM(me.lat, me.lng, p.lat, p.lng)))
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppTheme.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

// MARK: - 小组件

/// 搜索框在屏幕上的位置（全局坐标）。结果浮层靠它贴到输入框正下方，不用写死坐标。
private struct SearchFieldAnchorKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 { value = next }
    }
}

private struct SearchFieldAnchor: View {
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: SearchFieldAnchorKey.self,
                                   value: g.frame(in: .global))
        }
    }
}

struct CardView<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(ContentView.card))

    }
}

struct PillButton: View {
    let title: String
    let color: Color
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Capsule().fill(enabled ? color : Color.gray.opacity(0.4)))
        }
        .disabled(!enabled)
    }
}

/// 收起键盘
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private extension View {
    /// 内容一屏放得下时不要回弹，避免看起来还能再滑一点。
    @ViewBuilder func scrollBounceBehaviorIfFits() -> some View {
        if #available(iOS 16.4, *) { scrollBounceBehavior(.basedOnSize) } else { self }
    }

    /// 滑动列表时不收键盘。iOS 16 起 ScrollView 默认一滚就收，搜索浮层会跟着消失。
    @ViewBuilder func keepKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) { self.scrollDismissesKeyboard(.never) } else { self }
    }
}

enum TabSpec {
    static let count=4
    static let titles=["导航","轨迹","设备","我的"]
    static let icons=["location.north","map","circle.circle","person"]
    static let fillIcons=["location.north.fill","map.fill","circle.circle.fill","person.fill"]
}
enum TabLayout {
    static func isWide(size:CGSize,hSizeClass:UserInterfaceSizeClass?)->Bool {size.width>=700}
    static func useSideRail(size:CGSize,hSizeClass:UserInterfaceSizeClass?,placement:Int)->Bool {
        if placement==1{return false};if placement==2{return true}
        return size.width>=700 && size.width>size.height
    }
}
