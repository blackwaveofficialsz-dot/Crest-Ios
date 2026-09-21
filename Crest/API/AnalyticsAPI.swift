import Foundation

enum AnalyticsAPIError: LocalizedError {
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let message): message
        }
    }
}

struct AnalyticsSessionContext: Sendable {
    let accessToken: String
    let cacheIdentity: AnalyticsCacheIdentity
}

private struct AnalyticsLoginRequest: Encodable {
    let identifierType = "username"
    let identifier: String
    let password: String
    let clientType = "mobile"
    let deviceName = "Crest iOS Analytics"

    enum CodingKeys: String, CodingKey {
        case identifierType = "identifier_type"
        case identifier
        case password
        case clientType = "client_type"
        case deviceName = "device_name"
    }
}

@MainActor
final class AnalyticsOnlineSession {
    static let shared = AnalyticsOnlineSession()

    static var isConfigured: Bool {
        let environment = ProcessInfo.processInfo.environment
        let hasCredentials = !(environment["CREST_ANALYTICS_USERNAME"] ?? "").isEmpty
            && !(environment["CREST_ANALYTICS_PASSWORD"] ?? "").isEmpty
        return hasCredentials || KeychainStore(service: keychainService).readRefreshToken() != nil
    }

    private static let keychainService = "com.blackwave.crest.analytics"
    private let api = APIClient(baseURL: URL(string: "https://blackwave.org.cn/yuanji")!)
    private let keychain = KeychainStore(service: keychainService)
    private var sessionContext: AnalyticsSessionContext?

    private init() {}

    func validContext() async throws -> AnalyticsSessionContext {
        if let sessionContext { return sessionContext }

        if let refreshToken = keychain.readRefreshToken() {
            do {
                return try saveSession(try await api.refreshSession(refreshToken: refreshToken))
            } catch let error as APIError where error.invalidatesSession {
                keychain.deleteSessionTokens()
            }
        }

        let environment = ProcessInfo.processInfo.environment
        guard
            let username = environment["CREST_ANALYTICS_USERNAME"], !username.isEmpty,
            let password = environment["CREST_ANALYTICS_PASSWORD"], !password.isEmpty
        else {
            throw APIError.server("线上经营分析会话已失效，请重新配置测试账号")
        }
        return try saveSession(try await api.analyticsLogin(username: username, password: password))
    }

    func invalidateAccessToken() {
        sessionContext = nil
    }

    private func saveSession(_ response: LoginResponse) throws -> AnalyticsSessionContext {
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw APIError.invalidSession
        }
        guard let identity = AnalyticsCacheIdentity(
            userID: response.userID,
            workspaceID: response.activeWorkspaceID
        ) else {
            throw APIError.invalidSession
        }
        try keychain.saveRefreshToken(refreshToken)
        let context = AnalyticsSessionContext(accessToken: response.token, cacheIdentity: identity)
        sessionContext = context
        return context
    }
}

struct AnalyticsDateRange: Codable {
    let dateFrom: String
    let dateTo: String

    enum CodingKeys: String, CodingKey {
        case dateFrom = "date_from"
        case dateTo = "date_to"
    }
}

struct AnalyticsMetricComparison: Codable {
    let current: Double?
    let previous: Double?
    let difference: Double?
    let changeRate: Double?
    let status: String

    enum CodingKeys: String, CodingKey {
        case current
        case previous
        case difference
        case changeRate = "change_rate"
        case status
    }
}

struct AnalyticsDimensionRow: Codable, Identifiable {
    let dimKey: String?
    let dimLabel: String?
    let storeKey: String?
    let storeLabel: String?
    let metrics: [String: AnalyticsMetricComparison]

    var id: String { storeKey ?? dimKey ?? label }
    var label: String { storeLabel ?? dimLabel ?? storeKey ?? dimKey ?? "未命名" }

    enum CodingKeys: String, CodingKey {
        case dimKey = "dim_key"
        case dimLabel = "dim_label"
        case storeKey = "store_key"
        case storeLabel = "store_label"
        case metrics
    }
}

struct AnalyticsOverview: Codable {
    let period: AnalyticsDateRange
    let previousPeriod: AnalyticsDateRange?
    let metrics: [String: AnalyticsMetricComparison]
    let channels: [AnalyticsDimensionRow]
    let stores: [AnalyticsDimensionRow]
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case period
        case previousPeriod = "previous_period"
        case metrics
        case channels
        case stores
        case generatedAt = "generated_at"
    }
}

