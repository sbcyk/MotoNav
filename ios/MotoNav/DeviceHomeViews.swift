import SwiftUI

/// 设备 Tab：当前连接状态、产品正视图和两个屏幕设置入口。
struct DeviceConnectionCard<DisplayDest: View, SystemDest: View>: View {
    @ObservedObject var ble = BleLink.shared
    @ObservedObject private var connectAnim = ConnectAnimationCoordinator.shared
    @ViewBuilder var displayDestination: () -> DisplayDest
    @ViewBuilder var systemDestination: () -> SystemDest

    var body: some View {
        CardView {
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        deviceInfo
                        Spacer(minLength: 4)
                        deviceArtwork
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Spacer(minLength: 0); deviceArtwork; Spacer(minLength: 0) }
                        deviceInfo
                    }
                }
            } else {
                // iOS 15 没有 ViewThatFits，固定上下排布避免窄屏横向溢出。
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Spacer(minLength: 0); deviceArtwork; Spacer(minLength: 0) }
                    deviceInfo
                }
            }
            Divider().opacity(0.35)
            HStack(spacing: 0) {
                NavigationLink(destination: displayDestination()) { deviceQuickLinkLabel("屏幕显示", "sun.max") }.buttonStyle(.plain)
                Divider().frame(height: 30).opacity(0.35)
                NavigationLink(destination: systemDestination()) { deviceQuickLinkLabel("屏幕设置", "gearshape") }.buttonStyle(.plain)
            }
        }
    }

    private var deviceInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("圆屏").font(.footnote.weight(.medium)).foregroundColor(AppTheme.sub)
            Text(ble.screenName.isEmpty ? "MotoNav" : ble.screenName)
                .font(.system(size: 24, weight: .bold)).foregroundColor(AppTheme.text).lineLimit(2).minimumScaleFactor(0.8)
            HStack(spacing: 7) {
                Circle().fill(ble.isReady ? AppTheme.green : AppTheme.amber).frame(width: 9, height: 9)
                Text(ble.connectionSummary).font(.subheadline.weight(.medium))
                    .foregroundColor(ble.isReady ? AppTheme.green : AppTheme.sub).lineLimit(2)
            }
            HStack(spacing: 8) {
                BatteryGauge(percent: ble.screenBattery, charging: ble.screenCharging, width: 30, height: 15)
                Text(ble.screenBattery.map { "\($0)%" } ?? "电量未知")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundColor(AppTheme.sub)
            }
            GlassButton(title: ble.isReady ? "断开连接" : "连接圆屏", icon: ble.isReady ? "bolt.slash" : "bolt.fill", style: .tinted) {
                if ble.isReady { ble.disconnect() } else { connectAnim.connectManually() }
            }
            .padding(.top, 2)
        }
    }

    private var deviceArtwork: some View {
        ZStack(alignment: .bottom) {
            Image("GroundShadow").resizable().scaledToFit().frame(width: 120, height: 26).offset(y: 6).opacity(0.7)
            Image("DevicePuckHero").resizable().scaledToFit().frame(width: 120, height: 134)
        }
        .frame(width: 126, height: 146).accessibilityHidden(true)
    }

    private func deviceQuickLinkLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundColor(AppTheme.accent).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
    }
}
