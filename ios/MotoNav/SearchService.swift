import Foundation
import ObjectiveC
import CoreLocation

/// 版本：跟随 App 版本（见 Config.swift）
///
/// 目的地搜索：高德“输入提示”接口，优先显示附近的地方。
/// iOS v0.2.1 起只在按“搜索”时才查（原来边打字边查，拼音输入时每个字母都查一次，太费高德额度）；
/// 同样的关键词这次打开 App 查过就直接用上次的结果，不再查。
final class SearchService: NSObject, ObservableObject {
    static let shared = SearchService()

    struct Place: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let lat: Double
        let lng: Double
    }

    @Published var results: [Place] = []
    @Published var status = ""
    private var api: AMapSearchAPI?
    private var fuelRequest:AMapPOIAroundSearchRequest?
    private var activeSearch=""
    private var cache: [String: [Place]] = [:]         // 关键词 → 结果（只存在内存里）

    override init() {
        super.init()
        // 和 NaviBridge 一样：运行时登记协议，避免 Swift 方法名冲突
        class_addProtocol(SearchService.self, AMapSearchDelegate.self)
        rebuildAPI()
    }

    /// iOS v0.7 填了（或换了）高德 key 后重建搜索服务，不用重启 App
    func rebuildAPI() {
        api?.delegate = nil
        api = AMapSearchAPI()
        if let d = (self as AnyObject) as? AMapSearchDelegate { api?.delegate = d }
        cache = [:]
    }

    /// 按了“搜索”时调用（每按一次最多查一次高德）
    func search(_ text: String, near: (Double,Double)? = nil) {
        fuelRequest=nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { clear(); return }
        let around=near ?? LocationService.shared.location.map{l -> (Double,Double) in
            let g=MapGeo.wgsToGcj(l.coordinate.latitude,l.coordinate.longitude);return(g.lat,g.lng)
        }
        let location=around.map{String(format:"%.6f,%.6f",$0.1,$0.0)} ?? ""
        let searchKey=t+"|"+location
        activeSearch=searchKey
        if let r = cache[searchKey] {                           // 查过的不再花额度
            results = r
            status = r.isEmpty ? "没找到，换个说法试试" : ""
            return
        }
        let req = AMapInputTipsSearchRequest()
        req.keywords = t
        if !location.isEmpty {req.location=location}
        status = "搜索中…"
        api?.aMapInputTipsSearch(req)
    }

    func clear() { fuelRequest=nil;activeSearch="";results = []; status = "" }

    func searchFuel(near:(Double,Double)?=nil){
        let center=near ?? LocationService.shared.location.flatMap{fix -> (Double,Double)? in
            guard fix.horizontalAccuracy>=0,abs(fix.timestamp.timeIntervalSinceNow)<600 else{return nil}
            let g=MapGeo.wgsToGcj(fix.coordinate.latitude,fix.coordinate.longitude);return(g.lat,g.lng)
        }
        guard let center=center,MotorRequest.valid(center.0,center.1) else{status="正在定位，请稍后再点一次";LocationService.shared.refresh();return}
        let request=AMapPOIAroundSearchRequest()
        request.location=AMapGeoPoint.location(withLatitude:CGFloat(center.0),longitude:CGFloat(center.1))
        request.keywords="加油站";request.types="010100";request.sortrule=0;request.radius=10000;request.offset=20
        activeSearch="fuel";fuelRequest=request;results=[];status="搜索附近加油站…"
        api?.aMapPOIAroundSearch(request)
    }

    @objc(onPOISearchDone:response:)
    func mnFuelDone(_ request:AMapPOISearchBaseRequest?,response:AMapPOISearchResponse?){
        guard request === fuelRequest,activeSearch=="fuel" else{return}
        results=(response?.pois ?? []).compactMap{poi -> Place? in
            guard let point=poi.location,MotorRequest.valid(Double(point.latitude),Double(point.longitude)) else{return nil}
            return Place(name:poi.name ?? "加油站",address:poi.address ?? "",lat:Double(point.latitude),lng:Double(point.longitude))
        }
        status=results.isEmpty ? "附近十公里未找到加油站，可输入名称搜索":"按距离显示附近加油站"
    }

    @objc(onInputTipsSearchDone:response:)
    func mnTipsDone(_ request: AMapInputTipsSearchRequest?, response: AMapInputTipsSearchResponse?) {
        let searchKey=(request?.keywords ?? "")+"|"+(request?.location ?? "")
        guard searchKey==activeSearch else{return}
        let tips = response?.tips ?? []
        results = tips.compactMap { (tip: AMapTip) -> Place? in
            guard let p = tip.location else { return nil }          // 没有坐标的是“搜索建议词”，跳过
            return Place(name: tip.name ?? "", address: (tip.district ?? "") + (tip.address ?? ""),
                         lat: Double(p.latitude), lng: Double(p.longitude))
        }
        cache[searchKey] = results
        status = results.isEmpty ? "没找到，换个说法试试" : ""
    }

    @objc(AMapSearchRequest:didFailWithError:)
    func mnSearchFail(_ request: Any?, error: NSError?) {
        let code = error?.code ?? 0
        let bid = Bundle.main.bundleIdentifier ?? ""
        switch code {
        case 1008, 1009:    // iOS v0.7.2 key 绑定的 Bundle ID / 平台和这个 App 对不上：说清楚去哪改
            status = "搜索失败（\(code)）：高德 key 和这个 App 对不上。去高德开放平台控制台，把这个 key 的服务平台设为「iOS 平台」、" +
                "安全码（Bundle ID）改成 \(bid)，保存后等一两分钟再搜"
        case 1002, 1013:
            status = "搜索失败（\(code)）：高德 key 不对或已经被删除，到「我的 → 通用 → 密钥设置」重新填一个"
        case 1004, 1010:
            status = "搜索失败（\(code)）：这个高德 key 今天的搜索次数用完了，明天再试或换一个 key"
        case 1003, 1012:
            status = "搜索失败（\(code)）：这个高德 key 没有搜索权限，到高德控制台检查这个 key 开通的服务"
        default:
            status = "搜索失败：\(error?.localizedDescription ?? "未知错误")（\(code)）"
        }
    }
}