struct AnalyticsStoreScopeNode: Codable, Identifiable {
    let key: String
    let type: String
    let label: String
    let storeKey: String?
    let children: [AnalyticsStoreScopeNode]?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key
        case type
        case label
        case storeKey = "store_key"
        case children
    }
}

struct AnalyticsStoreScopeResponse: Codable {
    let nodes: [AnalyticsStoreScopeNode]
    let storeCount: Int

    enum CodingKeys: String, CodingKey {
        case nodes
        case storeCount = "store_count"
    }
}

struct AnalyticsRevenueTrendPoint: Codable, Identifiable {
    let period: String
    let netIncome: Double
    let orderCount: Double
    let missing: Bool?

    var id: String { period }

    enum CodingKeys: String, CodingKey {
        case period
        case netIncome = "net_income"
        case orderCount = "order_count"
        case missing
    }
}

struct AnalyticsRevenueTrendResponse: Codable {
    let points: [AnalyticsRevenueTrendPoint]
}

struct AnalyticsProduct: Codable, Identifiable {
    let productKey: String
    let productName: String
    let quantity: Double
    let salesAmount: Double
    let orderCount: Double?
    let quantityShare: Double
    let amountShare: Double

    var id: String { productKey }

    enum CodingKeys: String, CodingKey {
        case productKey = "product_key"
        case productName = "product_name"
        case quantity
        case salesAmount = "sales_amount"
        case orderCount = "order_count"
        case quantityShare = "quantity_share"
        case amountShare = "amount_share"
    }
}

struct AnalyticsProductsResponse: Codable {
    let dataStatus: String
    let items: [AnalyticsProduct]
    let total: Int

    enum CodingKeys: String, CodingKey {
        case dataStatus = "data_status"
        case items
        case total
    }
}

struct AnalyticsProductTrendPoint: Codable, Identifiable {
    let period: String
    let quantity: Double
    let salesAmount: Double
    let missing: Bool?

    var id: String { period }

    enum CodingKeys: String, CodingKey {
        case period
        case quantity
        case salesAmount = "sales_amount"
        case missing
    }
}

struct AnalyticsProductTrendResponse: Codable {
    let productKey: String
    let productName: String?
    let points: [AnalyticsProductTrendPoint]

    enum CodingKeys: String, CodingKey {
        case productKey = "product_key"
        case productName = "product_name"
        case points
    }
}

struct AnalyticsLaborPoint: Codable, Identifiable {
    let period: String
    let dataStatus: String
    let actualHours: Double
    let plannedHours: Double
    let netRevenue: Double
    let headcount: Double
    let actualRevenuePerHour: Double?
    let plannedRevenuePerHour: Double?

    var id: String { period }

    enum CodingKeys: String, CodingKey {
        case period
        case dataStatus = "data_status"
        case actualHours = "actual_hours"
        case plannedHours = "planned_hours"
        case netRevenue = "net_revenue"
        case headcount
        case actualRevenuePerHour = "actual_revenue_per_hour"
        case plannedRevenuePerHour = "planned_revenue_per_hour"
    }
}

struct AnalyticsLaborSummary: Codable {
    let actualHours: Double
    let plannedHours: Double
    let netRevenue: Double
    let headcount: Double
    let actualRevenuePerHour: Double?
    let plannedRevenuePerHour: Double?

    enum CodingKeys: String, CodingKey {
        case actualHours = "actual_hours"
        case plannedHours = "planned_hours"
        case netRevenue = "net_revenue"
        case headcount
        case actualRevenuePerHour = "actual_revenue_per_hour"
        case plannedRevenuePerHour = "planned_revenue_per_hour"
    }
}

struct AnalyticsLaborResponse: Codable {
    let dataStatus: String
    let points: [AnalyticsLaborPoint]
    let summary: AnalyticsLaborSummary

    enum CodingKeys: String, CodingKey {
        case dataStatus = "data_status"
        case points
        case summary
    }
}

struct AnalyticsRevenueAlert: Codable, Identifiable {
    let actualAmount: Double
    let baselineAmount: Double
    let businessDate: String
    let deviationPercent: Double
    let direction: String
    let reasonHints: [String]?
    let shopKey: String
    let shopLabel: String?
    let status: String

