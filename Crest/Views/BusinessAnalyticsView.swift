import Charts
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BusinessAnalyticsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var moduleSelection

    let onOpenSidebar: () -> Void
    let onOpenSettings: () -> Void

    private let api = APIClient()

    @State private var module: AnalyticsModule = .dashboard
    @State private var periodPreset: AnalyticsPeriodPreset = .currentMonth
    @State private var customPeriod: ClosedRange<Date>?
    @State private var selectedStoreKeys: Set<String> = []
    @State private var storeScopeNodes: [AnalyticsStoreScopeNode] = []
    @State private var storeScopeError: String?
    @State private var overview: AnalyticsOverview?
    @State private var revenueTrend: AnalyticsRevenueTrendResponse?
    @State private var products: AnalyticsProductsResponse?
    @State private var productTrend: AnalyticsProductTrendResponse?
    @State private var labor: AnalyticsLaborResponse?
    @State private var laborTrend: AnalyticsLaborResponse?
    @State private var alerts: [AnalyticsRevenueAlert]?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isFilterPresented = false
    @State private var selectedDetail: AnalyticsDetail?
    @State private var exportDocument: AnalyticsCSVDocument?
    @State private var isExporterPresented = false

    private var period: ClosedRange<Date> { customPeriod ?? periodPreset.range }
    private var dateFrom: String { AnalyticsDateFormat.api.string(from: period.lowerBound) }
    private var dateTo: String { AnalyticsDateFormat.api.string(from: period.upperBound) }
    private var trendPeriod: ClosedRange<Date> {
        let calendar = AnalyticsDateFormat.calendar
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        return start...end
    }
    private var trendDateFrom: String { AnalyticsDateFormat.api.string(from: trendPeriod.lowerBound) }
    private var trendDateTo: String { AnalyticsDateFormat.api.string(from: trendPeriod.upperBound) }
    private var storeKeys: [String] { selectedStoreKeys.sorted() }
    private var storeOptions: [AnalyticsStoreOption] {
        var seen: Set<String> = []
        return storeScopeNodes
            .flatMap(\.storeOptions)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    private var periodTitle: String { customPeriod == nil ? periodPreset.title : "自定义" }
    private var storeSummary: String {
        guard !selectedStoreKeys.isEmpty else { return "全部门店" }
        let labels = storeOptions.filter { selectedStoreKeys.contains($0.id) }.map(\.label)
        if labels.count == 1 { return labels[0] }
        return "\(labels.isEmpty ? selectedStoreKeys.count : labels.count) 家门店"
    }
    private var taskID: String {
        "\(session.activeWorkspaceID):\(module.rawValue):\(dateFrom):\(dateTo):\(storeKeys.joined(separator: ","))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            moduleTabs

            if session.tenantID == nil {
                personalWorkspaceState
            } else {
                analyticsContent
            }
        }
        .foregroundStyle(AppColors.primaryText)
        .background(AppColors.background.ignoresSafeArea())
        .task(id: taskID) {
            await loadSelectedModule()
        }
        .task(id: session.activeWorkspaceID) {
            await loadStoreScopes()
        }
        .onChange(of: session.activeWorkspaceID) { _, _ in
            selectedStoreKeys = []
            storeScopeNodes = []
            resetLoadedData()
        }
        .sheet(isPresented: $isFilterPresented) {
            AnalyticsFilterSheet(
                period: period,
                preset: customPeriod == nil ? periodPreset : nil,
                stores: storeOptions,
                selectedStoreKeys: selectedStoreKeys,
                storeError: storeScopeError
            ) { start, end, preset, keys in
                if let preset {
                    periodPreset = preset
                    customPeriod = nil
                } else {
                    customPeriod = start...end
                }
                selectedStoreKeys = keys
                resetLoadedData()
            }
        }
        .sheet(item: $selectedDetail) { detail in
            AnalyticsDetailView(detail: detail)
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Crest-\(module.title)-\(dateFrom)-\(dateTo).csv"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("经营分析")
                    .font(.headline.weight(.semibold))
                Text(module.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppColors.secondaryText)
            }

            HStack {
                SidebarOpenButton(action: onOpenSidebar)
                Spacer()
                if session.tenantID != nil {
                    Button(action: prepareExport) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .frame(width: 44, height: 44)
                    .disabled(selectedModuleHasNoData || isLoading)
                    .accessibilityLabel("导出当前经营分析")
                    .systemGlassCircleButton()

                    Button {
                        Task { await loadSelectedModule(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .frame(width: 44, height: 44)
                    .disabled(isLoading)
                    .accessibilityLabel("刷新经营分析")
                    .systemGlassCircleButton()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
    }

    private var moduleTabs: some View {
        HStack(spacing: 4) {
            ForEach(AnalyticsModule.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                        module = item
                        errorMessage = nil
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                        Text(item.title)
                            .font(.caption2.weight(module == item ? .semibold : .medium))
                    }
                    .foregroundStyle(module == item ? Color.white : AppColors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background {
                        if module == item {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(AppColors.chatSendButton)
                                .matchedGeometryEffect(id: "module-selection", in: moduleSelection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(module == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var analyticsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                periodControl

                if isLoading && selectedModuleHasNoData {
                    ProgressView("正在读取经营数据")
                        .tint(AppColors.secondaryText)
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if let errorMessage, selectedModuleHasNoData {
                    AnalyticsMessageState(
                        icon: "exclamationmark.triangle",
                        title: "暂时无法加载",
                        message: errorMessage,
                        actionTitle: "重新加载"
                    ) {
                        Task { await loadSelectedModule(forceRefresh: true) }
                    }
                } else {
                    selectedModuleContent
                        .id(module)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                )
                        )
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .refreshable {
            await loadSelectedModule(forceRefresh: true)
        }
    }

    private var periodControl: some View {
        Button {
            isFilterPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.chatSendButton)
                    .frame(width: 34, height: 34)
                    .background(AppColors.chatSendButton.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(AnalyticsDateFormat.display.string(from: period.lowerBound)) 至 \(AnalyticsDateFormat.display.string(from: period.upperBound))")
                        .font(.subheadline.weight(.medium))
                    Text("\(storeSummary) · 按日统计")
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }

                Spacer(minLength: 4)

                Text(periodTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.chatSendButton)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(AppColors.chatSendButton.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.tertiaryText)
            }
            .padding(10)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选经营分析")
    }

    @ViewBuilder
    private var selectedModuleContent: some View {
        switch module {
        case .dashboard:
            if let overview {
                AnalyticsDashboardContent(
                    overview: overview,
                    trend: revenueTrend,
                    onSelectChannel: { selectedDetail = .dimension($0, subtitle: "\(dateFrom) 至 \(dateTo)") }
                )
            }
        case .orders:
            if let overview {
                AnalyticsOrdersContent(
                    overview: overview,
                    trend: revenueTrend,
                    onSelectStore: { selectedDetail = .dimension($0, subtitle: "\(dateFrom) 至 \(dateTo)") }
                )
            }
        case .products:
            if let products {
                AnalyticsProductsContent(
                    response: products,
                    trend: productTrend,
                    onSelectProduct: { selectedDetail = .product($0, subtitle: "\(dateFrom) 至 \(dateTo)") }
                )
            }
        case .labor:
            if let labor {
                AnalyticsLaborContent(
                    response: labor,
                    trend: laborTrend,
                    onSelectPoint: { selectedDetail = .labor($0) }
                )
            }
        case .alerts:
            if let alerts {
                let visibleAlerts = selectedStoreKeys.isEmpty
                    ? alerts
                    : alerts.filter { selectedStoreKeys.contains($0.shopKey) }
                AnalyticsAlertsContent(
                    alerts: visibleAlerts,
                    businessDate: dateTo,
                    onSelectAlert: { selectedDetail = .alert($0) }
                )
            }
        }
    }

    private var personalWorkspaceState: some View {
        AnalyticsMessageState(
            icon: "building.2",
            title: "切换到团队工作空间",
            message: "经营分析只读取当前团队的门店、订单和人效数据，个人空间不会访问任何租户数据。",
            actionTitle: "选择工作空间",
            action: onOpenSettings
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var selectedModuleHasNoData: Bool {
        switch module {
        case .dashboard, .orders: overview == nil
        case .products: products == nil
        case .labor: labor == nil
        case .alerts: alerts == nil
        }
    }

    private func loadSelectedModule(forceRefresh: Bool = false) async {
        guard session.tenantID != nil else { return }
        if !forceRefresh && !selectedModuleHasNoData { return }

        let workspaceID = session.activeWorkspaceID
        isLoading = true
        errorMessage = nil
        defer {
            if workspaceID == session.activeWorkspaceID { isLoading = false }
        }

        do {
            switch module {
            case .dashboard, .orders:
                let value = try await withAnalyticsSession { token, identity in
                    try await api.analyticsOverview(
                        dateFrom: dateFrom,
                        dateTo: dateTo,
                        storeKeys: storeKeys,
                        refresh: forceRefresh,
                        accessToken: token,
                        cacheIdentity: identity
                    )
                }
                guard workspaceID == session.activeWorkspaceID else { return }
                overview = value
                revenueTrend = try await withAnalyticsSession { token, identity in
                    try await api.analyticsRevenueTrend(
                        dateFrom: trendDateFrom,
                        dateTo: trendDateTo,
                        storeKeys: storeKeys,
                        refresh: forceRefresh,
                        accessToken: token,
                        cacheIdentity: identity
                    )
                }
            case .products:
                let value = try await withAnalyticsSession { token, identity in
                    try await api.analyticsProducts(
                        dateFrom: dateFrom,
                        dateTo: dateTo,
                        storeKeys: storeKeys,
                        refresh: forceRefresh,
                        accessToken: token,
                        cacheIdentity: identity
                    )
                }
                guard workspaceID == session.activeWorkspaceID else { return }
                products = value
                let recentProducts = try await withAnalyticsSession { token, identity in
                    try await api.analyticsProducts(
                        dateFrom: trendDateFrom,
                        dateTo: trendDateTo,
                        storeKeys: storeKeys,
                        refresh: forceRefresh,
                        accessToken: token,
                        cacheIdentity: identity
                    )
                }
                if let product = recentProducts.items.first {
                    productTrend = try await withAnalyticsSession { token, identity in
                        try await api.analyticsProductTrend(
                            productKey: product.productKey,
                            dateFrom: trendDateFrom,
                            dateTo: trendDateTo,
                            storeKeys: storeKeys,
                            refresh: forceRefresh,
                            accessToken: token,
                            cacheIdentity: identity
                        )
                    }
                }
            case .labor:
                let value = try await withAnalyticsSession { token, identity in
                    try await api.analyticsLabor(
                        dateFrom: dateFrom,
                        dateTo: dateTo,
                        storeKeys: storeKeys,
                        refresh: forceRefresh,
                        accessToken: token,
                        cacheIdentity: identity
                    )
                }
                guard workspaceID == session.activeWorkspaceID else { return }
                labor = value
                laborTrend = try await withAnalyticsSession { token, identity in
                    try await api.analyticsLabor(
                        dateFrom: trendDateFrom,
                        dateTo: trendDateTo,
                        storeKeys: storeKeys,
                        refresh: forceRefresh,
                        accessToken: token,
                        cacheIdentity: identity
                    )
                }
            case .alerts:
                let value = try await withAnalyticsSession { token, identity in
                    try await api.analyticsRevenueAlerts(
                        businessDate: dateTo,
                        refresh: forceRefresh,
                        accessToken: token,
                        cacheIdentity: identity
                    )
                }
                guard workspaceID == session.activeWorkspaceID else { return }
                alerts = value
            }
        } catch is CancellationError {
            return
        } catch {
            guard workspaceID == session.activeWorkspaceID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadStoreScopes() async {
        guard session.tenantID != nil else { return }
        let workspaceID = session.activeWorkspaceID
        do {
            let response = try await withAnalyticsSession { token, identity in
                try await api.analyticsStoreScope(
                    accessToken: token,
                    cacheIdentity: identity
                )
            }
            guard workspaceID == session.activeWorkspaceID else { return }
            storeScopeNodes = response.nodes
            storeScopeError = nil
        } catch {
            guard workspaceID == session.activeWorkspaceID else { return }
            storeScopeError = error.localizedDescription
        }
    }

    private func withAnalyticsSession<Result>(
        _ operation: (String, AnalyticsCacheIdentity) async throws -> Result
    ) async throws -> Result {
#if DEBUG
        do {
            let context = try await AnalyticsOnlineSession.shared.validContext()
            return try await operation(context.accessToken, context.cacheIdentity)
        } catch is AnalyticsAPIError {
            AnalyticsOnlineSession.shared.invalidateAccessToken()
            let context = try await AnalyticsOnlineSession.shared.validContext()
            return try await operation(context.accessToken, context.cacheIdentity)
        }
#else
        guard let identity = AnalyticsCacheIdentity(
            userID: session.userID,
            workspaceID: session.activeWorkspaceID
        ) else {
            throw APIError.invalidSession
        }
        return try await session.withAuthenticatedSession { token in
            do {
                return try await operation(token, identity)
            } catch let error as AnalyticsAPIError {
                throw APIError.unauthorized(error.localizedDescription)
            }
        }
#endif
    }

    private func resetLoadedData() {
        overview = nil
        revenueTrend = nil
        products = nil
        productTrend = nil
        labor = nil
        laborTrend = nil
        alerts = nil
        errorMessage = nil
    }

    private func prepareExport() {
        guard let document = makeExportDocument() else { return }
        exportDocument = document
        isExporterPresented = true
    }

    private func makeExportDocument() -> AnalyticsCSVDocument? {
        var rows = [
            ["模块", module.title],
            ["日期范围", dateFrom, dateTo],
            ["门店范围", storeSummary],
            [],
        ]

        switch module {
        case .dashboard, .orders:
            guard let overview else { return nil }
            rows.append(["门店", "订单数", "净实收", "客单价"])
            rows += overview.stores.map {
                [$0.label, $0.csvValue("order_count"), $0.csvValue("net_income"), $0.csvValue("avg_order_value")]
            }
            rows.append([])
            rows.append(["渠道", "订单数", "净实收", "客单价"])
            rows += overview.channels.map {
                [$0.label, $0.csvValue("order_count"), $0.csvValue("net_income"), $0.csvValue("avg_order_value")]
            }
        case .products:
            guard let products else { return nil }
            rows.append(["产品", "销量", "销售额", "订单数", "数量占比", "销售额占比"])
            rows += products.items.map {
                [
                    $0.productName,
                    AnalyticsCSV.number($0.quantity),
                    AnalyticsCSV.number($0.salesAmount),
                    AnalyticsCSV.number($0.orderCount),
                    AnalyticsCSV.number($0.quantityShare),
                    AnalyticsCSV.number($0.amountShare),
                ]
            }
        case .labor:
            guard let labor else { return nil }
            rows.append(["日期", "实际工时", "计划工时", "净营收", "人数", "实际小时产出", "计划小时产出"])
            rows += labor.points.map {
                [
                    $0.period,
                    AnalyticsCSV.number($0.actualHours),
                    AnalyticsCSV.number($0.plannedHours),
                    AnalyticsCSV.number($0.netRevenue),
                    AnalyticsCSV.number($0.headcount),
                    AnalyticsCSV.number($0.actualRevenuePerHour),
                    AnalyticsCSV.number($0.plannedRevenuePerHour),
                ]
            }
        case .alerts:
            guard let alerts else { return nil }
            let visibleAlerts = selectedStoreKeys.isEmpty
                ? alerts
                : alerts.filter { selectedStoreKeys.contains($0.shopKey) }
            rows.append(["日期", "门店", "实际营收", "基准营收", "偏离率", "方向", "状态", "原因提示"])
            rows += visibleAlerts.map {
                [
                    $0.businessDate,
                    $0.shopLabel ?? $0.shopKey,
                    AnalyticsCSV.number($0.actualAmount),
                    AnalyticsCSV.number($0.baselineAmount),
                    AnalyticsCSV.number($0.deviationPercent),
                    $0.direction,
                    $0.status,
                    ($0.reasonHints ?? []).joined(separator: "；"),
                ]
            }
        }
        return AnalyticsCSVDocument(rows: rows)
    }
}

private enum AnalyticsModule: String, CaseIterable, Identifiable {
    case dashboard
    case orders
    case products
    case labor
    case alerts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "看板"
        case .orders: "订单"
        case .products: "产品"
        case .labor: "人效"
        case .alerts: "报警"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .orders: "list.bullet.clipboard"
        case .products: "takeoutbag.and.cup.and.straw"
        case .labor: "person.2"
        case .alerts: "bell.badge"
        }
    }
}

private enum AnalyticsPeriodPreset: String, CaseIterable, Identifiable {
    case yesterday
    case lastSevenDays
    case currentMonth
    case previousMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yesterday: "昨日"
        case .lastSevenDays: "近 7 天"
        case .currentMonth: "本月"
        case .previousMonth: "上月"
        }
    }

    var range: ClosedRange<Date> {
        let calendar = AnalyticsDateFormat.calendar
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        switch self {
        case .yesterday:
            return end...end
        case .lastSevenDays:
            return (calendar.date(byAdding: .day, value: -6, to: end) ?? end)...end
        case .currentMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end
            return start...end
        case .previousMonth:
            let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end
            let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
            return previousStart...previousEnd
        }
    }
}

private enum AnalyticsDateFormat {
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return value
    }()

    static let api: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

private struct AnalyticsStoreOption: Identifiable, Hashable {
    let id: String
    let label: String
}

private extension AnalyticsStoreScopeNode {
    var storeOptions: [AnalyticsStoreOption] {
        let current = storeKey.map { [AnalyticsStoreOption(id: $0, label: label)] } ?? []
        return current + (children ?? []).flatMap(\.storeOptions)
    }
}

private struct AnalyticsFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let stores: [AnalyticsStoreOption]
    let storeError: String?
    let onApply: (Date, Date, AnalyticsPeriodPreset?, Set<String>) -> Void

    @State private var draftStart: Date
    @State private var draftEnd: Date
    @State private var draftPreset: AnalyticsPeriodPreset?
    @State private var draftStoreKeys: Set<String>

    private var latestDate: Date {
        let calendar = AnalyticsDateFormat.calendar
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    private var canApply: Bool { draftStart <= draftEnd }

    init(
        period: ClosedRange<Date>,
        preset: AnalyticsPeriodPreset?,
        stores: [AnalyticsStoreOption],
        selectedStoreKeys: Set<String>,
        storeError: String?,
        onApply: @escaping (Date, Date, AnalyticsPeriodPreset?, Set<String>) -> Void
    ) {
        self.stores = stores
        self.storeError = storeError
        self.onApply = onApply
        _draftStart = State(initialValue: period.lowerBound)
        _draftEnd = State(initialValue: period.upperBound)
        _draftPreset = State(initialValue: preset)
        _draftStoreKeys = State(initialValue: selectedStoreKeys)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("快捷日期") {
                    ForEach(AnalyticsPeriodPreset.allCases) { preset in
                        Button {
                            draftPreset = preset
                            draftStart = preset.range.lowerBound
                            draftEnd = preset.range.upperBound
                        } label: {
                            selectionRow(title: preset.title, isSelected: draftPreset == preset)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("自定义日期") {
                    DatePicker(
                        "开始日期",
                        selection: Binding(
                            get: { draftStart },
                            set: { draftStart = $0; draftPreset = nil }
                        ),
                        in: ...latestDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "结束日期",
                        selection: Binding(
                            get: { draftEnd },
                            set: { draftEnd = $0; draftPreset = nil }
                        ),
                        in: ...latestDate,
                        displayedComponents: .date
                    )
                    if !canApply {
                        Text("结束日期不能早于开始日期")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("门店") {
                    Button {
                        draftStoreKeys = []
                    } label: {
                        selectionRow(title: "全部门店", isSelected: draftStoreKeys.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(stores) { store in
                        Button {
                            if draftStoreKeys.contains(store.id) {
                                draftStoreKeys.remove(store.id)
                            } else {
                                draftStoreKeys.insert(store.id)
                            }
                        } label: {
                            selectionRow(title: store.label, isSelected: draftStoreKeys.contains(store.id))
                        }
                        .buttonStyle(.plain)
                    }

                    if stores.isEmpty {
                        Text(storeError ?? "暂未读取到可选门店")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("取消")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(draftStart, draftEnd, draftPreset, draftStoreKeys)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canApply ? AppColors.chatSendButton : AppColors.tertiaryText)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(!canApply)
                    .accessibilityLabel("应用筛选")
                }
            }
        }
    }

    private func selectionRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(AppColors.primaryText)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.chatSendButton)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AnalyticsDashboardContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct TrendChartPoint: Identifiable {
        let period: String
        let date: Date
        let netIncome: Double
        let orderCount: Double

        var id: String { period }
    }

    @State private var selectedDate: Date?
    @State private var isTrendFullScreenPresented = false

    let overview: AnalyticsOverview
    let trend: AnalyticsRevenueTrendResponse?
    let onSelectChannel: (AnalyticsDimensionRow) -> Void

    private var trendPoints: [AnalyticsRevenueTrendPoint] {
        trend?.points.filter { $0.missing != true } ?? []
    }

    private var trendChartPoints: [TrendChartPoint] {
        trendPoints.compactMap { point in
            guard let date = AnalyticsDateFormat.api.date(from: point.period) else { return nil }
            return TrendChartPoint(
                period: point.period,
                date: date,
                netIncome: point.netIncome,
                orderCount: point.orderCount
            )
        }
    }

    private var trendYDomain: ClosedRange<Double> {
        guard
            let minimum = trendChartPoints.map(\.netIncome).min(),
            let maximum = trendChartPoints.map(\.netIncome).max()
        else {
            return 0...1
        }

        let fallbackSpread = max(abs(maximum) * 0.08, 1)
        let spread = max(maximum - minimum, fallbackSpread)
        let padding = spread * 0.18
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var latestTrendPointID: String? {
        trendChartPoints.last?.id
    }

    private var selectedTrendPoint: TrendChartPoint? {
        guard let selectedDate else { return nil }
        return trendChartPoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var trendChangeRate: Double? {
        guard
            let first = trendChartPoints.first?.netIncome,
            let last = trendChartPoints.last?.netIncome,
            first != 0
        else { return nil }
        return (last - first) / abs(first)
    }

    var body: some View {
        AnalyticsPageTitle(title: "经营看板", subtitle: "当前周期与上期经营表现")
            .analyticsEntrance(order: 0)
        AnalyticsKPIGrid(metrics: overview.metrics, compact: true)
            .analyticsEntrance(order: 1)

        AnalyticsSection(
            title: "营收趋势",
            subtitle: "最近30天 · 按日净实收",
            onExpand: { isTrendFullScreenPresented = true }
        ) {
            if trendChartPoints.isEmpty {
                AnalyticsEmptyText(text: "最近30天暂无营收趋势数据")
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compactCurrency(trendChartPoints.last?.netIncome ?? 0))
                            .font(.title2.weight(.bold))
                            .contentTransition(.numericText())
                        Text("最新净实收")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Spacer()
                    if let trendChangeRate {
                        Label(
                            AnalyticsValue.signedPercent(trendChangeRate),
                            systemImage: trendChangeRate >= 0 ? "arrow.up.right" : "arrow.down.right"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendChangeRate >= 0 ? Color.green : Color.red)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            (trendChangeRate >= 0 ? Color.green : Color.red).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                }
                trendChart.frame(height: 220)
            }
        }
        .analyticsEntrance(order: 2)
        .fullScreenCover(isPresented: $isTrendFullScreenPresented) {
            fullScreenTrendView
        }

        AnalyticsSection(title: "渠道表现") {
            if overview.channels.isEmpty {
                AnalyticsEmptyText(text: "当前周期暂无渠道数据")
            } else {
                ForEach(overview.channels) { channel in
                    Button { onSelectChannel(channel) } label: {
                        AnalyticsDetailLinkRow(
                            title: channel.label,
                            primary: AnalyticsValue.currency(channel.value("net_income")),
                            secondary: "\(AnalyticsValue.count(channel.value("order_count"))) 单"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .analyticsEntrance(order: 3)
    }

    private var fullScreenTrendView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("最近30天 · 按日净实收")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                trendChart
            }
            .padding(16)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("营收趋势")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        updateTrendOrientation(.portrait)
                        isTrendFullScreenPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("关闭全屏")
                }
            }
        }
        .foregroundStyle(AppColors.primaryText)
        .onAppear {
            updateTrendOrientation(.landscape)
        }
        .onDisappear {
            updateTrendOrientation(.portrait)
        }
    }

    @MainActor
    private func updateTrendOrientation(_ orientations: UIInterfaceOrientationMask) {
        AppOrientation.update(orientations)
    }

    private var trendChart: some View {
        GeometryReader { geometry in
            Chart {
                ForEach(trendChartPoints) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        yStart: .value("范围下限", trendYDomain.lowerBound),
                        yEnd: .value("净实收", point.netIncome)
                    )
                    .foregroundStyle(AppColors.chatSendButton.opacity(0.10))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("净实收", point.netIncome)
                    )
                    .foregroundStyle(AppColors.chatSendButton)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    if point.id == latestTrendPointID, point.id != selectedTrendPoint?.id {
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("净实收", point.netIncome)
                        )
                        .foregroundStyle(AppColors.chatSendButton)
                        .symbolSize(42)
                    }
                }

                if let selectedPoint = selectedTrendPoint {
                    RuleMark(x: .value("选中日期", selectedPoint.date))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.55))

                    PointMark(
                        x: .value("选中日期", selectedPoint.date),
                        y: .value("选中净实收", selectedPoint.netIncome)
                    )
                    .foregroundStyle(AppColors.chatSendButton)
                    .symbolSize(58)
                    .annotation(
                        position: selectedPoint.netIncome > (trendYDomain.lowerBound + trendYDomain.upperBound) / 2
                            ? .bottom
                            : .top,
                        alignment: tooltipAlignment(for: selectedPoint),
                        spacing: 8
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedPoint.date, format: .dateTime.month().day())
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                            Text(compactCurrency(selectedPoint.netIncome))
                                .font(.caption.weight(.bold))
                            Text("\(AnalyticsValue.count(selectedPoint.orderCount)) 单")
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    }
                }
            }
            .chartXScale(range: .plotDimension(padding: 6))
            .chartYScale(domain: trendYDomain)
            .chartXAxis {
                AxisMarks(values: xAxisDates(for: geometry.size.width)) { value in
                    AxisTick().foregroundStyle(AppColors.border)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(AppColors.border)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactCurrency(amount))
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { overlayGeometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = overlayGeometry[plotFrame]
                                    guard
                                        frame.contains(value.location),
                                        let date: Date = proxy.value(
                                            atX: value.location.x - frame.minX
                                        )
                                    else {
                                        return
                                    }
                                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                                        selectedDate = date
                                    }
                                }
                        )
                }
            }
            .accessibilityLabel("按日净实收趋势")
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.65),
                value: trendChartPoints.map(\.id)
            )
        }
    }

    private func tooltipAlignment(for point: TrendChartPoint) -> Alignment {
        guard let index = trendChartPoints.firstIndex(where: { $0.id == point.id }) else { return .center }
        if index < trendChartPoints.count / 3 { return .leading }
        if index >= trendChartPoints.count * 2 / 3 { return .trailing }
        return .center
    }

    private func xAxisDates(for width: CGFloat) -> [Date] {
        guard !trendChartPoints.isEmpty else { return [] }
        let labelCount = min(trendChartPoints.count, min(8, max(2, Int(width / 68))))
        guard labelCount > 1 else { return [trendChartPoints[0].date] }

        let lastIndex = trendChartPoints.count - 1
        return (0..<labelCount).map { labelIndex in
            let position = Double(labelIndex) * Double(lastIndex) / Double(labelCount - 1)
            return trendChartPoints[Int(position.rounded())].date
        }
    }

    private func compactCurrency(_ value: Double) -> String {
        if abs(value) >= 10_000 {
            let amount = value / 10_000
            if abs(amount) >= 10 {
                return "¥\(amount.formatted(.number.precision(.fractionLength(0))))万"
            }
            return "¥\(amount.formatted(.number.precision(.fractionLength(1))))万"
        }
        if abs(value) >= 1_000 {
            return "¥\((value / 1_000).formatted(.number.precision(.fractionLength(0))))k"
        }
        return "¥\(value.formatted(.number.precision(.fractionLength(0))))"
    }
}

private struct AnalyticsOrdersContent: View {
    @State private var selectedPeriod: String?
    @State private var isTrendFullScreenPresented = false

    let overview: AnalyticsOverview
    let trend: AnalyticsRevenueTrendResponse?
    let onSelectStore: (AnalyticsDimensionRow) -> Void

    private var stores: [AnalyticsDimensionRow] {
        overview.stores.sorted { $0.value("order_count") > $1.value("order_count") }
    }

    private var trendPoints: [AnalyticsRevenueTrendPoint] {
        trend?.points.filter { $0.missing != true } ?? []
    }

    private var trendOrderTotal: Double {
        trendPoints.reduce(0) { $0 + $1.orderCount }
    }

    private var averageDailyOrders: Double {
        guard !trendPoints.isEmpty else { return 0 }
        return trendOrderTotal / Double(trendPoints.count)
    }

    private var selectedPoint: AnalyticsRevenueTrendPoint? {
        guard let selectedPeriod else { return nil }
        return trendPoints.first { $0.period == selectedPeriod }
    }

    private var maxStoreOrders: Double {
        max(stores.map { $0.value("order_count") }.max() ?? 0, 1)
    }

    var body: some View {
        AnalyticsPageTitle(title: "订单统计", subtitle: "全部门店订单与实收概览")
            .analyticsEntrance(order: 0)
        AnalyticsKPIGrid(metrics: overview.metrics, compact: true)
            .analyticsEntrance(order: 1)

        AnalyticsSection(
            title: "订单趋势",
            subtitle: "最近30天 · 按日订单量",
            onExpand: { isTrendFullScreenPresented = true }
        ) {
            if trendPoints.isEmpty {
                AnalyticsEmptyText(text: "最近30天暂无订单趋势数据")
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AnalyticsValue.count(averageDailyOrders))
                            .font(.title2.weight(.bold))
                        Text("日均订单")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Spacer()
                    Text("共 \(AnalyticsValue.count(trendOrderTotal)) 单")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.chatSendButton)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(AppColors.chatSendButton.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                }

                orderTrendChart.frame(height: 210)
            }
        }
        .analyticsEntrance(order: 2)
        .fullScreenCover(isPresented: $isTrendFullScreenPresented) {
            AnalyticsChartFullScreen(
                title: "订单趋势",
                subtitle: "最近30天 · 按日订单量"
            ) {
                orderTrendChart
            }
        }

        AnalyticsSection(title: "门店订单", subtitle: "按订单量排序") {
            if stores.isEmpty {
                AnalyticsEmptyText(text: "当前周期暂无订单数据")
            } else {
                ForEach(Array(stores.enumerated()), id: \.element.id) { index, store in
                    Button { onSelectStore(store) } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(index < 3 ? Color.white : AppColors.secondaryText)
                                .frame(width: 26, height: 26)
                                .background(
                                    index < 3 ? AppColors.chatSendButton : AppColors.background,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )

                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(store.label)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(AnalyticsValue.count(store.value("order_count"))) 单")
                                        .font(.subheadline.weight(.semibold))
                                }

                                ProgressView(value: store.value("order_count"), total: maxStoreOrders)
                                    .tint(index < 3 ? AppColors.chatSendButton : AppColors.tertiaryText)
                                    .scaleEffect(y: 0.65)

                                HStack {
                                    Text("净实收 \(AnalyticsValue.currency(store.value("net_income")))")
                                    Spacer()
                                    Text("客单价 \(AnalyticsValue.currency(store.value("avg_order_value")))")
                                }
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.tertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .analyticsEntrance(order: 3)
    }

    private var orderTrendChart: some View {
        GeometryReader { geometry in
            Chart {
                ForEach(trendPoints) { point in
                    BarMark(
                        x: .value("日期", point.period),
                        y: .value("订单", point.orderCount)
                    )
                    .foregroundStyle(
                        point.id == selectedPoint?.id
                            ? AppColors.chatSendButton
                            : AppColors.chatSendButton.opacity(0.72)
                    )
                    .cornerRadius(3)
                }

                if let selectedPoint {
                    RuleMark(x: .value("选中日期", selectedPoint.period))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.55))
                    PointMark(
                        x: .value("选中日期", selectedPoint.period),
                        y: .value("选中订单", selectedPoint.orderCount)
                    )
                    .foregroundStyle(AppColors.chatSendButton)
                    .symbolSize(58)
                    .annotation(position: .top, spacing: 8) {
                        AnalyticsChartTooltip(
                            title: AnalyticsChartAxis.shortLabel(selectedPoint.period),
                            rows: [
                                "\(AnalyticsValue.count(selectedPoint.orderCount)) 单",
                                "净实收 \(AnalyticsValue.currency(selectedPoint.netIncome))"
                            ]
                        )
                    }
                }
            }
            .analyticsChartTapSelection(axis: .x, selection: $selectedPeriod)
            .chartXAxis {
                AxisMarks(values: AnalyticsChartAxis.values(
                    from: trendPoints.map(\.period),
                    width: geometry.size.width
                )) { value in
                    AxisTick().foregroundStyle(AppColors.border)
                    AxisValueLabel {
                        if let period = value.as(String.self) {
                            Text(AnalyticsChartAxis.shortLabel(period))
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(AppColors.border)
                    AxisValueLabel()
                }
            }
            .accessibilityLabel("最近30天按日订单趋势")
            .accessibilityHint("点按图表查看每日订单详情")
        }
    }
}

private struct AnalyticsProductsContent: View {
    @State private var selectedPeriod: String?
    @State private var isTrendFullScreenPresented = false

    let response: AnalyticsProductsResponse
    let trend: AnalyticsProductTrendResponse?
    let onSelectProduct: (AnalyticsProduct) -> Void

    private var trendPoints: [AnalyticsProductTrendPoint] {
        trend?.points.filter { $0.missing != true } ?? []
    }

    private var totalSales: Double {
        response.items.reduce(0) { $0 + $1.salesAmount }
    }

    private var totalQuantity: Double {
        response.items.reduce(0) { $0 + $1.quantity }
    }

    private var maxProductSales: Double {
        max(response.items.map(\.salesAmount).max() ?? 0, 1)
    }

    private var selectedPoint: AnalyticsProductTrendPoint? {
        guard let selectedPeriod else { return nil }
        return trendPoints.first { $0.period == selectedPeriod }
    }

    private var trendSubtitle: String {
        guard let productName = trend?.productName else {
            return "最近30天"
        }
        return "最近30天 · \(productName)"
    }

    private var productSnapshot: [AnalyticsSnapshotItem] {
        [
            AnalyticsSnapshotItem(
                label: "榜单销售额",
                value: AnalyticsValue.currency(totalSales),
                detail: "当前榜单合计",
                systemImage: "yensign.circle"
            ),
            AnalyticsSnapshotItem(
                label: "商品数",
                value: AnalyticsValue.count(Double(response.total)),
                detail: "参与销售商品",
                systemImage: "shippingbox"
            ),
            AnalyticsSnapshotItem(
                label: "总销量",
                value: AnalyticsValue.count(totalQuantity),
                detail: "当前榜单合计",
                systemImage: "cart"
            )
        ]
    }

    var body: some View {
        AnalyticsPageTitle(title: "产品分析", subtitle: "按商品销售额排名，共 \(response.total) 项")
            .analyticsEntrance(order: 0)

        AnalyticsSnapshotGrid(items: productSnapshot, columns: 3)
            .analyticsEntrance(order: 1)

        AnalyticsSection(
            title: "产品销售趋势",
            subtitle: trendSubtitle,
            onExpand: { isTrendFullScreenPresented = true }
        ) {
            if trendPoints.isEmpty {
                AnalyticsEmptyText(text: "最近30天暂无产品趋势数据")
            } else {
                if let latest = trendPoints.last {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AnalyticsValue.currency(latest.salesAmount))
                                .font(.title2.weight(.bold))
                            Text("最新销售额")
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        Spacer()
                        Text("销量 \(AnalyticsValue.count(latest.quantity))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.chatSendButton)
                    }
                }

                productTrendChart.frame(height: 210)
            }
        }
        .analyticsEntrance(order: 2)
        .fullScreenCover(isPresented: $isTrendFullScreenPresented) {
            AnalyticsChartFullScreen(title: "产品销售趋势", subtitle: trendSubtitle) {
                productTrendChart
            }
        }

        AnalyticsSection(title: "销售排行", subtitle: "商品销额不等同于财务净实收") {
            if response.items.isEmpty {
                AnalyticsEmptyText(text: "当前周期暂无产品销售数据")
            } else {
                ForEach(Array(response.items.enumerated()), id: \.element.id) { index, item in
                    Button { onSelectProduct(item) } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(index < 3 ? Color.white : AppColors.secondaryText)
                                .frame(width: 26, height: 26)
                                .background(
                                    index < 3 ? AppColors.chatSendButton : AppColors.background,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.productName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                ProgressView(value: item.salesAmount, total: maxProductSales)
                                    .tint(index < 3 ? AppColors.chatSendButton : AppColors.tertiaryText)
                                    .scaleEffect(y: 0.65)
                                Text("销量 \(AnalyticsValue.count(item.quantity)) · 占比 \(AnalyticsValue.percent(item.amountShare))")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            Spacer(minLength: 8)
                            Text(AnalyticsValue.currency(item.salesAmount))
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.tertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .analyticsEntrance(order: 3)
    }

    private var productTrendChart: some View {
        GeometryReader { geometry in
            Chart {
                ForEach(trendPoints) { point in
                    AreaMark(
                        x: .value("日期", point.period),
                        y: .value("销售额", point.salesAmount)
                    )
                    .foregroundStyle(AppColors.chatSendButton.opacity(0.10))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("日期", point.period),
                        y: .value("销售额", point.salesAmount)
                    )
                    .foregroundStyle(AppColors.chatSendButton)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                if let selectedPoint {
                    RuleMark(x: .value("选中日期", selectedPoint.period))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.55))
                    PointMark(
                        x: .value("选中日期", selectedPoint.period),
                        y: .value("选中销售额", selectedPoint.salesAmount)
                    )
                    .foregroundStyle(AppColors.chatSendButton)
                    .symbolSize(58)
                    .annotation(position: .top, spacing: 8) {
                        AnalyticsChartTooltip(
                            title: AnalyticsChartAxis.shortLabel(selectedPoint.period),
                            rows: [
                                AnalyticsValue.currency(selectedPoint.salesAmount),
                                "销量 \(AnalyticsValue.count(selectedPoint.quantity))"
                            ]
                        )
                    }
                }
            }
            .analyticsChartTapSelection(axis: .x, selection: $selectedPeriod)
            .chartXAxis {
                AxisMarks(values: AnalyticsChartAxis.values(
                    from: trendPoints.map(\.period),
                    width: geometry.size.width
                )) { value in
                    AxisValueLabel {
                        if let period = value.as(String.self) {
                            Text(AnalyticsChartAxis.shortLabel(period))
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(AppColors.border)
                    AxisValueLabel(format: Decimal.FormatStyle.Currency(code: "CNY").precision(.fractionLength(0)))
                }
            }
            .accessibilityLabel("最近30天产品销售趋势")
            .accessibilityHint("点按图表查看每日销售详情")
        }
    }
}

private struct AnalyticsLaborContent: View {
    @State private var selectedOutputPeriod: String?
    @State private var selectedHoursPeriod: String?
    @State private var isOutputFullScreenPresented = false
    @State private var isHoursFullScreenPresented = false

    let response: AnalyticsLaborResponse
    let trend: AnalyticsLaborResponse?
    let onSelectPoint: (AnalyticsLaborPoint) -> Void

    private var trendPoints: [AnalyticsLaborPoint] {
        trend?.points ?? []
    }

    private var planAttainment: String {
        guard response.summary.plannedHours > 0 else { return "暂无计划" }
        return (response.summary.actualHours / response.summary.plannedHours)
            .formatted(.percent.precision(.fractionLength(1)))
    }

    private var selectedOutputPoint: AnalyticsLaborPoint? {
        guard let selectedOutputPeriod else { return nil }
        return trendPoints.first { $0.period == selectedOutputPeriod }
    }

    private var selectedHoursPoint: AnalyticsLaborPoint? {
        guard let selectedHoursPeriod else { return nil }
        return trendPoints.first { $0.period == selectedHoursPeriod }
    }

    private var laborSnapshot: [AnalyticsSnapshotItem] {
        [
            AnalyticsSnapshotItem(
                label: "实际工时",
                value: AnalyticsValue.hours(response.summary.actualHours),
                detail: "计划达成 \(planAttainment)",
                systemImage: "clock"
            ),
            AnalyticsSnapshotItem(
                label: "计划工时",
                value: AnalyticsValue.hours(response.summary.plannedHours),
                detail: "排班计划基准",
                systemImage: "calendar.badge.clock"
            ),
            AnalyticsSnapshotItem(
                label: "人数",
                value: AnalyticsValue.count(response.summary.headcount),
                detail: "当前统计范围",
                systemImage: "person.2"
            ),
            AnalyticsSnapshotItem(
                label: "小时产出",
                value: AnalyticsValue.currency(response.summary.actualRevenuePerHour),
                detail: "实际每小时产出",
                systemImage: "gauge.with.dots.needle.50percent"
            )
        ]
    }

    var body: some View {
        AnalyticsPageTitle(title: "人效分析", subtitle: "实际工时、计划工时与小时产出")
            .analyticsEntrance(order: 0)

        AnalyticsSnapshotGrid(items: laborSnapshot, columns: 2)
        .analyticsEntrance(order: 1)

        AnalyticsSection(
            title: "小时产出趋势",
            subtitle: "最近30天",
            onExpand: { isOutputFullScreenPresented = true }
        ) {
            if trendPoints.isEmpty {
                AnalyticsEmptyText(text: "最近30天暂无人效趋势数据")
            } else {
                if let latest = trendPoints.last?.actualRevenuePerHour {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AnalyticsValue.currency(latest))
                                .font(.title2.weight(.bold))
                            Text("最新小时产出")
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        Spacer()
                        Label("实际", systemImage: "circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.chatSendButton)
                    }
                }

                hourlyOutputChart.frame(height: 210)

                HStack(spacing: 16) {
                    Label("实际", systemImage: "circle.fill").foregroundStyle(AppColors.chatSendButton)
                    Label("计划", systemImage: "circle.fill").foregroundStyle(AppColors.tertiaryText)
                }
                .font(.caption)
            }
        }
        .analyticsEntrance(order: 2)
        .fullScreenCover(isPresented: $isOutputFullScreenPresented) {
            AnalyticsChartFullScreen(title: "小时产出趋势", subtitle: "最近30天") {
                hourlyOutputChart
            }
        }

        AnalyticsSection(
            title: "工时趋势",
            subtitle: "最近30天 · 实际工时与计划工时",
            onExpand: { isHoursFullScreenPresented = true }
        ) {
            if trendPoints.isEmpty {
                AnalyticsEmptyText(text: "最近30天暂无工时趋势数据")
            } else {
                hoursTrendChart.frame(height: 210)

                HStack(spacing: 16) {
                    Label("实际", systemImage: "circle.fill").foregroundStyle(AppColors.chatSendButton)
                    Label("计划", systemImage: "circle.fill").foregroundStyle(AppColors.tertiaryText)
                }
                .font(.caption)
            }
        }
        .analyticsEntrance(order: 3)
        .fullScreenCover(isPresented: $isHoursFullScreenPresented) {
            AnalyticsChartFullScreen(
                title: "工时趋势",
                subtitle: "最近30天 · 实际工时与计划工时"
            ) {
                hoursTrendChart
            }
        }

        AnalyticsSection(title: "每日明细") {
            if response.points.isEmpty {
                AnalyticsEmptyText(text: "当前周期暂无人效明细")
            } else {
                ForEach(response.points) { point in
                    Button { onSelectPoint(point) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AnalyticsChartAxis.shortLabel(point.period))
                                    .font(.subheadline.weight(.semibold))
                                Text("实际 \(AnalyticsValue.hours(point.actualHours)) · 计划 \(AnalyticsValue.hours(point.plannedHours))")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AnalyticsValue.currency(point.actualRevenuePerHour))
                                    .font(.subheadline.weight(.semibold))
                                Text("小时产出")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.tertiaryText)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .analyticsEntrance(order: 4)
    }

    private var hourlyOutputChart: some View {
        GeometryReader { geometry in
            Chart {
                ForEach(trendPoints) { point in
                    if let actual = point.actualRevenuePerHour {
                        AreaMark(
                            x: .value("日期", point.period),
                            y: .value("小时产出", actual)
                        )
                        .foregroundStyle(AppColors.chatSendButton.opacity(0.10))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("日期", point.period),
                            y: .value("小时产出", actual),
                            series: .value("类型", "实际")
                        )
                        .foregroundStyle(AppColors.chatSendButton)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
                    if let planned = point.plannedRevenuePerHour {
                        LineMark(
                            x: .value("日期", point.period),
                            y: .value("小时产出", planned),
                            series: .value("类型", "计划")
                        )
                        .foregroundStyle(AppColors.tertiaryText)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }

                if let selectedOutputPoint {
                    RuleMark(x: .value("选中日期", selectedOutputPoint.period))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.55))
                        .annotation(position: .top, spacing: 8) {
                            AnalyticsChartTooltip(
                                title: AnalyticsChartAxis.shortLabel(selectedOutputPoint.period),
                                rows: [
                                    "实际 \(AnalyticsValue.currency(selectedOutputPoint.actualRevenuePerHour))",
                                    "计划 \(AnalyticsValue.currency(selectedOutputPoint.plannedRevenuePerHour))"
                                ]
                            )
                        }
                }
            }
            .analyticsChartTapSelection(axis: .x, selection: $selectedOutputPeriod)
            .chartXAxis {
                AxisMarks(values: AnalyticsChartAxis.values(
                    from: trendPoints.map(\.period),
                    width: geometry.size.width
                )) { value in
                    AxisValueLabel {
                        if let period = value.as(String.self) {
                            Text(AnalyticsChartAxis.shortLabel(period))
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .accessibilityLabel("最近30天小时产出趋势")
            .accessibilityHint("点按图表查看每日小时产出详情")
        }
    }

    private var hoursTrendChart: some View {
        GeometryReader { geometry in
            Chart {
                ForEach(trendPoints) { point in
                    BarMark(
                        x: .value("日期", point.period),
                        y: .value("实际工时", point.actualHours)
                    )
                    .foregroundStyle(
                        point.id == selectedHoursPoint?.id
                            ? AppColors.chatSendButton
                            : AppColors.chatSendButton.opacity(0.72)
                    )
                    .cornerRadius(2)

                    LineMark(
                        x: .value("日期", point.period),
                        y: .value("计划工时", point.plannedHours)
                    )
                    .foregroundStyle(AppColors.tertiaryText)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }

                if let selectedHoursPoint {
                    RuleMark(x: .value("选中日期", selectedHoursPoint.period))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.55))
                        .annotation(position: .top, spacing: 8) {
                            AnalyticsChartTooltip(
                                title: AnalyticsChartAxis.shortLabel(selectedHoursPoint.period),
                                rows: [
                                    "实际 \(AnalyticsValue.hours(selectedHoursPoint.actualHours))",
                                    "计划 \(AnalyticsValue.hours(selectedHoursPoint.plannedHours))"
                                ]
                            )
                        }
                }
            }
            .analyticsChartTapSelection(axis: .x, selection: $selectedHoursPeriod)
            .chartXAxis {
                AxisMarks(values: AnalyticsChartAxis.values(
                    from: trendPoints.map(\.period),
                    width: geometry.size.width
                )) { value in
                    AxisValueLabel {
                        if let period = value.as(String.self) {
                            Text(AnalyticsChartAxis.shortLabel(period))
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(AppColors.border)
                    AxisValueLabel()
                }
            }
            .accessibilityLabel("最近30天实际与计划工时趋势")
            .accessibilityHint("点按图表查看每日工时详情")
        }
    }
}

private struct AnalyticsAlertsContent: View {
    @State private var selectedAlertLabel: String?
    @State private var isChartFullScreenPresented = false

    let alerts: [AnalyticsRevenueAlert]
    let businessDate: String
    let onSelectAlert: (AnalyticsRevenueAlert) -> Void

    private var sortedAlerts: [AnalyticsRevenueAlert] {
        alerts.sorted { abs($0.deviationPercent) > abs($1.deviationPercent) }
    }

    private var chartAlerts: [AnalyticsRevenueAlert] {
        Array(sortedAlerts.prefix(8))
    }

    private var selectedAlert: AnalyticsRevenueAlert? {
        guard let selectedAlertLabel else { return nil }
        return chartAlerts.first { $0.shortLabel == selectedAlertLabel }
    }

    private var alertSnapshot: [AnalyticsSnapshotItem] {
        let upwardCount = alerts.filter { $0.deviationPercent >= 0 }.count
        let downwardCount = alerts.count - upwardCount
        let largestDeviation = sortedAlerts.first.map { AnalyticsValue.signedPercent($0.deviationPercent) } ?? "—"
        return [
            AnalyticsSnapshotItem(
                label: "报警数",
                value: "\(alerts.count)",
                detail: "需要关注",
                systemImage: "exclamationmark.triangle",
                tint: .orange
            ),
            AnalyticsSnapshotItem(
                label: "营收上扬",
                value: "\(upwardCount)",
                detail: "高于基准",
                systemImage: "arrow.up.right",
                tint: .green
            ),
            AnalyticsSnapshotItem(
                label: "最大偏离",
                value: largestDeviation,
                detail: "\(downwardCount) 家低于基准",
                systemImage: "arrow.down.right",
                tint: .red
            )
        ]
    }

    var body: some View {
        AnalyticsPageTitle(title: "营收报警", subtitle: "检测日 \(businessDate)")
            .analyticsEntrance(order: 0)

        AnalyticsSnapshotGrid(items: alertSnapshot, columns: 3)
            .analyticsEntrance(order: 1)

        if sortedAlerts.isEmpty {
            AnalyticsMessageState(
                icon: "checkmark.circle",
                title: "暂无营收报警",
                message: "当前检测日没有发现需要关注的门店营收波动。"
            )
            .frame(maxWidth: .infinity, minHeight: 260)
            .analyticsEntrance(order: 2)
        } else {
            AnalyticsSection(
                title: "报警偏离率",
                subtitle: "按偏离绝对值排序",
                onExpand: { isChartFullScreenPresented = true }
            ) {
                alertChart
                    .frame(height: CGFloat(max(150, min(300, chartAlerts.count * 38))))
            }
            .analyticsEntrance(order: 2)
            .fullScreenCover(isPresented: $isChartFullScreenPresented) {
                AnalyticsChartFullScreen(title: "报警偏离率", subtitle: "按偏离绝对值排序") {
                    alertChart
                }
            }

            ForEach(Array(sortedAlerts.enumerated()), id: \.element.id) { index, alert in
                let severity = alertSeverity(alert)
                Button { onSelectAlert(alert) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: alert.deviationPercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(alert.deviationPercent >= 0 ? Color.green : Color.red)
                            .frame(width: 34, height: 34)
                            .background((alert.deviationPercent >= 0 ? Color.green : Color.red).opacity(0.1), in: Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(alert.shopLabel ?? alert.shopKey)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(severity.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(severity.color)
                                    .padding(.horizontal, 7)
                                    .frame(height: 22)
                                    .background(severity.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                            }
                            HStack {
                                Text("实际 \(AnalyticsValue.currency(alert.actualAmount))")
                                Spacer()
                                Text(AnalyticsValue.signedPercent(alert.deviationPercent))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(alert.deviationPercent >= 0 ? Color.green : Color.red)
                            }
                            .font(.caption)
                            Text("基准 \(AnalyticsValue.currency(alert.baselineAmount))")
                                .font(.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                            if let hint = alert.reasonHints?.first, !hint.isEmpty {
                                Text(hint)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.tertiaryText)
                            .padding(.top, 10)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(14)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1)
                }
                .analyticsEntrance(order: min(index + 3, 7))
            }
        }
    }

    private func alertSeverity(_ alert: AnalyticsRevenueAlert) -> (title: String, color: Color) {
        let deviation = abs(alert.deviationPoints)
        if deviation >= 20 { return ("显著", .red) }
        if deviation >= 10 { return ("关注", .orange) }
        return ("轻微", AppColors.secondaryText)
    }

    private var alertChart: some View {
        Chart {
            RuleMark(x: .value("基准", 0))
                .foregroundStyle(AppColors.secondaryText.opacity(0.5))
            ForEach(chartAlerts) { alert in
                BarMark(
                    x: .value("偏离率（%）", alert.deviationPoints),
                    y: .value("门店", alert.shortLabel)
                )
                .foregroundStyle(alert.deviationPercent >= 0 ? Color.green : Color.red)
                .cornerRadius(3)
            }

            if let selectedAlert {
                RuleMark(y: .value("选中门店", selectedAlert.shortLabel))
                    .foregroundStyle(AppColors.secondaryText.opacity(0.55))
                    .annotation(position: .overlay) {
                        AnalyticsChartTooltip(
                            title: selectedAlert.shopLabel ?? selectedAlert.shopKey,
                            rows: [
                                "偏离 \(AnalyticsValue.signedPercent(selectedAlert.deviationPercent))",
                                "实际 \(AnalyticsValue.currency(selectedAlert.actualAmount))",
                                "基准 \(AnalyticsValue.currency(selectedAlert.baselineAmount))"
                            ]
                        )
                    }
            }
        }
        .analyticsChartTapSelection(axis: .y, selection: $selectedAlertLabel)
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(AppColors.border)
                AxisValueLabel()
            }
        }
        .accessibilityLabel("门店营收报警偏离率")
        .accessibilityHint("点按图表查看门店报警详情")
    }
}

private enum AnalyticsChartSelectionAxis {
    case x
    case y
}

private struct AnalyticsChartTapSelection: ViewModifier {
    let axis: AnalyticsChartSelectionAxis
    @Binding var selection: String?

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                guard frame.contains(value.location) else { return }

                                let selectedValue: String?
                                switch axis {
                                case .x:
                                    selectedValue = proxy.value(atX: value.location.x - frame.minX)
                                case .y:
                                    selectedValue = proxy.value(atY: value.location.y - frame.minY)
                                }
                                selection = selectedValue
                            }
                    )
            }
        }
    }
}

private extension View {
    func analyticsChartTapSelection(
        axis: AnalyticsChartSelectionAxis,
        selection: Binding<String?>
    ) -> some View {
        modifier(AnalyticsChartTapSelection(axis: axis, selection: selection))
    }
}

private struct AnalyticsChartFullScreen<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppOrientation.update(.portrait)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("关闭全屏")
                }
            }
        }
        .foregroundStyle(AppColors.primaryText)
        .onAppear {
            AppOrientation.update(.landscape)
        }
        .onDisappear {
            AppOrientation.update(.portrait)
        }
    }
}

