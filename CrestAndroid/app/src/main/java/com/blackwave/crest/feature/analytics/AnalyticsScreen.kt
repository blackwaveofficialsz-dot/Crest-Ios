package com.blackwave.crest.feature.analytics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.blackwave.crest.core.model.AnalyticsDimensionRow
import com.blackwave.crest.core.model.AnalyticsMetricComparison
import com.blackwave.crest.core.model.AnalyticsOverview
import com.blackwave.crest.core.session.SessionStore
import com.blackwave.crest.core.session.SessionUser
import com.blackwave.crest.core.session.userMessage
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

private enum class AnalyticsPeriod(val title: String) {
    YESTERDAY("昨日"),
    LAST_SEVEN_DAYS("近 7 天"),
    CURRENT_MONTH("本月"),
    PREVIOUS_MONTH("上月"),
}

private data class DateRange(val from: LocalDate, val to: LocalDate)

@Composable
fun AnalyticsScreen(
    session: SessionStore,
    user: SessionUser,
    onOpenSettings: () -> Unit,
) {
    if (user.tenantId == null) {
        Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("切换到团队工作空间", style = MaterialTheme.typography.titleLarge)
                Text(
                    "经营分析只读取当前团队的门店、订单和人效数据。",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(onClick = onOpenSettings) { Text("选择工作空间") }
            }
        }
        return
    }

    var period by rememberSaveable { mutableStateOf(AnalyticsPeriod.CURRENT_MONTH) }
    var overview by remember { mutableStateOf<AnalyticsOverview?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshRequest by remember { mutableIntStateOf(0) }
    val range = remember(period) { period.range() }

    LaunchedEffect(user.activeWorkspaceId, period, refreshRequest) {
        isLoading = true
        error = null
        try {
            overview = session.authenticated { token ->
                session.api.analyticsOverview(
                    dateFrom = range.from.format(API_DATE),
                    dateTo = range.to.format(API_DATE),
                    refresh = refreshRequest > 0,
                    accessToken = token,
                )
            }
        } catch (failure: Exception) {
            error = failure.userMessage("经营概览加载失败")
        } finally {
            isLoading = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        PeriodSelector(
            selected = period,
            range = range,
            isLoading = isLoading,
            onSelect = {
                if (it != period) {
                    overview = null
                    period = it
                }
            },
            onRefresh = { refreshRequest += 1 },
        )

        when {
            isLoading && overview == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator()
                    Text("正在读取经营数据", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            error != null && overview == null -> AnalyticsMessage(
                title = "暂时无法加载",
                message = error.orEmpty(),
                action = { refreshRequest += 1 },
            )
            overview != null -> OverviewContent(
                overview = overview!!,
                warning = error,
            )
            else -> AnalyticsMessage(
                title = "暂无经营数据",
                message = "当前周期没有可展示的数据。",
                action = { refreshRequest += 1 },
            )
        }
    }
}

@Composable
private fun PeriodSelector(
    selected: AnalyticsPeriod,
    range: DateRange,
    isLoading: Boolean,
    onSelect: (AnalyticsPeriod) -> Unit,
    onRefresh: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("经营看板", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    "${range.from.format(DISPLAY_DATE)} 至 ${range.to.format(DISPLAY_DATE)} · 全部门店",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            TextButton(enabled = !isLoading, onClick = onRefresh) { Text(if (isLoading) "刷新中…" else "刷新") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AnalyticsPeriod.entries.forEach { option ->
                if (selected == option) {
                    Button(onClick = { onSelect(option) }, modifier = Modifier.weight(1f)) { Text(option.title) }
                } else {
                    OutlinedButton(onClick = { onSelect(option) }, modifier = Modifier.weight(1f)) { Text(option.title) }
                }
            }
        }
    }
}

@Composable
private fun OverviewContent(overview: AnalyticsOverview, warning: String?) {
    val hasData = overview.metrics.values.any { it.current != null } || overview.channels.isNotEmpty()
    if (!hasData) {
        AnalyticsMessage(title = "暂无经营数据", message = "当前周期没有订单或营收数据。")
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                KpiCard(
                    label = "净实收",
                    value = currency(overview.metrics["net_income"]?.current),
                    comparison = overview.metrics["net_income"],
                    modifier = Modifier.weight(1f),
                )
                KpiCard(
                    label = "订单数",
                    value = count(overview.metrics["order_count"]?.current),
                    comparison = overview.metrics["order_count"],
                    modifier = Modifier.weight(1f),
                )
                KpiCard(
                    label = "客单价",
                    value = currency(overview.metrics["avg_order_value"]?.current),
                    comparison = overview.metrics["avg_order_value"],
                    modifier = Modifier.weight(1f),
                )
            }
        }
        item {
            Text("渠道表现", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
        if (overview.channels.isEmpty()) {
            item {
                Surface(shape = MaterialTheme.shapes.large, tonalElevation = 1.dp) {
                    Text(
                        "当前周期暂无渠道数据",
                        modifier = Modifier.fillMaxWidth().padding(20.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(overview.channels, key = AnalyticsDimensionRow::id) { channel ->
                ChannelRow(channel)
            }
        }
        warning?.let {
            item { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun KpiCard(
    label: String,
    value: String,
    comparison: AnalyticsMetricComparison?,
    modifier: Modifier = Modifier,
) {
    val rate = comparison?.changeRate
    val positive = rate != null && rate >= 0
    Surface(modifier = modifier, shape = MaterialTheme.shapes.large, tonalElevation = 1.dp) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                rate?.let(::signedPercent) ?: "无对比",
                style = MaterialTheme.typography.labelSmall,
                color = when {
                    rate == null -> MaterialTheme.colorScheme.onSurfaceVariant
                    positive -> POSITIVE
                    else -> MaterialTheme.colorScheme.error
                },
            )
        }
    }
}

@Composable
private fun ChannelRow(channel: AnalyticsDimensionRow) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        tonalElevation = 1.dp,
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(channel.label, modifier = Modifier.weight(1f), fontWeight = FontWeight.Medium)
            Column(horizontalAlignment = Alignment.End) {
                Text(currency(channel.metrics["net_income"]?.current), fontWeight = FontWeight.SemiBold)
                Text(
                    "${count(channel.metrics["order_count"]?.current)} 单",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun AnalyticsMessage(title: String, message: String, action: (() -> Unit)? = null) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (action != null) Button(onClick = action) { Text("重新加载") }
        }
    }
}

private fun AnalyticsPeriod.range(): DateRange {
    val end = LocalDate.now(SHANGHAI).minusDays(1)
    return when (this) {
        AnalyticsPeriod.YESTERDAY -> DateRange(end, end)
        AnalyticsPeriod.LAST_SEVEN_DAYS -> DateRange(end.minusDays(6), end)
        AnalyticsPeriod.CURRENT_MONTH -> DateRange(end.withDayOfMonth(1), end)
        AnalyticsPeriod.PREVIOUS_MONTH -> {
            val previous = end.withDayOfMonth(1).minusMonths(1)
            DateRange(previous, previous.withDayOfMonth(previous.lengthOfMonth()))
        }
    }
}

private fun currency(value: Double?): String = value?.let {
    "¥" + NumberFormat.getNumberInstance(Locale.CHINA).apply { maximumFractionDigits = 0 }.format(it)
} ?: "—"

private fun count(value: Double?): String = value?.let {
    NumberFormat.getNumberInstance(Locale.CHINA).apply { maximumFractionDigits = 0 }.format(it)
} ?: "—"

private fun signedPercent(value: Double): String {
    val normalized = if (abs(value) > 1) value / 100 else value
    val prefix = if (normalized > 0) "+" else ""
    return "$prefix${String.format(Locale.CHINA, "%.1f", normalized * 100)}%"
}

private val SHANGHAI: ZoneId = ZoneId.of("Asia/Shanghai")
private val API_DATE: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
private val DISPLAY_DATE: DateTimeFormatter = DateTimeFormatter.ofPattern("M月d日", Locale.CHINA)
private val POSITIVE = Color(0xFF1B7F4B)
