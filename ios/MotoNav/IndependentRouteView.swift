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
        busy=true;message="正在规划\(mode.rawValue)路线…"
        task=Task { @MainActor [weak self] in
            // v1.2 起步不再依赖常驻定位：没有手动起点就现等一次定位，等待期间保持 busy（页面显示转圈）
            let origin:MotorPoint
            let manualStart=self?.start          // 显式取一次：self?.start 是双重可选，直接 if let 只解一层
            if let start=manualStart{
                origin=start
            }else{
                self?.message="正在定位…"
                let fix=await LocationService.shared.currentFix()
                guard let self=self,self.generation==token,!Task.isCancelled else{return}
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
                VStack(alignment:.leading,spacing:16){
                    inputCard
                    HStack{
                        Button("路线历史"){showHistory=true};Spacer()
                        Button("高德登录／验证"){login=true}
                    }.font(.subheadline)
                    if waitingForInitialFix{Text("已选择目的地，等待当前位置后自动规划…").font(.footnote).foregroundColor(ContentView.sub)}
                    else if !model.message.isEmpty{Text(ContentView.userMessage(model.message)).font(.footnote).foregroundColor(ContentView.sub)}
                    if let route=selectedRoute{routeOptions(route)}
                    Text("账号过期时，可在这里重新登录高德。").font(.footnote).foregroundColor(ContentView.sub)
                    Text("锁屏前等待整条路线道路底图就绪；后台继续读取缓存、定位、语音和蓝牙，未缓存区域需回前台补充。").font(.footnote).foregroundColor(ContentView.sub)
                }.padding(16)
            }.background(ContentView.bg).navigationTitle("摩托车路线")
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("返回首页"){dismiss()}}}
        }.foregroundColor(AppTheme.text).tint(ContentView.pink)
        .sheet(isPresented:Binding(get:{pick != nil},set:{if !$0{pick=nil}})){
            RoutePointPicker(title:pick==0 ? "选择起点":"选择目的地",near:model.start){point in
                waitingForInitialFix=false
                if pick==0{model.start=point}else{model.end=point};model.invalidate();pick=nil
            }
        }
        .sheet(isPresented:$waypoints){RouteWaypointEditor(points:model.vias,near:model.start){points in
            waitingForInitialFix=false
            model.vias=points;model.invalidate()
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
            // v1.2 定位改成单次取点：这里主动等一次。单次失败不会再有 @Published 更新把它救回来，
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
    private var inputCard:some View {
        CardView{
            Text("摩托车路线")
                .font(.title3.bold())
            Text("确认起点和目的地，再添加沿途要经过的地点。")
                .font(.footnote).foregroundColor(ContentView.sub)
            Button{pick=0}label:{
                Label(model.start?.name.isEmpty == false ? model.start!.name:"我的位置（点此更改起点）",systemImage:"location")
                    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
            }
            if model.start != nil{Button("使用当前位置"){model.start=nil;model.invalidate()}.font(.footnote).frame(minHeight:36)}
            Divider().opacity(0.35)
            Button{pick=1}label:{
                Label(model.end?.name.isEmpty == false ? model.end!.name:"输入目的地",systemImage:"mappin.and.ellipse")
                    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
            }
            if let point=model.end{
                Button("收藏目的地"){Favorites.shared.add(SearchService.Place(name:point.name,address:"",lat:point.lat,lng:point.lng))}
                    .font(.footnote).frame(minHeight:36)
            }
            Button{waypoints=true}label:{
                Label(model.vias.isEmpty ? "添加途经点（最多三个）":"途经："+model.vias.map{$0.name}.joined(separator:" → "),systemImage:"point.topleft.down.curvedto.point.bottomright.up")
                    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
            }
            PillButton(title:model.busy ? "正在规划…":"规划摩托车路线",color:ContentView.pink,enabled:!model.busy && model.end != nil){
                waitingForInitialFix=false
                model.plan(.motorcycle)
            }
        }
    }
    private func routeOptions(_ route:MotorRoute)->some View {
        VStack(alignment:.leading,spacing:14){
            MotorMap(route:route,position:nil,overview:true).frame(height:260).clipShape(RoundedRectangle(cornerRadius:18))
            if !route.detailedGuidance {
                Text("已取得路线轨迹，暂无分段转向指引，请按地图路线行进。")
                    .font(.footnote).foregroundColor(ContentView.sub)
            }
            ForEach(Array(model.routes.enumerated()),id:\.offset){i,r in
                Button{model.selected=i}label:{
                    HStack{
                        Image(systemName:model.selected==i ? "checkmark.circle.fill":"circle")
                        VStack(alignment:.leading,spacing:4){Text("方案 \(i+1) · \(NaviBridge.durText(r.seconds))").bold();Text(NaviBridge.distText(r.totalMeters)).font(.subheadline)}
                        Spacer()
                    }.padding(14).background(RoundedRectangle(cornerRadius:14).fill(ContentView.card))
                }
            }
            PillButton(title:"开始导！",color:ContentView.pink,enabled:!model.busy){begin(route,false)}
            DisclosureGroup("模拟与高级选项") {
                VStack(alignment:.leading,spacing:12){
                    Picker("模拟速度",selection:$simulationSpeed){ForEach(NavigationSpeed.values,id:\.self){Text("\($0) km/h").tag($0)}}
                        .pickerStyle(.segmented)
                    GlassButton(title:"模拟导航",icon:"play.circle",style:.tinted,enabled:!model.busy){begin(route,true)}
                }
                .padding(.top,12)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppTheme.text)
            .padding(14)
            .background(RoundedRectangle(cornerRadius:14).fill(AppTheme.card))
        }
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
