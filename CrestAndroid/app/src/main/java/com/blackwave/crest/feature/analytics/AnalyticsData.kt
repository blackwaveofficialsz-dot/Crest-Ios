package com.blackwave.crest.feature.analytics

import com.blackwave.crest.core.model.*
import com.blackwave.crest.ui.localization.L
import com.blackwave.crest.ui.localization.AppLocalization
import java.time.LocalDate
import java.time.ZoneId
import java.text.NumberFormat
import android.icu.text.Collator
import android.icu.text.RuleBasedCollator
import java.util.Locale
import kotlin.math.abs
import kotlinx.serialization.Serializable

internal enum class AnalyticsModule(val title: String, val heading: String, val subtitle: String) {
    DASHBOARD("看板", "经营看板", "当前周期与上期经营表现"),
    ORDERS("订单", "订单统计", "全部门店订单与实收概览"),
    PRODUCTS("产品", "产品分析", "按商品销售额排名"),
    LABOR("人效", "人效分析", "实际工时、计划工时与小时产出"),
    ALERTS("报警", "营收报警", "检测日"),
}

internal enum class AnalyticsPeriod(val title: String) {
    YESTERDAY("昨日"), LAST_SEVEN_DAYS("近 7 天"), CURRENT_MONTH("本月"), PREVIOUS_MONTH("上月");

    fun range(today: LocalDate = LocalDate.now(ZoneId.of("Asia/Shanghai"))): AnalyticsRange {
        val end = today.minusDays(1)
        return when (this) {
            YESTERDAY -> AnalyticsRange(end, end)
            LAST_SEVEN_DAYS -> AnalyticsRange(end.minusDays(6), end)
            CURRENT_MONTH -> AnalyticsRange(end.withDayOfMonth(1), end)
            PREVIOUS_MONTH -> AnalyticsRange(end.withDayOfMonth(1).minusMonths(1), end.withDayOfMonth(1).minusDays(1))
        }
    }
}

internal data class AnalyticsRange(val from: LocalDate, val to: LocalDate)

@Serializable
internal data class AnalyticsData(
    val overview: AnalyticsOverview? = null,
    val revenue: AnalyticsRevenueTrend? = null,
    val products: AnalyticsProducts? = null,
    val productTrend: AnalyticsProductTrend? = null,
    val labor: AnalyticsLabor? = null,
    val laborTrend: AnalyticsLabor? = null,
    val alerts: List<AnalyticsAlert>? = null,
)

internal data class AnalyticsDetail(val title: String, val subtitle: String, val rows: List<Pair<String, String>>)

internal fun analyticsStoreOptions(nodes: List<AnalyticsStoreNode>, locale: Locale): List<Pair<String, String>> {
    val collator = Collator.getInstance(locale)
    (collator as? RuleBasedCollator)?.numericCollation = true
    return nodes.flatMap { it.stores() }.distinctBy { it.first }
        .sortedWith { left, right -> collator.compare(left.second, right.second) }
}

internal fun analyticsNumber(value: Double?): String = value?.let { String.format(AppLocalization.locale, "%,.0f", it) } ?: "—"
internal fun analyticsCurrency(value: Double?): String = value?.let { "¥${analyticsNumber(it)}" } ?: "—"
internal fun analyticsCompactCurrency(value: Double?): String {
    if (value == null) return "—"
    val chineseWan = AppLocalization.locale.language == "zh" && abs(value) >= 10_000
    val divisor = if (chineseWan) 10_000 else if (abs(value) >= 1_000) 1_000 else 1
    val digits = if (chineseWan && abs(value) < 100_000) 1 else 0
    val amount = NumberFormat.getNumberInstance(AppLocalization.locale).apply {
        minimumFractionDigits = digits
        maximumFractionDigits = digits
    }.format(value / divisor)
    return "¥$amount" + if (chineseWan) "万" else if (divisor == 1_000) "k" else ""
}
internal fun analyticsHours(value: Double): String = L("%@ 小时", String.format(AppLocalization.locale, "%,.1f", value))
internal fun analyticsPercent(value: Double?, signed: Boolean = false): String = value?.let {
    val percent = if (abs(it) > 1) it else it * 100
    String.format(AppLocalization.locale, if (signed && percent > 0) "+%.1f%%" else "%.1f%%", percent)
} ?: "—"