private struct AnalyticsChartTooltip: View {
    let title: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(.caption2)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColors.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

private struct AnalyticsPageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.chatSendButton)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnalyticsSnapshotItem: Identifiable {
    let label: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var id: String { label }

    init(
        label: String,
        value: String,
        detail: String,
        systemImage: String,
        tint: Color = AppColors.chatSendButton
    ) {
        self.label = label
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
    }
}

private struct AnalyticsSnapshotGrid: View {
    let items: [AnalyticsSnapshotItem]
    let columns: Int

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: max(columns, 1))
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.tint)
                        Text(item.label)
                            .font(.caption2)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                    Text(item.value)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(AppColors.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .padding(8)
            }
        }
        .padding(4)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        }
    }
}

private enum AnalyticsChartAxis {
    static func values(from periods: [String], width: CGFloat) -> [String] {
        guard !periods.isEmpty else { return [] }
        let labelCount = min(periods.count, min(7, max(2, Int(width / 68))))
        guard labelCount > 1 else { return [periods[0]] }

        let lastIndex = periods.count - 1
        return (0..<labelCount).map { labelIndex in
            let position = Double(labelIndex) * Double(lastIndex) / Double(labelCount - 1)
            return periods[Int(position.rounded())]
        }
    }

    static func shortLabel(_ period: String) -> String {
        guard period.count >= 5 else { return period }
        return String(period.suffix(5)).replacingOccurrences(of: "-", with: "/")
    }
}