    var id: String { "\(businessDate):\(shopKey):\(direction)" }

    enum CodingKeys: String, CodingKey {
        case actualAmount = "actual_amount"
        case baselineAmount = "baseline_amount"
        case businessDate = "business_date"
        case deviationPercent = "deviation_pct"
        case direction
        case reasonHints = "reason_hints"
        case shopKey = "shop_key"
        case shopLabel = "shop_label"
        case status
    }
}

private struct AnalyticsRevenueAlertsResponse: Codable {
    let alerts: [AnalyticsRevenueAlert]
}

extension APIClient {
    private var analyticsBaseURL: URL {
        if let value = ProcessInfo.processInfo.environment["CREST_ANALYTICS_API_BASE_URL"],
           let overrideURL = URL(string: value) {
            return overrideURL
        }
        return URL(string: "https://blackwave.org.cn/yuanji")!
    }

    func analyticsLogin(username: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: analyticsBaseURL.appending(path: "/api/v1/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            AnalyticsLoginRequest(identifier: username, password: password)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "线上经营分析登录失败（\(http.statusCode)）"
            if http.statusCode == 401 {
                throw APIError.unauthorized(message)
            }
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    func analyticsOverview(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        refresh: Bool,
        accessToken: String
    ) async throws -> AnalyticsOverview {
        try await analyticsGET(
            "/api/v1/analytics/operations/overview",
            queryItems: analyticsPeriodItems(dateFrom: dateFrom, dateTo: dateTo, storeKeys: storeKeys) + [
                URLQueryItem(name: "compare", value: "previous"),
                URLQueryItem(name: "granularity", value: "day"),
                URLQueryItem(name: "order_breakdown", value: "channel"),
                URLQueryItem(name: "refresh", value: String(refresh)),
            ],
            accessToken: accessToken,
            fallbackError: "经营概览加载失败"
        )
    }

    func analyticsProducts(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        accessToken: String
    ) async throws -> AnalyticsProductsResponse {
        try await analyticsGET(
            "/api/v1/analytics/operations/products",
            queryItems: analyticsPeriodItems(dateFrom: dateFrom, dateTo: dateTo, storeKeys: storeKeys) + [
                URLQueryItem(name: "compare", value: "previous"),
                URLQueryItem(name: "granularity", value: "day"),
                URLQueryItem(name: "limit", value: "30"),
            ],
            accessToken: accessToken,
            fallbackError: "产品分析加载失败"
        )
    }

    func analyticsLabor(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        accessToken: String
    ) async throws -> AnalyticsLaborResponse {
        try await analyticsGET(
            "/api/v1/analytics/operations/labor",
            queryItems: analyticsPeriodItems(dateFrom: dateFrom, dateTo: dateTo, storeKeys: storeKeys) + [
                URLQueryItem(name: "compare", value: "previous"),
                URLQueryItem(name: "granularity", value: "day"),
            ],
            accessToken: accessToken,
            fallbackError: "人效分析加载失败"
        )
    }

    func analyticsRevenueAlerts(
        businessDate: String,
        accessToken: String
    ) async throws -> [AnalyticsRevenueAlert] {
        let response: AnalyticsRevenueAlertsResponse = try await analyticsGET(
            "/api/v1/analytics/revenue-alerts",
            queryItems: [URLQueryItem(name: "business_date", value: businessDate)],
            accessToken: accessToken,
            fallbackError: "营收报警加载失败"
        )
        return response.alerts
    }

    func analyticsStoreScope(accessToken: String) async throws -> AnalyticsStoreScopeResponse {
        try await analyticsGET(
            "/api/v1/analytics/store-scope-tree",
            queryItems: [],
            accessToken: accessToken,
            fallbackError: "门店范围加载失败"
        )
    }

    func analyticsRevenueTrend(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        accessToken: String
    ) async throws -> AnalyticsRevenueTrendResponse {
        try await analyticsGET(
            "/api/v1/analytics/trends/revenue",
            queryItems: analyticsPeriodItems(dateFrom: dateFrom, dateTo: dateTo, storeKeys: storeKeys) + [
                URLQueryItem(name: "store_key", value: "ALL"),
                URLQueryItem(name: "source_type", value: "all"),
                URLQueryItem(name: "granularity", value: "day"),
                URLQueryItem(name: "include_current", value: "false"),
            ],
            accessToken: accessToken,
            fallbackError: "营收趋势加载失败"
        )
    }

    func analyticsProductTrend(
        productKey: String,
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        accessToken: String
    ) async throws -> AnalyticsProductTrendResponse {
        let scopeKey = storeKeys.count == 1 ? storeKeys[0] : "ALL"
        let scopeType = storeKeys.count == 1 ? "shop" : "all"
        return try await analyticsGET(
            "/api/v1/analytics/products/trend",
            queryItems: analyticsPeriodItems(dateFrom: dateFrom, dateTo: dateTo, storeKeys: storeKeys) + [
                URLQueryItem(name: "product_key", value: productKey),
                URLQueryItem(name: "dim_key", value: scopeKey),
                URLQueryItem(name: "dim_type", value: scopeType),
                URLQueryItem(name: "granularity", value: "day"),
                URLQueryItem(name: "include_current", value: "false"),
            ],
            accessToken: accessToken,
            fallbackError: "产品趋势加载失败"
        )
    }

    private func analyticsPeriodItems(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String]
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "date_from", value: dateFrom),
            URLQueryItem(name: "date_to", value: dateTo),
        ]
        items.append(contentsOf: storeKeys.map { URLQueryItem(name: "store_keys", value: $0) })
        return items
    }

    private func analyticsGET<Response: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem],
        accessToken: String,
        fallbackError: String
    ) async throws -> Response {
        guard var components = URLComponents(
            url: analyticsBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidResponse
        }
        components.queryItems = queryItems
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "\(fallbackError)（\(http.statusCode)）"
            if http.statusCode == 401 {
                throw AnalyticsAPIError.unauthorized(message)
            }
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct AnalyticsClientDay: Encodable {
    let date: String
    let version: String
}

private struct AnalyticsDeltaChangedDay<Payload: Codable>: Decodable {
    let date: String
    let version: String
    let payload: Payload?
}

private struct AnalyticsDeltaResponse<Payload: Codable>: Decodable {
    let changedDays: [AnalyticsDeltaChangedDay<Payload>]
    let unchangedDays: [String]
    let productName: String?

    enum CodingKeys: String, CodingKey {
        case changedDays = "changed_days"
        case unchangedDays = "unchanged_days"
        case productName = "product_name"
    }
}

private struct AnalyticsDailyFactV2Response<Payload: Codable>: Decodable {
    let accessScopeHash: String
    let changedDays: [AnalyticsDailyFactV2ChangedDay<Payload>]
    let deletedDays: [String]
    let namespace: String
    let paramsHash: String
    let productName: String?
    let resetRequired: Bool
    let schemaVersion: String
    let unchangedDays: [String]

    enum CodingKeys: String, CodingKey {
        case accessScopeHash = "access_scope_hash"
        case changedDays = "changed_days"
        case deletedDays = "deleted_days"
        case namespace
        case paramsHash = "params_hash"
        case productName = "product_name"
        case resetRequired = "reset_required"
        case schemaVersion = "schema_version"
        case unchangedDays = "unchanged_days"
    }
}

private struct AnalyticsDailyFactV2ChangedDay<Payload: Codable>: Decodable {
    let date: String
    let version: String
    let payload: Payload
}

private struct AnalyticsRevenueDeltaParams: Encodable {
    let sourceType = "all"
    let storeKey: String

    enum CodingKeys: String, CodingKey {
        case sourceType = "source_type"
        case storeKey = "store_key"
    }
}

private struct AnalyticsRevenueDeltaRequest: Encodable {
    let clientDays: [AnalyticsClientDay]
    let dateFrom: String
    let dateTo: String
    let forceRefresh: Bool
    let params: AnalyticsRevenueDeltaParams

    enum CodingKeys: String, CodingKey {
        case clientDays = "client_days"
        case dateFrom = "date_from"
        case dateTo = "date_to"
        case forceRefresh = "force_refresh"
        case params
    }
}

private struct AnalyticsProductDeltaParams: Encodable {
    let dimKey: String
    let dimType: String
    let productKey: String

    enum CodingKeys: String, CodingKey {
        case dimKey = "dim_key"
        case dimType = "dim_type"
        case productKey = "product_key"
    }
}

private struct AnalyticsProductDeltaRequest: Encodable {
    let schemaVersion = "product-daily-fact-v2"
    let clientAccessScopeHash: String?
    let clientDays: [AnalyticsClientDay]
    let dateFrom: String
    let dateTo: String
    let forceRefresh: Bool
    let params: AnalyticsProductDeltaParams

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case clientAccessScopeHash = "client_access_scope_hash"
        case clientDays = "client_days"
        case dateFrom = "date_from"
        case dateTo = "date_to"
        case forceRefresh = "force_refresh"
        case params
    }
}

