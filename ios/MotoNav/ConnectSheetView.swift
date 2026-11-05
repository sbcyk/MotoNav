import SwiftUI

/// 手动连接卡片：小幅倾斜展示，不阻塞自动重连。
struct ConnectSheetView: View {
    @ObservedObject var coord = ConnectAnimationCoordinator.shared
    @ObservedObject var ble = BleLink.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.36).ignoresSafeArea().onTapGesture { }
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 44)
                    Text(coord.deviceTitle).font(.system(size: 20, weight: .semibold)).foregroundColor(AppTheme.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { coord.dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(AppTheme.sub)
                            .frame(width: 44, height: 44).background(Circle().fill(AppTheme.secondaryFill))
                    }
                    .buttonStyle(.plain).accessibilityLabel("关闭连接界面")
                }
                .padding(.horizontal, 16).padding(.top, 12)

                ConnectPuckSceneView(spinning: !reduceMotion && coord.phase == .spinning, spinSeconds: coord.spinSeconds)
                    .frame(width: 238, height: 238)

                if coord.showBattery {
                    HStack(spacing: 8) {
                        Image(systemName: "battery.50").font(.title3).foregroundColor(AppTheme.green)
                        Text(ble.screenBattery.map { "电量 \($0)%" } ?? "电量 —")
                            .font(.system(size: 26, weight: .semibold).monospacedDigit()).foregroundColor(AppTheme.text)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Text(coord.statusText).font(.system(size: 16, weight: .semibold))
                    .foregroundColor(coord.phase == .connected ? AppTheme.green : AppTheme.text)
                    .multilineTextAlignment(.center).padding(.top, 12).padding(.horizontal, 22)
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 10))
                    Text(coord.footerHint).font(.footnote.weight(.medium))
                }
                .foregroundColor(AppTheme.sub).padding(.top, 8)
                if coord.phase == .failed {
                    GlassButton(title: "重新连接", icon: "arrow.clockwise", style: .prominent) { coord.connectManually() }
                        .padding(.horizontal, 22).padding(.top, 18)
                }
            }
            .padding(.bottom, 22).frame(maxWidth: 390)
            .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(AppTheme.card).shadow(color: .black.opacity(0.24), radius: 24, y: 12))
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.28), value: coord.showBattery)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.28), value: coord.phase)
    }
}

/// 自动重连提示；关闭提示不会取消蓝牙连接。
struct ReconnectBanner: View {
    @ObservedObject private var coord = ConnectAnimationCoordinator.shared
    @ObservedObject private var ble = BleLink.shared
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(ble.isReady ? AppTheme.green : AppTheme.accent).frame(width: 9, height: 9)
            Text(ble.isReady ? "圆屏已连接" : coord.statusText).font(.footnote.weight(.semibold)).foregroundColor(AppTheme.text).lineLimit(1)
            Spacer(minLength: 4)
            Button { coord.dismissReconnectBanner() } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundColor(AppTheme.sub)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("关闭重连提示")
        }
        .padding(.leading, 16).padding(.trailing, 4).frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 18).fill(AppTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.stroke.opacity(0.35)))
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}