private struct AnalyticsKPIGrid: View {
    let metrics: [String: AnalyticsMetricComparison]
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 0) {
                AnalyticsMetricTile(
                    label: "净实收",
                    value: AnalyticsValue.currency(metrics["net_income"]?.current),
                    comparison: metrics["net_income"],
                    compact: true,
                    framed: false
                )
                Divider().frame(height: 54)
                AnalyticsMetricTile(
                    label: "订单数",
                    value: AnalyticsValue.count(metrics["order_count"]?.current),
                    comparison: metrics["order_count"],
                    compact: true,
                    framed: false
                )
                Divider().frame(height: 54)
                AnalyticsMetricTile(
                    label: "客单价",
                    value: AnalyticsValue.currency(metrics["avg_order_value"]?.current),
                    comparison: metrics["avg_order_value"],
                    compact: true,
                    framed: false
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 9)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border, lineWidth: 1)
            }
        } else {
            VStack(spacing: 10) {
                AnalyticsMetricTile(
                    label: "周期净实收",
                    value: AnalyticsValue.currency(metrics["net_income"]?.current),
                    comparison: metrics["net_income"]
                )
                HStack(spacing: 10) {
                    AnalyticsMetricTile(
                        label: "周期订单",
                        value: AnalyticsValue.count(metrics["order_count"]?.current),
                        comparison: metrics["order_count"]
                    )
                    AnalyticsMetricTile(
                        label: "客单价",
                        value: AnalyticsValue.currency(metrics["avg_order_value"]?.current),
                        comparison: metrics["avg_order_value"]
                    )
                }
            }
        }
    }
}