extension APIClient {
    func analyticsOverview(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        refresh: Bool,
        accessToken: String,
        cacheIdentity: AnalyticsCacheIdentity
    ) async throws -> AnalyticsOverview {
        try await cachedAnalyticsValue(
            identity: cacheIdentity,
            scope: analyticsScope("overview", dateFrom, dateTo, storeKeys),
            forceRefresh: refresh
        ) {
            try await analyticsOverview(
                dateFrom: dateFrom,
                dateTo: dateTo,
                storeKeys: storeKeys,
                refresh: refresh,
                accessToken: accessToken
            )
        }
    }

    func analyticsProducts(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        refresh: Bool,
        accessToken: String,
        cacheIdentity: AnalyticsCacheIdentity
    ) async throws -> AnalyticsProductsResponse {
        try await cachedAnalyticsValue(
            identity: cacheIdentity,
            scope: analyticsScope("products", dateFrom, dateTo, storeKeys),
            forceRefresh: refresh
        ) {
            try await analyticsProducts(
                dateFrom: dateFrom,
                dateTo: dateTo,
                storeKeys: storeKeys,
                accessToken: accessToken
            )
        }
    }

    func analyticsLabor(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        refresh: Bool,
        accessToken: String,
        cacheIdentity: AnalyticsCacheIdentity
    ) async throws -> AnalyticsLaborResponse {
        try await cachedAnalyticsValue(
            identity: cacheIdentity,
            scope: analyticsScope("labor", dateFrom, dateTo, storeKeys),
            forceRefresh: refresh
        ) {
            try await analyticsLabor(
                dateFrom: dateFrom,
                dateTo: dateTo,
                storeKeys: storeKeys,
                accessToken: accessToken
            )
        }
    }

