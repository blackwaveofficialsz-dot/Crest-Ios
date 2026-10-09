package com.blackwave.crest.feature.analytics

import com.blackwave.crest.ui.localization.L

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import com.blackwave.crest.ui.components.CrestIcon
import com.blackwave.crest.ui.components.CrestIconKind

@Composable
internal fun AnalyticsContent(module: AnalyticsModule, data: AnalyticsData, range: AnalyticsRange, onDetail: (AnalyticsDetail) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        when (module) {
            AnalyticsModule.DASHBOARD, AnalyticsModule.ORDERS -> data.overview?.let { overview ->
                AnalyticsMetrics(listOf("net_income" to L("净实收"), "order_count" to L("订单数"), "avg_order_value" to L("客单价")).map { (key, label) ->
                        val metric = overview.metrics[key]
                        Metric(label, if (key == "order_count") analyticsNumber(metric?.current) else analyticsCurrency(metric?.current), rate = metric?.changeRate)
                }, comparison = true)
                val orders = module == AnalyticsModule.ORDERS
                val trend = data.revenue?.points.orEmpty().filter { it.missing != true }
                val change = trend.firstOrNull()?.netIncome?.takeIf { it != 0.0 }?.let { (trend.last().netIncome - it) / abs(it) }
                AnalyticsChart(if (orders) L("订单趋势") else L("营收趋势"), L("最近30天 · %@", L(if (orders) L("按日订单量") else L("按日净实收"))),
                    data.revenue?.points.orEmpty().map { ChartPoint(it.period, if (it.missing == true) null else if (orders) it.orderCount else it.netIncome,
                        detail = if (orders) L("净实收 %@", analyticsCurrency(it.netIncome)) else L("%@ 单", analyticsNumber(it.orderCount))) }, currency = !orders, scrollable = orders, includeZero = orders,
                    summary = if (orders) ChartSummary(L("日均订单"), analyticsNumber(trend.map { it.orderCount }.takeIf { it.isNotEmpty() }?.average()), L("共 %@ 单", analyticsNumber(trend.sumOf { it.orderCount })))
                    else ChartSummary(L("最新净实收"), analyticsCompactCurrency(trend.lastOrNull()?.netIncome), change?.let { (if (it >= 0) "↗ " else "↘ ") + analyticsPercent(it, true) }, change), compactCurrency = !orders)
                val rows = if (orders) overview.stores.sortedByDescending { it.metrics["order_count"]?.current ?: 0.0 } else overview.channels
                AnalyticsSection(if (orders) L("门店订单") else L("渠道表现")) {
                    if (rows.isEmpty()) Text(L("当前周期暂无数据"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    rows.forEachIndexed { index, row ->
                        if (orders) AnalyticsRankRow(index, row.label, L("%@ 单", analyticsNumber(row.metrics["order_count"]?.current)),
                            L("净实收 %@", analyticsCurrency(row.metrics["net_income"]?.current)), L("客单价 %@", analyticsCurrency(row.metrics["avg_order_value"]?.current)),
                            rankingFraction(row.metrics["order_count"]?.current ?: 0.0, rows.maxOfOrNull { it.metrics["order_count"]?.current ?: 0.0 } ?: 0.0)) { onDetail(row.detail(range)) }
                        else AnalyticsLink(row.label, L("%@ 单", analyticsNumber(row.metrics["order_count"]?.current)),
                            analyticsCurrency(row.metrics["net_income"]?.current)) { onDetail(row.detail(range)) }
                    }
                }
            }
            AnalyticsModule.PRODUCTS -> data.products?.let { response ->
                AnalyticsMetrics(listOf(
                    Metric(L("榜单销售额"), analyticsCurrency(response.items.sumOf { it.salesAmount }), L("当前榜单合计"), CrestIconKind.YEN_CIRCLE),
                    Metric(L("商品数"), response.total.toString(), L("参与销售商品"), CrestIconKind.PACKAGE),
                    Metric(L("总销量"), analyticsNumber(response.items.sumOf { it.quantity }), L("当前榜单合计"), CrestIconKind.CART),
                ))
                val latest = data.productTrend?.points?.lastOrNull { it.missing != true }
                AnalyticsChart(L("产品销售趋势"), L("最近30天 · %@", data.productTrend?.productName.orEmpty()),
                    data.productTrend?.points.orEmpty().map { ChartPoint(it.period, if (it.missing == true) null else it.salesAmount, detail = L("销量 %@", analyticsNumber(it.quantity))) }, currency = true,
                    summary = ChartSummary(L("最新销售额"), analyticsCurrency(latest?.salesAmount), L("销量 %@", analyticsNumber(latest?.quantity))))
                AnalyticsSection(L("销售排行"), L("商品销额不等同于财务净实收")) {
                    if (response.items.isEmpty()) Text(L("当前周期暂无产品销售数据"))
                    response.items.forEachIndexed { index, item ->
                        AnalyticsRankRow(index, item.productName, analyticsCurrency(item.salesAmount),
                            L("销量 %@ · 占比 %@", analyticsNumber(item.quantity), analyticsPercent(item.amountShare)), "",
                            rankingFraction(item.salesAmount, response.items.maxOfOrNull { it.salesAmount } ?: 0.0)) { onDetail(item.detail(range)) }
                    }
                }
            }
            AnalyticsModule.LABOR -> data.labor?.let { response ->
                AnalyticsMetrics(listOf(
                    Metric(L("实际工时"), analyticsHours(response.summary.actualHours), L("计划达成 %@", analyticsPercent(response.summary.plannedHours.takeIf { it > 0 }?.let { response.summary.actualHours / it })), CrestIconKind.CLOCK),
                    Metric(L("计划工时"), analyticsHours(response.summary.plannedHours), L("排班计划基准"), CrestIconKind.CALENDAR_CLOCK),
                    Metric(L("人数"), analyticsNumber(response.summary.headcount), L("当前统计范围"), CrestIconKind.PEOPLE),
                    Metric(L("小时产出"), analyticsCurrency(response.summary.actualRevenuePerHour), L("实际每小时产出"), CrestIconKind.GAUGE),
                ), columns = 2)
                val trend = data.laborTrend?.points.orEmpty()
                AnalyticsChart(L("小时产出趋势"), L("最近30天"), trend.map { ChartPoint(it.period, if (it.dataStatus == "missing") null else it.actualRevenuePerHour, if (it.dataStatus == "missing") null else it.plannedRevenuePerHour) }, currency = true,
                    summary = ChartSummary(L("最新小时产出"), analyticsCurrency(trend.lastOrNull { it.dataStatus != "missing" }?.actualRevenuePerHour), L("实际")))
                AnalyticsChart(L("工时趋势"), L("最近30天 · 实际工时与计划工时"), trend.map { ChartPoint(it.period, if (it.dataStatus == "missing") null else it.actualHours, if (it.dataStatus == "missing") null else it.plannedHours) }, bars = true)
                AnalyticsSection(L("每日明细")) {
                    if (response.points.isEmpty()) Text(L("当前周期暂无人效明细"))
                    response.points.forEach { point -> AnalyticsLink(chartDateLabel(point.period), L("实际 %@ · 计划 %@", analyticsHours(point.actualHours), analyticsHours(point.plannedHours)), analyticsCurrency(point.actualRevenuePerHour)) { onDetail(point.detail()) } }
                }
            }
            AnalyticsModule.ALERTS -> data.alerts?.sortedByDescending { abs(it.deviationPercent) }?.let { alerts ->
                AnalyticsMetrics(listOf(
                    Metric(L("报警数"), alerts.size.toString(), L("需要关注"), CrestIconKind.WARNING_TRIANGLE, tint = Color(0xFFFF9500)),
                    Metric(L("营收上扬"), alerts.count { it.deviationPercent >= 0 }.toString(), L("高于基准"), CrestIconKind.ARROW_UP_RIGHT, tint = Color(0xFF34C759)),
                    Metric(L("最大偏离"), analyticsPercent(alerts.firstOrNull()?.deviationPercent, true), L("%lld 家低于基准", alerts.count { it.deviationPercent < 0 }), CrestIconKind.ARROW_DOWN_RIGHT, tint = MaterialTheme.colorScheme.error),
                ))
                if (alerts.isEmpty()) AnalyticsSection(L("暂无营收报警")) { Text(L("当前检测日没有发现需要关注的门店营收波动。")) }
                else {
                    AnalyticsChart(L("报警偏离率"), L("按偏离绝对值排序"), alerts.take(8).map { ChartPoint(it.shopLabel ?: it.shopKey, it.deviationPercent,
                        detail = L("实际 %@", analyticsCurrency(it.actualAmount)) + "\n" + L("基准 %@", analyticsCurrency(it.baselineAmount))) }, bars = true, percent = true)
                    alerts.forEach { alert -> AnalyticsSection(alert.shopLabel ?: alert.shopKey) {
                        val deviation = abs(alert.deviationPercent).let { if (it > 1) it else it * 100 }
                        val severity = if (deviation >= 20) L("显著") else if (deviation >= 10) L("关注") else L("轻微")
                        val tint = if (deviation >= 20) MaterialTheme.colorScheme.error else if (deviation >= 10) Color(0xFFFF9500) else MaterialTheme.colorScheme.onSurfaceVariant
                        Text(severity, Modifier.background(tint.copy(alpha = .1f), RoundedCornerShape(6.dp)).padding(horizontal = 7.dp, vertical = 3.dp), fontSize = 11.sp, color = tint)
                        AnalyticsLink(alert.businessDate, L("实际 %@ · 基准 %@", analyticsCurrency(alert.actualAmount), analyticsCurrency(alert.baselineAmount)), analyticsPercent(alert.deviationPercent, true)) { onDetail(alert.detail()) }
                        if (!alert.reasonHints.isNullOrEmpty()) Text(alert.reasonHints.joinToString("；"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } }
                }
            }
        }
    }
}

@Composable
private fun AnalyticsMetrics(metrics: List<Metric>, columns: Int = 3, comparison: Boolean = false) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(8.dp), border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
        Column(Modifier.padding(4.dp)) {
            metrics.chunked(columns).forEach { row ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    row.forEachIndexed { index, metric ->
                        Column(Modifier.weight(1f).heightIn(min = 78.dp).padding(8.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                metric.icon?.let { CrestIcon(it, Modifier.size(12.dp), metric.tint ?: MaterialTheme.colorScheme.secondary) }
                                Text(metric.title, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                            }
                            Text(metric.value, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (comparison) Text(metric.rate?.let { (if (it >= 0) "↗ " else "↘ ") + analyticsPercent(it, true) } ?: L("无对比"), fontSize = 11.sp,
                                color = metric.rate?.let { if (it >= 0) Color(0xFF34C759) else MaterialTheme.colorScheme.error } ?: MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                            else Text(metric.detail, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        if (comparison && index < row.lastIndex) VerticalDivider(Modifier.height(54.dp), color = MaterialTheme.colorScheme.outline)
                    }
                }
            }
        }
    }
}

private data class Metric(val title: String, val value: String, val detail: String = "", val icon: CrestIconKind? = null, val rate: Double? = null, val tint: Color? = null)

@Composable
private fun AnalyticsRankRow(index: Int, title: String, value: String, detail: String, trailingDetail: String, fraction: Float, onClick: () -> Unit) {
    val tint = if (index < 3) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onSurfaceVariant
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(26.dp).background(if (index < 3) tint else MaterialTheme.colorScheme.background, RoundedCornerShape(6.dp)), contentAlignment = Alignment.Center) {
            Text((index + 1).toString(), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (index < 3) Color.White else tint)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, Modifier.weight(1f), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(value, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            }
            Box(Modifier.fillMaxWidth().height(3.dp).background(MaterialTheme.colorScheme.outline.copy(alpha = .45f), RoundedCornerShape(2.dp))) {
                Box(Modifier.fillMaxWidth(fraction).fillMaxHeight().background(tint, RoundedCornerShape(2.dp)))
            }
            Row {
                Text(detail, Modifier.weight(1f), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (trailingDetail.isNotEmpty()) Text(trailingDetail, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        CrestIcon(CrestIconKind.CHEVRON_RIGHT, Modifier.size(12.dp), MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
