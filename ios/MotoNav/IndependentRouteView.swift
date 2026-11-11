import SwiftUI
import CoreLocation

enum IndependentMode:String,CaseIterable,Identifiable {
    case motorcycle="摩托车",bicycle="自行车"
    var id:String{rawValue}
}

final class IndependentPlanner:ObservableObject {
    @Published var start:MotorPoint?
    @Published var end:MotorPoint?
    @Published var vias:[MotorPoint]=[]
    @Published var routes:[MotorRoute]=[]
    @Published var selected=0
    @Published var busy=false
    @Published var message=""
    private var generation=UUID()
    private var task:Task<Void,Never>?
    func invalidate(){generation=UUID();task?.cancel();task=nil;routes=[];selected=0;busy=false}
    func load(_ entry:SavedMotorPlan){
        guard entry.valid else{return}
        invalidate();start=entry.request.start;end=entry.request.end;vias=entry.request.vias
        message="已恢复起终点和途经点，点击规划获取最新路线"
    }
    func plan(_ mode:IndependentMode){
        guard !WebMotorSession.shared.running,!NaviBridge.shared.navigating,!NaviBridge.shared.cruising else{message="请先结束当前导航或巡航";return}
        guard !Settings.shared.keysMissing else{message="请先填写自己的高德 iOS Key";return}
        guard let end=end else{message="请选择目的地";return}
        invalidate();let token=generation
        // v1.3 起步不再依赖常驻定位：没有手动起点就得先等一次定位。文案在设置 busy 时一并定好，别先闪一帧“正在规划”
        busy=true;message=start == nil ? "正在定位…" : "正在规划\(mode.rawValue)路线…"
        task=Task { @MainActor [weak self] in
            let origin:MotorPoint
            let manualStart=self?.start          // 显式取一次：self?.start 是双重可选，直接 if let 只解一层
            if let start=manualStart{
                origin=start
            }else{
                guard let self=self,self.generation==token,!Task.isCancelled else{return}   // 视图已关就别再发起定位
                let fix=await LocationService.shared.currentFix()
                guard self.generation==token,!Task.isCancelled else{return}
                guard let fix=fix else{
                    self.busy=false
                    self.message=LocationService.shared.isAuthorized ? "定位超时，可手动选择起点后重试" : "没有定位权限，请在系统设置里允许定位，或手动选择起点"
                    return
                }
                let g=MapGeo.wgsToGcj(fix.coordinate.latitude,fix.coordinate.longitude)
                origin=MotorPoint(lat:g.lat,lng:g.lng,name:"我的位置")
                self.message="正在规划\(mode.rawValue)路线…"
            }
            let request=MotorRequest(start:origin,end:end,vias:mode == .bicycle ? []:vias,bicycle:mode == .bicycle)
            do{
                let result=try await MotorRoutes.load(request)
                guard let self=self,self.generation==token,!Task.isCancelled else{return}
                self.routes=result;self.selected=0;self.busy=false
                self.message="已找到 \(result.count) 条路线，请选择方案"
                if let first=result.first{MotorPlanHistory.shared.save(first)}
            }catch{
                guard let self=self,self.generation==token,!Task.isCancelled else{return}
                self.busy=false;self.message=error.localizedDescription
            }
        }
    }
}

struct MotorLoginView:View {
    @StateObject private var browser=MotorBrowser()
    let page:URL?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationView{
            VStack{
                Text("仅在登录或验证时打开网页。登录保存在本机，正常规划可直接在 App 完成。").font(.caption).padding()
                MotorBrowserView(browser:browser)
                Text(ContentView.userMessage(browser.status)).font(.caption)
            }.navigationTitle("高德登录／验证").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}}}
        }.onAppear{if let page=page{browser.web.load(URLRequest(url:page))}}
    }
}