    func analyticsRevenueAlerts(
        businessDate: String,
        refresh: Bool,
        accessToken: String,
        cacheIdentity: AnalyticsCacheIdentity
    ) async throws -> [AnalyticsRevenueAlert] {
        try await cachedAnalyticsValue(
            identity: cacheIdentity,
            scope: "alerts|\(businessDate)",
            forceRefresh: refresh
        ) {
            try await analyticsRevenueAlerts(
                businessDate: businessDate,
                accessToken: accessToken
            )
        }
    }

    func analyticsStoreScope(
        accessToken: String,
        cacheIdentity: AnalyticsCacheIdentity
    ) async throws -> AnalyticsStoreScopeResponse {
        try await cachedAnalyticsValue(
            identity: cacheIdentity,
            scope: "store-scope|v1",
            forceRefresh: false
        ) {
            try await analyticsStoreScope(accessToken: accessToken)
        }
    }

    func analyticsRevenueTrend(
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        refresh: Bool,
        accessToken: String,
        cacheIdentity: AnalyticsCacheIdentity
    ) async throws -> AnalyticsRevenueTrendResponse {
        let snapshotScope = analyticsScope("revenue-trend", dateFrom, dateTo, storeKeys)
        guard storeKeys.count <= 1 else {
            return try await cachedAnalyticsValue(
                identity: cacheIdentity,
                scope: snapshotScope,
                forceRefresh: refresh
            ) {
                try await analyticsRevenueTrend(
                    dateFrom: dateFrom,
                    dateTo: dateTo,
                    storeKeys: storeKeys,
                    accessToken: accessToken
                )
            }
        }

        let storeKey = storeKeys.first ?? "ALL"
        let dailyScope = "revenue-daily-v1|\(storeKey)|all"
        do {
            let expectedDates = try analyticsDates(from: dateFrom, to: dateTo)
            if refresh {
                try? await AnalyticsCache.shared.clearDaily(identity: cacheIdentity, scope: dailyScope)
                try? await AnalyticsCache.shared.clearSnapshot(identity: cacheIdentity, scope: snapshotScope)
            }
            let existing: [String: AnalyticsCachedDay<AnalyticsRevenueTrendPoint>] =
                try await AnalyticsCache.shared.dailyEntries(
                    identity: cacheIdentity,
                    scope: dailyScope,
                    dateFrom: dateFrom,
                    dateTo: dateTo
                )
            let request = AnalyticsRevenueDeltaRequest(
                clientDays: existing.values.map { AnalyticsClientDay(date: $0.date, version: $0.version) },
                dateFrom: dateFrom,
                dateTo: dateTo,
                forceRefresh: refresh,
                params: AnalyticsRevenueDeltaParams(storeKey: storeKey)
            )
            let delta: AnalyticsDeltaResponse<AnalyticsRevenueTrendPoint> = try await analyticsPOST(
                "/api/v1/analytics/trends/revenue/delta",
                body: request,
                accessToken: accessToken,
                fallbackError: "营收趋势增量加载失败"
            )
            try validateAnalyticsDelta(
                delta,
                expectedDates: expectedDates,
                clientDays: request.clientDays
            )
            try await AnalyticsCache.shared.mergeDaily(
                delta.changedDays.map {
                    AnalyticsChangedDay(date: $0.date, version: $0.version, payload: $0.payload)
                },
                identity: cacheIdentity,
                scope: dailyScope
            )
            let merged: [String: AnalyticsCachedDay<AnalyticsRevenueTrendPoint>] =
                try await AnalyticsCache.shared.dailyEntries(
                    identity: cacheIdentity,
                    scope: dailyScope,
                    dateFrom: dateFrom,
                    dateTo: dateTo
                )
            guard expectedDates.allSatisfy({ merged[$0] != nil }) else {
                throw APIError.server("经营分析日缓存不完整")
            }
            let response = AnalyticsRevenueTrendResponse(
                points: expectedDates.compactMap { merged[$0]?.payload }
            )
            try? await AnalyticsCache.shared.saveSnapshot(
                response,
                identity: cacheIdentity,
                scope: snapshotScope
            )
            return response
        } catch let authenticationError as AnalyticsAPIError {
            throw authenticationError
        } catch {
            return try await cachedAnalyticsValue(
                identity: cacheIdentity,
                scope: snapshotScope,
                forceRefresh: refresh
            ) {
                try await analyticsRevenueTrend(
                    dateFrom: dateFrom,
                    dateTo: dateTo,
                    storeKeys: storeKeys,
                    accessToken: accessToken
                )
            }
        }
    }