private struct AnalyticsMetricTile: View {
    let label: String
    let value: String
    var comparison: AnalyticsMetricComparison?
    var compact = false
    var framed = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            Text(label)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(AppColors.secondaryText)
            Text(value)
                .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let change = comparison?.changeRate {
                Label(
                    compact ? AnalyticsValue.signedPercent(change) : "较上期 \(AnalyticsValue.signedPercent(change))",
                    systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(change >= 0 ? Color.green : Color.red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("较上期 \(AnalyticsValue.signedPercent(change))")
            } else {
                Text(compact ? "无对比" : "暂无上期对比")
                    .font(.caption2)
                    .foregroundStyle(AppColors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 60 : 94, alignment: .leading)
        .padding(framed ? (compact ? 10 : 14) : 8)
        .background {
            if framed {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.surface)
            }
        }
        .overlay {
            if framed {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border, lineWidth: 1)
            }
        }
    }
}

private struct AnalyticsSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var onExpand: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        onExpand: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onExpand = onExpand
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.chatSendButton.opacity(0.75))
                        .frame(width: 3, height: subtitle == nil ? 18 : 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let onExpand {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(width: 32, height: 32)
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(.plain)
                    .accessibilityLabel("全屏查看\(title)")
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1)
        }
    }
}

private struct AnalyticsEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let order: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : 12)
            .scaleEffect(reduceMotion || isVisible ? 1 : 0.985, anchor: .top)
            .onAppear {
                guard !isVisible else { return }
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(
                        .spring(response: 0.42, dampingFraction: 0.88)
                            .delay(Double(order) * 0.065)
                    ) {
                        isVisible = true
                    }
                }
            }
    }
}