internal fun AnalyticsDimensionRow.detail(range: AnalyticsRange) = AnalyticsDetail(label, L("%@ 至 %@", range.from, range.to), listOf(
    "订单数" to analyticsNumber(metrics["order_count"]?.current),
    "净实收" to analyticsCurrency(metrics["net_income"]?.current),
    "客单价" to analyticsCurrency(metrics["avg_order_value"]?.current),
    "退款金额" to analyticsCurrency(metrics["refund_amount"]?.current),
))

internal fun AnalyticsProduct.detail(range: AnalyticsRange) = AnalyticsDetail(productName, L("%@ 至 %@", range.from, range.to), listOf(
    "销售额" to analyticsCurrency(salesAmount), "销量" to analyticsNumber(quantity),
    "订单数" to analyticsNumber(orderCount), "销售额占比" to analyticsPercent(amountShare), "数量占比" to analyticsPercent(quantityShare),
))

internal fun AnalyticsLaborPoint.detail() = AnalyticsDetail(period, L("人效日明细"), listOf(
    "实际工时" to analyticsHours(actualHours), "计划工时" to analyticsHours(plannedHours),
    "净营收" to analyticsCurrency(netRevenue), "人数" to analyticsNumber(headcount),
    "实际小时产出" to analyticsCurrency(actualRevenuePerHour), "计划小时产出" to analyticsCurrency(plannedRevenuePerHour),
))

internal fun AnalyticsAlert.detail() = AnalyticsDetail(shopLabel ?: shopKey, businessDate, listOf(
    "实际营收" to analyticsCurrency(actualAmount), "基准营收" to analyticsCurrency(baselineAmount),
    "偏离率" to analyticsPercent(deviationPercent, true), "状态" to status,
) + if (reasonHints.isNullOrEmpty()) emptyList() else listOf("原因提示" to reasonHints.joinToString("；")))

/** Always quote CSV cells; neutralize spreadsheet formulas in backend-supplied labels. */
internal fun analyticsCsv(rows: List<List<String>>): ByteArray = ("\uFEFF" + rows.joinToString("\r\n") { row ->
    row.joinToString(",") { value ->
        val safe = if (value.trimStart().firstOrNull() in listOf('=', '+', '-', '@') && value.toDoubleOrNull() == null) "'$value" else value
        "\"${safe.replace("\"", "\"\"")}\""
    }
}).toByteArray(Charsets.UTF_8)

internal fun AnalyticsData.exportRows(module: AnalyticsModule, range: AnalyticsRange, stores: String): List<List<String>> {
    val rows = mutableListOf(listOf(L("模块"), L(module.title)), listOf(L("日期范围"), range.from.toString(), range.to.toString()), listOf(L("门店范围"), stores), emptyList())
    fun number(value: Double?) = value?.toString().orEmpty()
    when (module) {
        AnalyticsModule.DASHBOARD, AnalyticsModule.ORDERS -> {
            listOf("门店" to overview?.stores.orEmpty(), "渠道" to overview?.channels.orEmpty()).forEach { (label, dimensions) ->
                rows += listOf(label, "订单数", "净实收", "客单价").map { L(it) }
                rows += dimensions.map { listOf(it.label, number(it.metrics["order_count"]?.current), number(it.metrics["net_income"]?.current), number(it.metrics["avg_order_value"]?.current)) }
                rows.add(emptyList())
            }
        }
        AnalyticsModule.PRODUCTS -> {
            rows += listOf("产品", "销量", "销售额", "订单数", "数量占比", "销售额占比").map { L(it) }
            rows += products?.items.orEmpty().map { listOf(it.productName, number(it.quantity), number(it.salesAmount), number(it.orderCount), number(it.quantityShare), number(it.amountShare)) }
        }
        AnalyticsModule.LABOR -> {
            rows += listOf("日期", "实际工时", "计划工时", "净营收", "人数", "实际小时产出", "计划小时产出").map { L(it) }
            rows += labor?.points.orEmpty().map { listOf(it.period, number(it.actualHours), number(it.plannedHours), number(it.netRevenue), number(it.headcount), number(it.actualRevenuePerHour), number(it.plannedRevenuePerHour)) }
        }
        AnalyticsModule.ALERTS -> {
            rows += listOf("日期", "门店", "实际营收", "基准营收", "偏离率", "方向", "状态", "原因提示").map { L(it) }
            rows += alerts.orEmpty().map { listOf(it.businessDate, it.shopLabel ?: it.shopKey, number(it.actualAmount), number(it.baselineAmount), number(it.deviationPercent), it.direction, it.status, it.reasonHints.orEmpty().joinToString("；")) }
        }
    }
    return rows
}
