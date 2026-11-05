import Foundation
import Combine

/// 手动连接展示产品卡；自动重连只显示非阻塞状态条。连接本身仍由 BleLink 决定。
final class ConnectAnimationCoordinator: ObservableObject {
    static let shared = ConnectAnimationCoordinator()

    enum Kind { case first, manual, auto }
    enum Phase { case idle, spinning, connected, failed }

    @Published var isPresented = false
    @Published var kind: Kind = .manual
    @Published var phase: Phase = .idle
    @Published var statusText = "正在连接圆屏…"
    @Published var showBattery = false
    @Published private(set) var showReconnectBanner = false

    let spinSeconds: TimeInterval = 0.75
    private var readyWatch: AnyCancellable?
    private var timeoutWork: DispatchWorkItem?
    private var finishWork: DispatchWorkItem?
    private var bannerWork: DispatchWorkItem?
    private var autoConnecting = false

    var deviceTitle: String {
        BleLink.shared.screenName.isEmpty ? "MotoNav" : BleLink.shared.screenName
    }

    var footerHint: String {
        switch kind {
        case .first: return "首次配对"
        case .manual: return "手动连接"
        case .auto: return "自动重连"
        }
    }

    var bannerText: String {
        if showReconnectBanner { return statusText }
        return BleLink.shared.isReady ? "圆屏已连接" : "圆屏未连接"
    }

    func connectManually() {
        kind = .manual
        presentAndConnect()
    }

    func connectAutomatically() {
        autoConnecting = true
        kind = .auto
        statusText = "正在重新连接圆屏…"
        showReconnectBanner = true
        BleLink.shared.connect()
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.autoConnecting else { return }
            self.autoConnecting = false
            self.showReconnectBanner = false
        }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func dismiss() {
        timeoutWork?.cancel()
        finishWork?.cancel()
        readyWatch?.cancel()
        readyWatch = nil
        isPresented = false
        phase = .idle
        showBattery = false
        statusText = "正在连接圆屏…"
    }

    func dismissReconnectBanner() {
        bannerWork?.cancel()
        autoConnecting = false
        showReconnectBanner = false
    }

    private func presentAndConnect() {
        dismissReconnectBanner()
        timeoutWork?.cancel()
        finishWork?.cancel()
        readyWatch?.cancel()
        isPresented = true
        phase = .spinning
        showBattery = false
        statusText = "正在连接圆屏…"
        BleLink.shared.connect()

        readyWatch = Publishers.CombineLatest(BleLink.shared.$isReady, BleLink.shared.$verified)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready, verified in
                guard let self, self.isPresented, ready, verified else { return }
                self.scheduleConnected()
            }
        if BleLink.shared.isReady && BleLink.shared.verified { scheduleConnected() }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.isPresented, self.phase != .connected else { return }
            self.phase = .failed
            self.statusText = "暂未连接，请确认圆屏已开机"
            self.showBattery = false
        }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    private func scheduleConnected() {
        finishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPresented, BleLink.shared.isReady, BleLink.shared.verified else { return }
            self.phase = .connected
            self.statusText = "已连接圆屏"
            self.showBattery = true
            self.timeoutWork?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                guard let self, self.isPresented, self.phase == .connected else { return }
                self.dismiss()
            }
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + spinSeconds, execute: work)
    }
}