struct IndependentPlannerView:View {
    @StateObject private var model=IndependentPlanner()
    @ObservedObject private var location=LocationService.shared
    @ObservedObject var guide=WebMotorSession.shared
    @State private var pick:Int?
    @State private var login=false
    @State private var loaded=false
    @State private var waitingForInitialFix=false
    @State private var waypoints=false
    @State private var showHistory=false
    @State private var simulationSpeed=60
    @Environment(\.dismiss) private var dismiss
    private let initialDestination: SearchService.Place?
    init(initialDestination:SearchService.Place? = nil){
        self.initialDestination=initialDestination
    }
    var body:some View {
        NavigationView{
            ScrollView{
                VStack(alignment:.leading,spacing:14){
                    header
                    inputCard
                    // 工具行贴着起终点卡，别被方案区挤到页面最底下
                    toolRow
                    if waitingForInitialFix{
                        notice("已选择目的地，等待当前位置后自动规划…")
                    }else if !model.message.isEmpty && !model.busy{
                        // 规划中由 planningCard 显示进度，这里再说一遍就是重复
                        notice(ContentView.userMessage(model.message))
                    }
                    if let route=selectedRoute{routeSection(route)}
                    else if model.busy{planningCard}
                    notes
                }
                .padding(.horizontal,16)
                .padding(.top,6)
                .padding(.bottom,24)          // 底部留白交给 safeAreaInset 的底栏，这里只留常规间距
                .frame(maxWidth:760,alignment:.leading)
                .frame(maxWidth:.infinity)
            }
            .safeAreaInset(edge:.bottom,spacing:0){bottomBar}
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("返回首页"){dismiss()}}}
        }.foregroundColor(AppTheme.text).tint(AppTheme.accent)
        .sheet(isPresented:Binding(get:{pick != nil},set:{if !$0{pick=nil}})){
            RoutePointPicker(title:pick==0 ? "选择起点":"选择目的地",near:model.start){point in
                waitingForInitialFix=false
                if pick==0{model.start=point}else{model.end=point}
                // 已经有方案时改了起终点，旧方案作废：明确提示要重算，别让人以为还在看旧的三条
                let planned = !model.routes.isEmpty
                model.invalidate()
                if planned{model.message="起终点已改动，点「规划摩托车路线」重新算路"}
                pick=nil
            }
        }
        .sheet(isPresented:$waypoints){RouteWaypointEditor(points:model.vias,near:model.start){points in
            waitingForInitialFix=false
            let planned = !model.routes.isEmpty
            model.vias=points;model.invalidate()
            if planned{model.message="途经点已改动，点「规划摩托车路线」重新算路"}
        }}
        .sheet(isPresented:$showHistory){MotorHistoryView(bicycle:false){entry in
            waitingForInitialFix=false
            model.load(entry)
        }}
        .sheet(isPresented:$login){MotorLoginView(page:nil)}
        .onAppear{
            guard !loaded else{return};loaded=true
            LocationService.shared.refresh()
            if let destination=initialDestination {
                model.invalidate()
                model.end=MotorPoint(lat:destination.lat,lng:destination.lng,name:destination.name)
                planInitialDestination()
            } else {
                restoreSharedRoute()
            }
        }
        .onReceive(location.$location) { _ in
            if waitingForInitialFix { planInitialDestination() }
        }
        .onChange(of: guide.route?.id) { _ in
            // 规划页已打开时，也能接收高德新分享的路线。
            restoreSharedRoute()
        }
    }
    private func restoreSharedRoute(){
        guard !guide.running,let route=guide.route,!route.request.bicycle else{return}
        waitingForInitialFix=false
        model.invalidate()
        model.start=route.request.start
        model.end=route.request.end
        model.vias=route.request.vias
        model.routes=[route]
        model.selected=0
        model.message=""
    }
    private func planInitialDestination(){
        guard initialDestination != nil,model.end != nil,!model.busy else{return}
        if let fix=location.location,fix.horizontalAccuracy>=0,fix.horizontalAccuracy<=100,abs(fix.timestamp.timeIntervalSinceNow)<15{
            waitingForInitialFix=false
            model.plan(.motorcycle)
        }else if !waitingForInitialFix{
            waitingForInitialFix=true
            // v1.3 定位改成单次取点：这里主动等一次。单次失败不会再有 @Published 更新把它救回来，
            // 所以必须带超时收尾，否则会一直停在“等待当前位置后自动规划…”
            Task { @MainActor in
                let fix=await LocationService.shared.currentFix()
                guard self.waitingForInitialFix,!self.model.busy else{return}
                self.waitingForInitialFix=false
                if fix == nil{
                    self.model.message=LocationService.shared.isAuthorized ? "定位超时，请手动选择起点" : "没有定位权限，请在系统设置里允许定位，或手动选择起点"
                }else{
                    self.model.plan(.motorcycle)
                }
            }
        }
    }
    private var selectedRoute:MotorRoute?{model.routes.indices.contains(model.selected) ? model.routes[model.selected]:nil}
    private var header:some View {
        VStack(alignment:.leading,spacing:3){
            Text(model.routes.isEmpty ? "摩托车路线":"选择路线")
                .font(.system(size:28,weight:.heavy,design:.rounded))
                .foregroundColor(AppTheme.text)
            Text(headerSubtitle).font(.footnote).foregroundColor(AppTheme.sub).lineLimit(2)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }
    private var headerSubtitle:String {
        let from=model.start?.name.isEmpty == false ? model.start!.name : "当前位置"
        guard let end=model.end else{return "确认起点和目的地，再规划摩托车路线"}
        return "\(from) → \(end.name.isEmpty ? "目的地":end.name)"
    }
    private func notice(_ text:String)->some View {
        Label(text,systemImage:"info.circle")
            .font(.footnote).foregroundColor(AppTheme.sub)
            .frame(maxWidth:.infinity,alignment:.leading)
    }
    private var inputCard:some View {
        CardView{
            VStack(spacing:2){
                pointRow(icon:"circle.fill",tint:AppTheme.green,label:"起点",
                         value:model.start?.name.isEmpty == false ? model.start!.name : "我的位置",
                         action:{pick=0})
                Divider().opacity(0.3).padding(.vertical,2)
                pointRow(icon:"mappin",tint:AppTheme.red,label:"目的地",
                         value:model.end?.name.isEmpty == false ? model.end!.name : "选择目的地",
                         action:{pick=1})
            }
            PillButton(title:model.busy ? "正在规划…":"规划摩托车路线",color:AppTheme.accent,enabled:!model.busy && model.end != nil){
                waitingForInitialFix=false
                model.plan(.motorcycle)
            }
            .padding(.top,4)
        }
    }
    /// 起终点一行：左边色点标身份，右边箭头表示可改
    private func pointRow(icon:String,tint:Color,label:String,value:String,action:@escaping()->Void)->some View {
        Button(action:action){
            HStack(spacing:12){
                Image(systemName:icon)
                    .font(.system(size:13,weight:.bold))
                    .foregroundColor(tint)
                    .frame(width:30,height:30)
                    .background(Circle().fill(tint.opacity(0.14)))
                VStack(alignment:.leading,spacing:1){
                    Text(label).font(.caption2).foregroundColor(AppTheme.sub)
                    Text(value).font(.subheadline.weight(.semibold)).foregroundColor(AppTheme.text).lineLimit(1)
                }
                Spacer(minLength:8)
                Image(systemName:"chevron.right").font(.caption.weight(.bold)).foregroundColor(AppTheme.stroke)
            }
            .padding(.vertical,4)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    /// 途经 / 收藏 / 历史 / 登录：一行小胶囊，窄屏可以横着推
    private var toolRow:some View {
        ScrollView(.horizontal,showsIndicators:false){
            HStack(spacing:8){
                GlassChip(title:model.vias.isEmpty ? "途经点":"途经 \(model.vias.count)",icon:"arrow.triangle.branch",compact:true){waypoints=true}
                if model.end != nil{
                    GlassChip(title:"收藏目的地",icon:"star",compact:true){
                        guard let point=model.end else{return}
                        Favorites.shared.add(SearchService.Place(name:point.name,address:"",lat:point.lat,lng:point.lng))
                    }
                }
                if model.start != nil{
                    GlassChip(title:"使用当前位置",icon:"location.fill",compact:true){model.start=nil;model.invalidate()}
                }
                GlassChip(title:"路线历史",icon:"clock.arrow.circlepath",compact:true){showHistory=true}
                GlassChip(title:"高德登录",icon:"key.fill",compact:true){login=true}
            }
            .padding(.vertical,2)
        }
    }
    private var planningCard:some View {
        CardView{
            HStack(spacing:12){
                ProgressView()
                Text(model.message.isEmpty ? "正在规划摩托车路线…" : ContentView.userMessage(model.message)).font(.subheadline).foregroundColor(AppTheme.sub)
            }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        }
    }
    private var notes:some View {
        VStack(alignment:.leading,spacing:5){
            Text("账号过期时，用上面的「高德登录」重新登录。")
            Text("锁屏前等待整条路线底图就绪；后台继续读取缓存、定位、语音和蓝牙，未缓存区域需回前台补充。")
        }.font(.caption).foregroundColor(AppTheme.sub).padding(.top,2)
    }
    @ViewBuilder private var bottomBar:some View {
        // busy 时 routes 已被 invalidate 清空，这里必然有方案可选，不用再判进度态
        if let route=selectedRoute{
            VStack(spacing:0){
                Divider().opacity(0.35)
                PillButton(title:"开始导！",color:AppTheme.accent){begin(route,false)}
                    .padding(.horizontal,16).padding(.top,12).padding(.bottom,8)
            }
            // 铺满整条底栏，材质要一直铺到 Home 指示条下面，所以直接用 ultraThinMaterial 而不走 liquidGlass
            .background(.ultraThinMaterial,ignoresSafeAreaEdges:.bottom)
        }
    }
    /// 选方案：上面一张能看全三条线的地图，下面按方案列卡片；点哪条地图就高亮哪条
    private func routeSection(_ route:MotorRoute)->some View {
        VStack(alignment:.leading,spacing:12){
            MotorRoutesMap(routes:model.routes,selected:model.selected)
                .frame(height:300)
                .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:22,style:.continuous).strokeBorder(AppTheme.stroke.opacity(0.28),lineWidth:1))
                .overlay(alignment:.topLeading){
                    Text(model.routes.count > 1 ? "\(model.routes.count) 条方案 · 点选高亮":"高德分享路线")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.text)
                        .padding(.horizontal,10).padding(.vertical,6)
                        .liquidGlass(Capsule())
                        .padding(12)
                }
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("路线预览，共 \(model.routes.count) 条方案")
            VStack(spacing:8){
                ForEach(Array(model.routes.enumerated()),id:\.offset){i,r in routeRow(i,r)}
            }
            if !route.detailedGuidance{
                Label("已取得路线轨迹，暂无分段转向指引，请按地图路线行进。",systemImage:"exclamationmark.triangle")
                    .font(.footnote).foregroundColor(AppTheme.amber)
            }
            advancedCard
        }
    }
    /// 方案卡：左缘一条色条对应地图上的线，主体是时长 + 补充信息，右侧勾
    private func routeRow(_ index:Int,_ route:MotorRoute)->some View {
        let on=model.selected==index
        let detail=routeDetail(route)
        let fastest=model.routes.map{$0.seconds}.min() ?? route.seconds
        let extra=max(0,(route.seconds-fastest)/60)
        // 只有一条路线（高德分享）时没有「选哪条」这回事，就不打推荐标
        let recommended=model.routes.count>1 && index==fastestIndex
        return Button{
            withAnimation(.easeOut(duration:0.16)){model.selected=index}
        }label:{
            VStack(alignment:.leading,spacing:5){
                HStack(alignment:.center,spacing:8){
                    Text(NaviBridge.durText(route.seconds))
                        .font(.system(size:19,weight:.semibold).monospacedDigit())
                        .foregroundColor(AppTheme.text)
                    if recommended{tagChip("推荐",strong:true)}
                    else if extra>0{tagChip("+\(extra) 分",strong:false)}
                    Spacer(minLength:0)
                    Image(systemName:on ? "checkmark.circle.fill":"circle")
                        .font(.system(size:20))
                        .foregroundColor(on ? AppTheme.accent : AppTheme.stroke.opacity(0.8))
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.sub)
                    .lineLimit(1)
            }
            // 左边 8 + 色条 4 + 间距 12 = 文字从 24 起，别让大字贴着色条
            .padding(.leading,24).padding(.trailing,14).padding(.vertical,13)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(RoundedRectangle(cornerRadius:16,style:.continuous).fill(on ? AppTheme.accentSoft : AppTheme.card))
            .overlay(RoundedRectangle(cornerRadius:16,style:.continuous)
                .strokeBorder(on ? AppTheme.accent.opacity(0.5) : Color.clear,lineWidth:1.5))
            .overlay(alignment:.leading){
                Capsule()
                    .fill(on ? AppTheme.accent : AppTheme.stroke.opacity(0.42))
                    .frame(width:4)
                    .padding(.vertical,12)
                    .padding(.leading,8)
            }
            .contentShape(RoundedRectangle(cornerRadius:16,style:.continuous))
        }.buttonStyle(.plain)
        .accessibilityLabel("\(NaviBridge.durText(route.seconds))，\(detail)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
    /// 用时最短那一条的下标（推荐标挂在它身上，不假设高德第一条一定最快）
    private var fastestIndex:Int {
        model.routes.enumerated().min{$0.element.seconds < $1.element.seconds}?.offset ?? 0
    }
    private func tagChip(_ text:String,strong:Bool)->some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(strong ? AppTheme.accent : AppTheme.sub)
            .padding(.horizontal,8).padding(.vertical,3)
            .background(Capsule().fill(strong ? AppTheme.accentSoft : AppTheme.secondaryFill.opacity(0.75)))
    }
    /// 距离 + 主要经过的道路（最多两条），比单给公里数更有判断价值
    private func routeDetail(_ route:MotorRoute)->String {
        let distance=NaviBridge.distText(route.totalMeters)
        let roads=mainRoads(route)
        return roads.isEmpty ? distance : distance+" · "+roads
    }
    /// 主要道路：按分段里程挑最长两条再还原行进顺序。
    /// 不能直接取前两条——起点那几段常是几百米的小路，按顺序取会把「XX胡同」当成主干道。
    private func mainRoads(_ route:MotorRoute)->String {
        let named=route.steps.filter{!$0.road.isEmpty}
        guard !named.isEmpty else{return ""}
        var picked=Set(named.sorted{$0.distance>$1.distance}.prefix(2).map{$0.road})
        if !named.contains(where:{picked.contains($0.road) && $0.distance>0}){
            // 高德分享的路线没有分段里程，退回从开头几条里按顺序挑（去重后最多两条）
            picked=Set(named.prefix(4).map{$0.road})
        }
        var ordered:[String]=[]
        for step in named where picked.contains(step.road) && !ordered.contains(step.road){
            ordered.append(step.road)
            if ordered.count==2{break}
        }
        return ordered.joined(separator:" · ")
    }
    private var advancedCard:some View {
        DisclosureGroup{
            VStack(alignment:.leading,spacing:12){
                Picker("模拟速度",selection:$simulationSpeed){ForEach(NavigationSpeed.values,id:\.self){Text("\($0) km/h").tag($0)}}
                    .pickerStyle(.segmented)
                GlassButton(title:"模拟导航",icon:"play.circle",style:.tinted){
                    if let route=selectedRoute{begin(route,true)}
                }
            }
            .padding(.top,12)
        }label:{
            Label("模拟与高级选项",systemImage:"slider.horizontal.3")
                .font(.subheadline.weight(.semibold)).foregroundColor(AppTheme.text)
        }
        .tint(AppTheme.accent)
        .padding(16)
        .background(RoundedRectangle(cornerRadius:18,style:.continuous).fill(AppTheme.card))
    }
    private func begin(_ route:MotorRoute,_ simulate:Bool){
        guard !NaviBridge.shared.navigating,!NaviBridge.shared.cruising,!guide.running else{model.message="请先结束当前导航或巡航";return}
        History.shared.add(SearchService.Place(name:route.request.end.name,address:"",lat:route.request.end.lat,lng:route.request.end.lng))
        MotorPlanHistory.shared.save(route)
        guide.start(route,simulate:simulate,simulationSpeed:simulationSpeed)
    }
}