    func analyticsProductTrend(
        productKey: String,
        dateFrom: String,
        dateTo: String,
        storeKeys: [String],
        refresh: Bool,
        accessToken: String,
        cacheIdentity: AnalyticsCacheIdentity
    ) async throws -> AnalyticsProductTrendResponse {
        let snapshotScope = analyticsScope("product-trend|\(productKey)", dateFrom, dateTo, storeKeys)
        guard storeKeys.count <= 1 else {
            return try await cachedAnalyticsValue(
                identity: cacheIdentity,
                scope: snapshotScope,
                forceRefresh: refresh
            ) {
                try await analyticsProductTrend(
                    productKey: productKey,
                    dateFrom: dateFrom,
                    dateTo: dateTo,
                    storeKeys: storeKeys,
                    accessToken: accessToken
                )
            }
        }

        let dimKey = storeKeys.first ?? "ALL"
        let dimType = storeKeys.isEmpty ? "all" : "shop"
        let dailyScope = "product-daily-v2|\(dimType)|\(dimKey)|\(productKey)"
        let schemaVersion = "product-daily-fact-v2"
        do {
            let previous: AnalyticsCachedSnapshot<AnalyticsProductTrendResponse>? = try? await AnalyticsCache.shared.snapshot(
                identity: cacheIdentity,
                scope: snapshotScope
            )
            let expectedDates = try analyticsDates(from: dateFrom, to: dateTo)
            var metadata = try await AnalyticsCache.shared.dailyMetadata(
                identity: cacheIdentity,
                scope: dailyScope
            )
            if refresh || metadata?.schemaVersion != schemaVersion || metadata?.accessScopeHash.isEmpty != false {
                try? await AnalyticsCache.shared.clearDaily(identity: cacheIdentity, scope: dailyScope)
                try? await AnalyticsCache.shared.clearSnapshot(identity: cacheIdentity, scope: snapshotScope)
                metadata = nil
            }
            let existing: [String: AnalyticsCachedDay<AnalyticsProductTrendPoint>] =
                try await AnalyticsCache.shared.dailyEntries(
                    identity: cacheIdentity,
                    scope: dailyScope,
                    dateFrom: dateFrom,
                    dateTo: dateTo
                )
            let request = AnalyticsProductDeltaRequest(
                clientAccessScopeHash: metadata?.accessScopeHash,
                clientDays: existing.values.map { AnalyticsClientDay(date: $0.date, version: $0.version) },
                dateFrom: dateFrom,
                dateTo: dateTo,
                forceRefresh: refresh,
                params: AnalyticsProductDeltaParams(
                    dimKey: dimKey,
                    dimType: dimType,
                    productKey: productKey
                )
            )
            let delta: AnalyticsDailyFactV2Response<AnalyticsProductTrendPoint> = try await analyticsPOST(
                "/api/v1/analytics/products/trend/delta",
                body: request,
                accessToken: accessToken,
                fallbackError: "产品趋势增量加载失败"
            )
            try validateAnalyticsDailyFactV2(
                delta,
                expectedDates: expectedDates,
                clientDays: request.clientDays,
                previousMetadata: metadata,
                schemaVersion: schemaVersion
            )
            if delta.resetRequired {
                try await AnalyticsCache.shared.clearDaily(identity: cacheIdentity, scope: dailyScope)
            }
            try await AnalyticsCache.shared.mergeDaily(
                delta.changedDays.map {
                    AnalyticsChangedDay(date: $0.date, version: $0.version, payload: $0.payload)
                } + delta.deletedDays.map {
                    AnalyticsChangedDay(date: $0, version: "deleted", payload: nil)
                },
                identity: cacheIdentity,
                scope: dailyScope
            )
            try await AnalyticsCache.shared.saveDailyMetadata(
                AnalyticsDailyMetadata(
                    schemaVersion: delta.schemaVersion,
                    accessScopeHash: delta.accessScopeHash,
                    namespace: delta.namespace,
                    paramsHash: delta.paramsHash
                ),
                identity: cacheIdentity,
                scope: dailyScope
            )
            let merged: [String: AnalyticsCachedDay<AnalyticsProductTrendPoint>] =
                try await AnalyticsCache.shared.dailyEntries(
                    identity: cacheIdentity,
                    scope: dailyScope,
                    dateFrom: dateFrom,
                    dateTo: dateTo
                )
            let deletedDates = Set(delta.deletedDays)
            guard expectedDates.allSatisfy({ merged[$0] != nil || deletedDates.contains($0) }) else {
                throw APIError.server("经营分析日缓存不完整")
            }
            let response = AnalyticsProductTrendResponse(
                productKey: productKey,
                productName: delta.productName ?? previous?.value.productName,
                points: expectedDates.compactMap { merged[$0]?.payload }
            )
            try? await AnalyticsCache.shared.saveSnapshot(
                response,
                identity: cacheIdentity,
                scope: snapshotScope
            )
            return response
        } catch let authenticationError as AnalyticsAPIError {
            throw authenticationError
        } catch {
            return try await cachedAnalyticsValue(
                identity: cacheIdentity,
                scope: snapshotScope,
                forceRefresh: refresh
            ) {
                try await analyticsProductTrend(
                    productKey: productKey,
                    dateFrom: dateFrom,
                    dateTo: dateTo,
                    storeKeys: storeKeys,
                    accessToken: accessToken
                )
            }
        }
    }