/// iOS v0.4 最近去过（和安卓版一样：最多 12 个，同名且相距 50 米以内算同一个地方，存在手机上）
final class History: ObservableObject {
    static let shared = History()
    @Published private(set) var places: [SearchService.Place] = []
    private let key = "nav_history"

    private init() {
        let arr = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
        places = arr.compactMap { o in
            guard let n = o["n"] as? String, let la = o["la"] as? Double, let lo = o["lo"] as? Double else { return nil }
            return SearchService.Place(name: n, address: o["a"] as? String ?? "", lat: la, lng: lo)
        }
    }

    func add(_ p: SearchService.Place) {
        var list = [p]
        for o in places where !(o.name == p.name && NaviBridge.distM(o.lat, o.lng, p.lat, p.lng) < 50) {
            if list.count >= 12 { break }
            list.append(o)
        }
        places = list
        save()
    }

    func clear() { places = []; save() }

    private func save() {
        UserDefaults.standard.set(places.map { ["n": $0.name, "a": $0.address, "la": $0.lat, "lo": $0.lng] as [String: Any] }, forKey: key)
    }
}

/// 手机当前位置（搜索时优先附近、查天气、规划路线起点用）。导航中直接用高德导航的定位。
/// iOS v0.3 巡航模式时切成高精度、锁屏后台也继续定位，位置交给 NaviBridge（小地图、车速、测速牌）。
/// v1.3 起定位只有两档：需要时单次取点（requestLocation，答完即停）和导航/巡航时的连续定位。
/// 不再“一启动就一直定位”，灵动岛上的定位指示因此只在真正导航时出现。
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    private let lm = CLLocationManager()
    private let coarseFilter: CLLocationDistance = 30
    /// 单次取点能接受的精度上限（米）。高德算路起点用，太粗的位置会把起点甩出去几个路口
    private let coarseAccuracy: CLLocationAccuracy = 100
    @Published var location: CLLocation?

    /// 导航/巡航期间为 true；其余时间一律不连续定位
    private var navigating = false
    /// 正在等一次定位的调用方（规划、天气、自动规划可能同时等，统一排队，一起唤醒）
    private var waiters: [UUID: CheckedContinuation<CLLocation?, Never>] = [:]
    /// 授权弹窗还没回来，用户点了同意就补一次取点
    private var wantsFixAfterAuth = false

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
        lm.distanceFilter = coarseFilter
    }

    /// 已经拿到定位权限（没授权时 currentFix 会立刻返回 nil，提示文案要分开写）
    var isAuthorized: Bool {
        lm.authorizationStatus == .authorizedWhenInUse || lm.authorizationStatus == .authorizedAlways
    }

    /// 补一次位置（启动预热、搜索、天气用）。定位器答完即停，不会常驻。
    func refresh() {
        guard !navigating else { return }                     // 导航中已有连续定位
        switch lm.authorizationStatus {
        case .notDetermined:
            wantsFixAfterAuth = true
            lm.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestOnce()
        default:
            break
        }
    }

    /// 要一个“现在的位置”：够新就直接给；否则发一次单次定位并等，超时或没授权返回 nil。
    /// 调用方负责在这段等待期间显示加载态（规划、天气都这么用）。
    func currentFix(timeout: TimeInterval = 6, maxAge: TimeInterval = 15) async -> CLLocation? {
        if let fix = usable(location, maxAge: maxAge) { return fix }
        let auth = lm.authorizationStatus
        if auth == .denied || auth == .restricted { return nil }
        let id = UUID()
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            // 先挂号再开定位：反过来的话，回调可能落在挂号之前，这个等待者会白等到超时
            waiters[id] = cont
            if waiters.count == 1 {
                if auth == .notDetermined {
                    wantsFixAfterAuth = true
                    lm.requestWhenInUseAuthorization()
                } else if !navigating {
                    // 导航中不能调 requestLocation：它会掐断 startUpdatingLocation 的连续定位
                    requestOnce()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resolve(id, with: nil)                  // 只结束自己，别的等待者继续等
            }
        }
    }

    /// 导航/巡航开始：连续、高精度、锁屏也继续
    func beginNavigation() {
        guard !navigating else { return }
        navigating = true
        wantsFixAfterAuth = false
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.distanceFilter = kCLDistanceFilterNone
        lm.activityType = (WebMotorSession.shared.running && WebMotorSession.shared.route?.request.bicycle == true) ? .fitness : .automotiveNavigation
        lm.pausesLocationUpdatesAutomatically = false
        lm.allowsBackgroundLocationUpdates = true
        lm.startUpdatingLocation()
    }

    /// 导航/巡航结束：先撤后台资格再停，否则灵动岛的定位指示会残留
    func endNavigation() {
        guard navigating else { return }
        navigating = false
        lm.allowsBackgroundLocationUpdates = false
        lm.stopUpdatingLocation()
        lm.pausesLocationUpdatesAutomatically = true
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
        lm.distanceFilter = coarseFilter
        lm.activityType = .other
    }

    private func requestOnce() {
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
        lm.distanceFilter = coarseFilter
        lm.requestLocation()
    }

    private func usable(_ fix: CLLocation?, maxAge: TimeInterval) -> CLLocation? {
        guard let fix = fix, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= coarseAccuracy else { return nil }
        if maxAge > 0, -fix.timestamp.timeIntervalSinceNow > maxAge { return nil }
        return fix
    }

    /// 结束一个等待者。先摘掉再唤醒，超时和定位回调谁先到都不会重复 resume
    private func resolve(_ id: UUID, with fix: CLLocation?) {
        guard let cont = waiters.removeValue(forKey: id) else { return }
        cont.resume(returning: fix)
    }

    /// 定位到了，把这一批等待者一起放行
    private func resolveAll(_ fix: CLLocation?) {
        let all = waiters
        waiters = [:]
        all.values.forEach { $0.resume(returning: fix) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        location = l
        if usable(l, maxAge: 60) != nil { resolveAll(l) }       // 太粗的位置不给算路用，继续等下一次
        RideRecorder.shared.fix(l); WebMotorSession.shared.onFix(l)
        if NaviBridge.shared.cruising { NaviBridge.shared.onCruiseLocation(l) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 首次定位偶尔给一次 locationUnknown，iOS 自己还会再试；别的错误直接让等待方拿到 nil
        if (error as? CLError)?.code == .locationUnknown { return }
        resolveAll(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isAuthorized else { resolveAll(nil); wantsFixAfterAuth = false; return }
        if navigating { manager.startUpdatingLocation(); return }   // 只在导航期间续上
        if wantsFixAfterAuth { wantsFixAfterAuth = false; requestOnce() }
    }
}
