package com.blackwave.crest.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
data class AnalyticsStoreNode(
    val key: String,
    val type: String,
    val label: String,
    @SerialName("store_key") val storeKey: String? = null,
    val children: List<AnalyticsStoreNode>? = null,
) {
    fun stores(): List<Pair<String, String>> =
        listOfNotNull(storeKey?.let { it to label }) + children.orEmpty().flatMap { it.stores() }
}

@Serializable
data class AnalyticsStoreScope(val nodes: List<AnalyticsStoreNode>, @SerialName("store_count") val storeCount: Int)

@Serializable
data class AnalyticsRevenuePoint(
    val period: String,
    @SerialName("net_income") val netIncome: Double,
    @SerialName("order_count") val orderCount: Double,
    val missing: Boolean? = null,
)

@Serializable
data class AnalyticsRevenueTrend(val points: List<AnalyticsRevenuePoint>)

@Serializable
data class AnalyticsProduct(
    @SerialName("product_key") val productKey: String,
    @SerialName("product_name") val productName: String,
    val quantity: Double,
    @SerialName("sales_amount") val salesAmount: Double,
    @SerialName("order_count") val orderCount: Double? = null,
    @SerialName("quantity_share") val quantityShare: Double,
    @SerialName("amount_share") val amountShare: Double,
)

@Serializable
data class AnalyticsProducts(
    @SerialName("data_status") val dataStatus: String,
    val items: List<AnalyticsProduct>,
    val total: Int,
)

@Serializable
data class AnalyticsProductPoint(
    val period: String,
    val quantity: Double,
    @SerialName("sales_amount") val salesAmount: Double,
    val missing: Boolean? = null,
)

@Serializable
data class AnalyticsProductTrend(
    @SerialName("product_key") val productKey: String,
    @SerialName("product_name") val productName: String? = null,
    val points: List<AnalyticsProductPoint>,
)

@Serializable
data class AnalyticsLaborPoint(
    val period: String,
    @SerialName("data_status") val dataStatus: String,
    @SerialName("actual_hours") val actualHours: Double,
    @SerialName("planned_hours") val plannedHours: Double,
    @SerialName("net_revenue") val netRevenue: Double,
    val headcount: Double,
    @SerialName("actual_revenue_per_hour") val actualRevenuePerHour: Double? = null,
    @SerialName("planned_revenue_per_hour") val plannedRevenuePerHour: Double? = null,
)

@Serializable
data class AnalyticsLaborSummary(
    @SerialName("actual_hours") val actualHours: Double,
    @SerialName("planned_hours") val plannedHours: Double,
    @SerialName("net_revenue") val netRevenue: Double,
    val headcount: Double,
    @SerialName("actual_revenue_per_hour") val actualRevenuePerHour: Double? = null,
    @SerialName("planned_revenue_per_hour") val plannedRevenuePerHour: Double? = null,
)

@Serializable
data class AnalyticsLabor(
    @SerialName("data_status") val dataStatus: String,
    val points: List<AnalyticsLaborPoint>,
    val summary: AnalyticsLaborSummary,
)

@Serializable
data class AnalyticsAlert(
    @SerialName("actual_amount") val actualAmount: Double,
    @SerialName("baseline_amount") val baselineAmount: Double,
    @SerialName("business_date") val businessDate: String,
    @SerialName("deviation_pct") val deviationPercent: Double,
    val direction: String,
    @SerialName("reason_hints") val reasonHints: List<String>? = null,
    @SerialName("shop_key") val shopKey: String,
    @SerialName("shop_label") val shopLabel: String? = null,
    val status: String,
)

@Serializable
data class AnalyticsAlerts(val alerts: List<AnalyticsAlert>)

@Serializable
data class AnalyticsChangedDay(val date: String, val version: String, val payload: JsonObject? = null)

/** Both existing delta endpoints share day versions; product V2 also carries access metadata. */
@Serializable
data class AnalyticsDelta(
    @SerialName("changed_days") val changedDays: List<AnalyticsChangedDay>,
    @SerialName("unchanged_days") val unchangedDays: List<String>,
    @SerialName("deleted_days") val deletedDays: List<String>? = null,
    @SerialName("product_name") val productName: String? = null,
    @SerialName("schema_version") val schemaVersion: String? = null,
    @SerialName("access_scope_hash") val accessScopeHash: String? = null,
    val namespace: String? = null,
    @SerialName("params_hash") val paramsHash: String? = null,
    @SerialName("reset_required") val resetRequired: Boolean? = null,
)