    private func cachedAnalyticsValue<Value: Codable>(
        identity: AnalyticsCacheIdentity,
        scope: String,
        forceRefresh: Bool,
        load: () async throws -> Value
    ) async throws -> Value {
        if forceRefresh {
            try? await AnalyticsCache.shared.clearSnapshot(identity: identity, scope: scope)
        } else if let cached: AnalyticsCachedSnapshot<Value> = try? await AnalyticsCache.shared.snapshot(
            identity: identity,
            scope: scope
        ), Date().timeIntervalSince(cached.cachedAt) < 5 * 60 {
            return cached.value
        }

        do {
            let value = try await load()
            try? await AnalyticsCache.shared.saveSnapshot(value, identity: identity, scope: scope)
            return value
        } catch let authenticationError as AnalyticsAPIError {
            throw authenticationError
        } catch {
            if !forceRefresh,
               let cached: AnalyticsCachedSnapshot<Value> = try? await AnalyticsCache.shared.snapshot(
                   identity: identity,
                   scope: scope
               ) {
                return cached.value
            }
            throw error
        }
    }

    private func analyticsScope(
        _ name: String,
        _ dateFrom: String,
        _ dateTo: String,
        _ storeKeys: [String]
    ) -> String {
        "\(name)|\(dateFrom)|\(dateTo)|\(storeKeys.sorted().joined(separator: ","))"
    }