private extension View {
    func analyticsEntrance(order: Int) -> some View {
        modifier(AnalyticsEntranceModifier(order: order))
    }
}

private struct AnalyticsDetailLinkRow: View {
    let title: String
    let primary: String
    let secondary: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(primary).font(.subheadline.weight(.semibold))
                Text(secondary).font(.caption).foregroundStyle(AppColors.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.tertiaryText)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct AnalyticsEmptyText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppColors.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

private struct AnalyticsMessageState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppColors.chatSendButton)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(AppColors.chatSendButton, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private enum AnalyticsValue {
    static func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "¥" + value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }

    static func count(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }

    static func hours(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1))) + " 小时"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        let normalized = abs(value) > 1 ? value / 100 : value
        return normalized.formatted(.percent.precision(.fractionLength(1)))
    }

    static func signedPercent(_ value: Double) -> String {
        let normalized = abs(value) > 1 ? value / 100 : value
        let text = normalized.formatted(.percent.precision(.fractionLength(1)))
        return normalized > 0 ? "+\(text)" : text
    }
}

private extension AnalyticsDimensionRow {
    func value(_ key: String) -> Double {
        metrics[key]?.current ?? 0
    }

    var shortLabel: String {
        let value = label
        return value.count > 8 ? String(value.prefix(8)) + "…" : value
    }

