import Foundation
import SwiftUI

// MARK: - 选点

/// 起点 / 目的地 / 途经点共用的选点页。
/// 不用系统 List + 导航栏：整页是卡片列表，页眉和四周留白跟 App 其他页面一致。
struct RoutePointPicker: View {
    let title: String
    let near: MotorPoint?
    let choose: (MotorPoint)->Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title,
                        subtitle: "搜索地点，或从收藏与最近目的地中选择",
                        onClose: { dismiss() })
            PlacePickerContent(near: near) { point in
                choose(point)
                dismiss()
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .foregroundColor(AppTheme.text)
    }
}

/// 选点主体：搜索框 + 结果 / 收藏 / 最近目的地。
/// 单独拆出来是因为途经点编辑页要在同一个弹窗里原地切换，不能再叠一层 sheet。
private struct PlacePickerContent: View {
    let near: MotorPoint?
    let choose: (MotorPoint)->Void
    @StateObject private var search = SearchService()
    @ObservedObject private var favorites = Favorites.shared
    @ObservedObject private var history = History.shared
    @ObservedObject private var settings = Settings.shared
    @State private var query = ""
    @State private var debounce: DispatchWorkItem?
    @State private var programmaticQuery: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.sub)
                        .accessibilityHidden(true)
                    TextField("搜索地点、地址", text: $query)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .foregroundColor(AppTheme.text)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { runSearch() }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            search.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.sub.opacity(0.65))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 0)
                .frame(minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.sunken))
                .onChange(of: query) { text in schedule(text) }

                HStack(spacing: 8) {
                    GlassChip(title: "附近加油站", icon: "fuelpump", compact: true) {
                        focused = false
                        debounce?.cancel()
                        // query 改到「加油站」会触发 onChange，别让防抖再用文本搜索覆盖加油站 POI 结果
                        programmaticQuery = "加油站"
                        query = "加油站"
                        search.searchFuel(near: near.map { ($0.lat, $0.lng) })
                    }
                    if !favorites.places.isEmpty && !query.isEmpty {
                        GlassChip(title: "我的收藏", icon: "star", compact: true) {
                            query = ""
                            search.clear()
                        }
                    }
                    Spacer(minLength: 0)
                }

                if settings.keysMissing {
                    Label("没有高德密钥时只能从收藏和最近目的地里选。", systemImage: "key")
                        .font(.caption)
                        .foregroundColor(AppTheme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboardIfAvailable()
        }
        .onDisappear { debounce?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if !search.results.isEmpty {
            section("搜索结果") {
                ForEach(search.results) { place in row(place) }
            }
        } else {
            if !search.status.isEmpty {
                HStack(spacing: 8) {
                    if search.status.hasPrefix("搜索中") { ProgressView().controlSize(.small) }
                    Text(ContentView.userMessage(search.status))
                        .font(.footnote)
                        .foregroundColor(AppTheme.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if query.isEmpty {
                if !favorites.places.isEmpty {
                    section("收藏地点") {
                        ForEach(Array(favorites.places.prefix(8))) { place in row(place.searchPlace) }
                    }
                }
                if !history.places.isEmpty {
                    section("最近目的地") {
                        ForEach(Array(history.places.prefix(8))) { place in row(place) }
                    }
                }
                if favorites.places.isEmpty && history.places.isEmpty {
                    Label(settings.keysMissing
                          ? "没有高德密钥，暂时没有可选地点；先到「我的 → 通用 → 密钥设置」填写 Key。"
                          : "输入地点名称开始搜索。搜过的目的地也会出现在这里。",
                          systemImage: settings.keysMissing ? "key" : "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                }
            } else if !settings.keysMissing && search.status.isEmpty {
                Text("输入后自动搜索…")
                    .font(.footnote)
                    .foregroundColor(AppTheme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.sub)
            VStack(spacing: 8) { rows() }
        }
    }

    /// 一行地点：主体点了就选走，右侧星标负责收藏 / 取消收藏，点了立刻有反馈。
    private func row(_ place: SearchService.Place) -> some View {
        let saved = isFavorite(place)
        return HStack(spacing: 6) {
            Button {
                choose(MotorPoint(lat: place.lat, lng: place.lng, name: place.name))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppTheme.accentSoft))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !place.address.isEmpty {
                            Text(place.address)
                                .font(.caption)
                                .foregroundColor(AppTheme.sub)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if let distance = distanceText(place) {
                        Text(distance)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.accent)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(place)
            } label: {
                Image(systemName: saved ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(saved ? AppTheme.accent : AppTheme.sub)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved ? "取消收藏\(place.name)" : "收藏\(place.name)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.card))
    }

    private func isFavorite(_ place: SearchService.Place) -> Bool {
        favorites.places.contains { NaviBridge.distM($0.lat, $0.lng, place.lat, place.lng) < Favorites.samePlaceMeters }
    }

    private func toggleFavorite(_ place: SearchService.Place) {
        if let saved = favorites.places.first(where: {
            NaviBridge.distM($0.lat, $0.lng, place.lat, place.lng) < Favorites.samePlaceMeters
        }) {
            favorites.remove(saved)
        } else {
            favorites.add(place)
        }
    }

    private func distanceText(_ place: SearchService.Place) -> String? {
        guard let me = NaviBridge.shared.myPosition() else { return nil }
        return NaviBridge.distText(Int(NaviBridge.distM(me.lat, me.lng, place.lat, place.lng)))
    }

    /// 输入停下 0.4 秒再查一次，拼音输入不会每个字母都花一次高德额度。
    private func schedule(_ text: String) {
        debounce?.cancel()
        // 程序里改 query（加油站快捷入口）时不要当成用户输入再查一次
        if let pending = programmaticQuery {
            programmaticQuery = nil
            if pending == text { return }
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { search.clear(); return }
        guard !settings.keysMissing else { return }
        let work = DispatchWorkItem { search.search(value, near: near.map { ($0.lat, $0.lng) }) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func runSearch() {
        debounce?.cancel()
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { search.clear(); return }
        guard !settings.keysMissing else { return }
        search.search(value, near: near.map { ($0.lat, $0.lng) })
    }
}

// MARK: - 途经点

/// 途经点编辑：按顺序最多三个。选点在这里原地切换，不再从 sheet 里再弹一层 sheet。
struct RouteWaypointEditor: View {
    private struct Draft: Identifiable {
        let id = UUID()
        var point: MotorPoint
    }

    private enum PickerTarget: Identifiable {
        case new
        case item(UUID)

        var id: String {
            switch self {
            case .new: return "new"
            case .item(let id): return id.uuidString
            }
        }
    }

    let near: MotorPoint?
    let apply: ([MotorPoint])->Void
    @State private var draft: [Draft]
    @State private var target: PickerTarget?
    @Environment(\.dismiss) private var dismiss

    init(points: [MotorPoint], near: MotorPoint?, apply: @escaping ([MotorPoint])->Void) {
        self.near = near
        self.apply = apply
        _draft = State(initialValue: points.map { Draft(point: $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            if target == nil {
                SheetHeader(title: "途经点",
                            subtitle: "按顺序经过，最多三个",
                            actionTitle: "应用",
                            onClose: { dismiss() },
                            onAction: {
                                apply(draft.map(\.point))
                                dismiss()
                            })
            } else {
                SheetHeader(title: "选择途经点",
                            subtitle: "搜索地点，或从收藏与最近目的地中选择",
                            back: true,
                            onClose: { target = nil })
            }

            if let target {
                PlacePickerContent(near: near) { point in
                    switch target {
                    case .new:
                        if draft.count < 3 {
                            withAnimation(.easeOut(duration: 0.16)) { draft.append(Draft(point: point)) }
                        }
                    case .item(let id):
                        if let index = draft.firstIndex(where: { $0.id == id }) {
                            draft[index].point = point
                        }
                    }
                    self.target = nil
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if draft.isEmpty {
                            Label("还没有途经点。可以先去加油站、便利店，再继续前往目的地。",
                                  systemImage: "arrow.triangle.branch")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.sub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 18)
                        } else {
                            ForEach(Array(draft.enumerated()), id: \.element.id) { index, item in
                                row(index, item)
                            }
                        }
                        if draft.count < 3 {
                            addButton
                        }
                        Text("只有点「应用」才会改变路线；关闭或返回会保留原来的设置。")
                            .font(.caption)
                            .foregroundColor(AppTheme.sub)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .foregroundColor(AppTheme.text)
    }

    private func row(_ index: Int, _ item: Draft) -> some View {
        HStack(spacing: 6) {
            Button {
                target = .item(item.id)
            } label: {
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppTheme.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.point.name.isEmpty ? "选择地点" : item.point.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.text)
                            .lineLimit(1)
                        Text("第 \(index + 1) 个途经点")
                            .font(.caption2)
                            .foregroundColor(AppTheme.sub)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppTheme.stroke)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button { move(item.id, -1) } label: { Label("上移", systemImage: "arrow.up") }
                    .disabled(index == 0)
                Button { move(item.id, 1) } label: { Label("下移", systemImage: "arrow.down") }
                    .disabled(index == draft.count - 1)
                Divider()
                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.16)) { draft.removeAll { $0.id == item.id } }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.sub)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("管理第 \(index + 1) 个途经点")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.card))
    }

    private var addButton: some View {
        Button {
            target = .new
        } label: {
            Label("添加途经点", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.accent.opacity(0.45),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func move(_ id: UUID, _ delta: Int) {
        guard let index = draft.firstIndex(where: { $0.id == id }) else { return }
        let next = index + delta
        guard draft.indices.contains(next) else { return }
        withAnimation(.easeOut(duration: 0.16)) { draft.swapAt(index, next) }
    }
}

// MARK: - 路线历史

struct MotorHistoryView: View {
    let bicycle: Bool
    let choose: (SavedMotorPlan)->Void
    @ObservedObject private var history = MotorPlanHistory.shared
    @State private var confirmClear = false
    @Environment(\.dismiss) private var dismiss

    private var plans: [SavedMotorPlan] { history.plans.filter { $0.request.bicycle == bicycle } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: bicycle ? "自行车路线历史" : "路线历史",
                        subtitle: plans.isEmpty ? "成功规划的起终点和途经点会保存在这里" : "\(plans.count) 条已保存",
                        actionTitle: "清空",
                        actionEnabled: !plans.isEmpty,
                        onClose: { dismiss() },
                        onAction: { confirmClear = true })

            ScrollView {
                VStack(spacing: 10) {
                    if plans.isEmpty {
                        Label("还没有保存的路线。完成一次规划后，起终点和途经点会自动记录。",
                              systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(plans) { entry in row(entry) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .foregroundColor(AppTheme.text)
        .confirmationDialog("清空当前类型的路线历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空路线历史", role: .destructive) { history.clear(bicycle: bicycle) }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ entry: SavedMotorPlan) -> some View {
        HStack(spacing: 6) {
            Button {
                choose(entry)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(entry.request.start.name.isEmpty ? "起点" : entry.request.start.name) → \(entry.request.end.name.isEmpty ? "目的地" : entry.request.end.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Text(NaviBridge.durText(entry.seconds))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundColor(AppTheme.accent)
                    }
                    if !entry.request.vias.isEmpty {
                        Label(entry.request.vias.map(\.name).joined(separator: " → "),
                              systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundColor(AppTheme.sub)
                            .lineLimit(1)
                    }
                    Text("\(NaviBridge.distText(entry.distance)) · \(NaviBridge.durText(entry.seconds))")
                        .font(.caption)
                        .foregroundColor(AppTheme.sub)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(role: .destructive) { history.remove(entry.id) } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.sub)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("删除这条路线历史")
        }
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.card))
    }
}

private extension View {
    /// iOS 16 起滚动列表顺手收键盘；15 上保持原样。
    @ViewBuilder func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16.0, *) { scrollDismissesKeyboard(.interactively) } else { self }
    }
}