    private func analyticsDates(from dateFrom: String, to dateTo: String) throws -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: dateFrom),
              let end = formatter.date(from: dateTo),
              start <= end
        else {
            throw APIError.server("经营分析日期范围无效")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var dates: [String] = []
        var current = start
        while current <= end, dates.count <= 365 {
            dates.append(formatter.string(from: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        guard dates.count <= 365, dates.last == dateTo else {
            throw APIError.server("经营分析日期范围不能超过 365 天")
        }
        return dates
    }

    private func validateAnalyticsDelta<Payload: Codable>(
        _ response: AnalyticsDeltaResponse<Payload>,
        expectedDates: [String],
        clientDays: [AnalyticsClientDay]
    ) throws {
        let requested = Set(expectedDates)
        let client = Set(clientDays.map(\.date))
        var resolved = Set<String>()
        for changed in response.changedDays {
            guard requested.contains(changed.date), resolved.insert(changed.date).inserted else {
                throw APIError.server("经营分析增量协议无效")
            }
        }
        for unchanged in response.unchangedDays {
            guard requested.contains(unchanged), client.contains(unchanged), resolved.insert(unchanged).inserted else {
                throw APIError.server("经营分析增量协议无效")
            }
        }
        guard resolved == requested else {
            throw APIError.server("经营分析增量协议无效")
        }
    }

    private func validateAnalyticsDailyFactV2<Payload: Codable>(
        _ response: AnalyticsDailyFactV2Response<Payload>,
        expectedDates: [String],
        clientDays: [AnalyticsClientDay],
        previousMetadata: AnalyticsDailyMetadata?,
        schemaVersion: String
    ) throws {
        guard response.schemaVersion == schemaVersion,
              !response.namespace.isEmpty,
              !response.paramsHash.isEmpty,
              !response.accessScopeHash.isEmpty,
              previousMetadata?.accessScopeHash == nil
                || previousMetadata?.accessScopeHash == response.accessScopeHash
                || response.resetRequired
        else {
            throw APIError.server("经营分析 V2 增量协议无效")
        }

        let requested = Set(expectedDates)
        let client = Set(clientDays.map(\.date))
        var resolved = Set<String>()
        for changed in response.changedDays {
            guard requested.contains(changed.date), resolved.insert(changed.date).inserted else {
                throw APIError.server("经营分析 V2 增量协议无效")
            }
        }
        for unchanged in response.unchangedDays {
            guard !response.resetRequired,
                  requested.contains(unchanged),
                  client.contains(unchanged),
                  resolved.insert(unchanged).inserted
            else {
                throw APIError.server("经营分析 V2 增量协议无效")
            }
        }
        for deleted in response.deletedDays {
            guard requested.contains(deleted), resolved.insert(deleted).inserted else {
                throw APIError.server("经营分析 V2 增量协议无效")
            }
        }
        guard resolved == requested else {
            throw APIError.server("经营分析 V2 增量协议无效")
        }
    }

    private func analyticsPOST<Request: Encodable, Response: Decodable>(
        _ path: String,
        body: Request,
        accessToken: String,
        fallbackError: String
    ) async throws -> Response {
        var request = URLRequest(url: analyticsBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = readErrorMessage(from: data) ?? "\(fallbackError)（\(http.statusCode)）"
            if http.statusCode == 401 { throw AnalyticsAPIError.unauthorized(message) }
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