struct IndependentNavigationView: View {
    @ObservedObject var guide=WebMotorSession.shared
    @ObservedObject var settings=Settings.shared
    @ObservedObject var metadata=WebRouteMetadata.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmExit=false
    var body: some View {
        ZStack(alignment:.top){
            if let route=guide.route {MotorMap(route:route,position:guide.position,overview:guide.overview).ignoresSafeArea()}
            VStack(spacing:12){
                HStack(alignment:.center,spacing:18){
                    Image(systemName:arrow).font(.system(size:48,weight:.bold)).foregroundColor(ContentView.pink).frame(width:58)
                    VStack(alignment:.leading,spacing:6){
                        Text(NaviBridge.distText(guide.turnMetres)).font(.system(size:30,weight:.heavy))
                        Text(guide.instruction).font(.headline).lineLimit(2)
                        if !navigationNotice.isEmpty {Text(navigationNotice).font(.caption).foregroundColor(ContentView.sub)}
                    };Spacer(minLength:0)
                }.padding(18).background(RoundedRectangle(cornerRadius:22).fill(ContentView.bg.opacity(0.94)))
                Spacer()
                VStack(spacing:12){
                    HStack{
                        Text("\(guide.speed)").font(.system(size:32,weight:.bold))+Text(" km/h").font(.footnote)
                        Spacer()
                        VStack(alignment:.trailing){Text("剩余 \(NaviBridge.distText(guide.remaining))").bold();Text("约 \(NaviBridge.durText(guide.remainingSeconds))").font(.footnote)}
                    }
                    HStack(spacing: 8){
                        GlassChip(title:guide.overview ? "跟随" : "全览",icon:guide.overview ? "location.fill" : "map",compact:true){guide.overview.toggle()}
                            .frame(maxWidth:.infinity)
                        GlassChip(title:settings.voiceMuted ? "取消静音" : "静音",icon:settings.voiceMuted ? "speaker.slash" : "speaker.wave.2",compact:true){settings.voiceMuted.toggle();if settings.voiceMuted{Speech.shared.stopNow()}}
                            .frame(maxWidth:.infinity)
                        GlassChip(title:"设置",icon:"gearshape",compact:true){dismiss()}
                            .frame(maxWidth:.infinity)
                    }.font(.subheadline)
                    if guide.simulation {
                        HStack{Button(guide.paused ? "继续" : "暂停"){guide.paused.toggle()};Spacer();Button("\(guide.speed) km/h"){guide.speed=NavigationSpeed.next(guide.speed)}}
                    }
                    Button("结束导航"){confirmExit=true}.foregroundColor(.red)
                }.padding(18).background(RoundedRectangle(cornerRadius:22).fill(ContentView.bg.opacity(0.94)))
            }.padding(16)
            if guide.arrived {
                VStack(spacing:18){Text("已到达目的地").font(.title.bold());Button("返回首页"){guide.arrived=false;dismiss()}}
                    .padding(30).background(RoundedRectangle(cornerRadius:22).fill(ContentView.bg)).frame(maxHeight:.infinity)
            }
        }.foregroundColor(AppTheme.text).tint(ContentView.pink)
        .alert("结束导航？",isPresented:$confirmExit){Button("结束",role:.destructive){guide.stop();guide.arrived=false;dismiss()};Button("继续导航",role:.cancel){}}
    }
    private var navigationNotice:String {
        if guide.status.contains("重算失败") {return "重新规划暂未完成，将保留当前路线"}
        if guide.status.contains("正在重新规划") {return "偏离路线，正在重新规划…"}
        if guide.status.contains("已偏离路线") {return "已偏离路线"}
        if guide.status.contains("GPS") {return "定位信号较弱"}
        if guide.route?.detailedGuidance == false {return "按路线行进 · 暂无分段转向指引"}
        return guide.simulation ? "模拟导航":""
    }
    private var arrow:String {
        if guide.route?.detailedGuidance == false {return "point.topleft.down.curvedto.point.bottomright.up"}
        switch guide.turnDirection {case "L":return "arrow.turn.up.left";case "R":return "arrow.turn.up.right";case "SL":return "arrow.up.left";case "SR":return "arrow.up.right";case "U":return "arrow.uturn.left";default:return "arrow.up"}
    }
}