    func csvValue(_ key: String) -> String {
        AnalyticsCSV.number(metrics[key]?.current)
    }
}

private extension AnalyticsRevenueAlert {
    var shortLabel: String {
        let value = shopLabel ?? shopKey
        return value.count > 8 ? String(value.prefix(8)) + "…" : value
    }

    var deviationPoints: Double {
        abs(deviationPercent) > 1 ? deviationPercent : deviationPercent * 100
    }
}

private struct AnalyticsDetail: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let rows: [AnalyticsDetailRow]

    static func dimension(_ item: AnalyticsDimensionRow, subtitle: String) -> Self {
        Self(
            title: item.label,
            subtitle: subtitle,
            rows: [
                AnalyticsDetailRow(label: "订单数", value: "\(AnalyticsValue.count(item.metrics["order_count"]?.current)) 单"),
                AnalyticsDetailRow(label: "净实收", value: AnalyticsValue.currency(item.metrics["net_income"]?.current)),
                AnalyticsDetailRow(label: "客单价", value: AnalyticsValue.currency(item.metrics["avg_order_value"]?.current)),
                AnalyticsDetailRow(label: "退款金额", value: AnalyticsValue.currency(item.metrics["refund_amount"]?.current)),
            ]
        )
    }

    static func product(_ item: AnalyticsProduct, subtitle: String) -> Self {
        Self(
            title: item.productName,
            subtitle: subtitle,
            rows: [
                AnalyticsDetailRow(label: "销售额", value: AnalyticsValue.currency(item.salesAmount)),
                AnalyticsDetailRow(label: "销量", value: AnalyticsValue.count(item.quantity)),
                AnalyticsDetailRow(label: "订单数", value: AnalyticsValue.count(item.orderCount)),
                AnalyticsDetailRow(label: "销售额占比", value: AnalyticsValue.percent(item.amountShare)),
                AnalyticsDetailRow(label: "数量占比", value: AnalyticsValue.percent(item.quantityShare)),
            ]
        )
    }

    static func labor(_ item: AnalyticsLaborPoint) -> Self {
        Self(
            title: item.period,
            subtitle: "人效日明细",
            rows: [
                AnalyticsDetailRow(label: "实际工时", value: AnalyticsValue.hours(item.actualHours)),
                AnalyticsDetailRow(label: "计划工时", value: AnalyticsValue.hours(item.plannedHours)),
                AnalyticsDetailRow(label: "净营收", value: AnalyticsValue.currency(item.netRevenue)),
                AnalyticsDetailRow(label: "人数", value: AnalyticsValue.count(item.headcount)),
                AnalyticsDetailRow(label: "实际小时产出", value: AnalyticsValue.currency(item.actualRevenuePerHour)),
                AnalyticsDetailRow(label: "计划小时产出", value: AnalyticsValue.currency(item.plannedRevenuePerHour)),
            ]
        )
    }

    static func alert(_ item: AnalyticsRevenueAlert) -> Self {
        var rows = [
            AnalyticsDetailRow(label: "实际营收", value: AnalyticsValue.currency(item.actualAmount)),
            AnalyticsDetailRow(label: "基准营收", value: AnalyticsValue.currency(item.baselineAmount)),
            AnalyticsDetailRow(label: "偏离率", value: AnalyticsValue.signedPercent(item.deviationPercent)),
            AnalyticsDetailRow(label: "状态", value: item.status),
        ]
        if let hints = item.reasonHints, !hints.isEmpty {
            rows.append(AnalyticsDetailRow(label: "原因提示", value: hints.joined(separator: "；")))
        }
        return Self(
            title: item.shopLabel ?? item.shopKey,
            subtitle: item.businessDate,
            rows: rows
        )
    }
}

private struct AnalyticsDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct AnalyticsDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let detail: AnalyticsDetail

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(detail.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(row.label)
                                .foregroundStyle(AppColors.secondaryText)
                            Spacer(minLength: 12)
                            Text(row.value)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text(detail.subtitle)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("关闭详情")
                }
            }
        }
    }
}

private struct AnalyticsCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    private var data: Data

    init(rows: [[String]]) {
        data = AnalyticsCSV.data(rows: rows)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum AnalyticsCSV {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", locale: locale, value)
    }

    static func data(rows: [[String]]) -> Data {
        let body = rows
            .map { $0.map(escaped).joined(separator: ",") }
            .joined(separator: "\r\n")
        var result = Data([0xEF, 0xBB, 0xBF])
        result.append(Data(body.utf8))
        return result
    }

    private static func escaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

#Preview {
    BusinessAnalyticsView(onOpenSidebar: {}, onOpenSettings: {})
        .environmentObject(SessionStore())
}
