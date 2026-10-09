package com.blackwave.crest.feature.analytics

import android.app.Activity
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.blackwave.crest.ui.components.CrestIconKind
import com.blackwave.crest.ui.components.CrestIcon
import com.blackwave.crest.ui.components.CrestDialogSystemBars
import com.blackwave.crest.ui.localization.L
import kotlin.math.abs
import kotlin.math.roundToInt

internal data class ChartPoint(val label: String, val value: Double?, val comparison: Double? = null, val detail: String? = null)
internal data class ChartSummary(val label: String, val value: String, val badge: String? = null, val change: Double? = null)

@Composable
internal fun AnalyticsChart(
    title: String, subtitle: String, points: List<ChartPoint>, currency: Boolean = false,
    bars: Boolean = false, percent: Boolean = false, summary: ChartSummary? = null, compactCurrency: Boolean = false,
    scrollable: Boolean = false, includeZero: Boolean = true,
) {
    var expanded by remember { mutableStateOf(false) }
    var selected by remember(points) { mutableStateOf<Int?>(null) }
    val plot: @Composable (Modifier) -> Unit = { modifier ->
        if (percent) AlertPlot(points, selected, { selected = it }, modifier)
        else ChartPlot(points, currency, compactCurrency, bars, scrollable, includeZero, summary, selected, { selected = it }, modifier)
    }
    AnalyticsSection(title, subtitle, action = {
        IconButton({ expanded = true }, Modifier.size(44.dp).semantics { contentDescription = L("全屏查看") }) {
            CrestIcon(CrestIconKind.EXPAND, Modifier.size(15.dp), MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }) {
        plot(Modifier.height(if (percent) (points.size * 38).coerceIn(150, 300).dp else 282.dp))
    }
    if (expanded) {
        val context = LocalContext.current
        DisposableEffect(context) {
            val activity = generateSequence(context) { (it as? ContextWrapper)?.baseContext }.filterIsInstance<Activity>().firstOrNull()
            val previous = activity?.requestedOrientation
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            onDispose { if (previous != null) activity.requestedOrientation = previous }
        }
        Dialog({ expanded = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            CrestDialogSystemBars(MaterialTheme.colorScheme.background)
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Column(Modifier.safeDrawingPadding().padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                        AnalyticsIcon(CrestIconKind.CLOSE, L("关闭全屏"), { expanded = false })
                    }
                    Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                    plot(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ChartPlot(points: List<ChartPoint>, currency: Boolean, compactCurrency: Boolean, bars: Boolean, scrollable: Boolean, includeZero: Boolean, summary: ChartSummary?, selected: Int?, onSelect: (Int) -> Unit, modifier: Modifier) {
    if (points.none { it.value != null || it.comparison != null }) {
        Text(L("暂无趋势数据"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    val initialCount = if (scrollable) minOf(14, points.size) else points.size
    var visibleCount by remember(points) { mutableFloatStateOf(initialCount.toFloat()) }
    var first by remember(points) { mutableFloatStateOf((points.size - initialCount).toFloat()) }
    val visible = points.drop(first.roundToInt()).take(visibleCount.roundToInt().coerceAtLeast(1))
    val domain = chartDomain(points.flatMap { listOfNotNull(it.value, it.comparison) }, includeZero)
    val bottom = domain.start
    val top = domain.endInclusive
    val ticks = trendChartTicks(domain)
    val primary = MaterialTheme.colorScheme.secondary
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val grid = MaterialTheme.colorScheme.outline.copy(alpha = .5f)
    val red = MaterialTheme.colorScheme.error
    val hasComparison = points.any { it.comparison != null }
    val axisOnRight = hasComparison && !bars // iOS hourly-output chart uses the native trailing number axis.
    val axisWidth = if (axisOnRight) 28.dp else 45.dp
    fun formatted(value: Double?) = if (bars) value?.let(::analyticsHours) ?: "—" else if (compactCurrency) analyticsCompactCurrency(value) else if (currency) analyticsCurrency(value) else analyticsNumber(value)
    val axisLabels: @Composable () -> Unit = {
        Box(Modifier.width(axisWidth).fillMaxHeight()) {
            ticks.forEach { tick ->
                Text(if (bars || axisOnRight) analyticsNumber(tick) else formatted(tick), Modifier.align(Alignment { child, space, _ ->
                    IntOffset(0, ((1 - (tick - bottom) / (top - bottom)) * space.height - child.height / 2).roundToInt())
                }), fontSize = 10.sp, color = secondary, maxLines = 1)
            }
        }
    }
    val point = selected?.let { points.getOrNull(it) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        summary?.let {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(it.value, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                    Text(it.label, fontSize = 11.sp, color = secondary)
                }
                it.badge?.let { badge ->
                    val tint = summary.change?.let { rate -> if (rate >= 0) Color(0xFF34C759) else red } ?: primary
                    val badgeModifier = if (summary.change != null) Modifier.background(tint.copy(alpha = .1f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 5.dp) else Modifier
                    Text(badge, badgeModifier, fontSize = 11.sp, color = tint)
                }
            }
        }
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!axisOnRight) axisLabels()
            Box(Modifier.weight(1f).fillMaxHeight()) {
                Canvas(Modifier.fillMaxSize()
                    .semantics {
                        contentDescription = point?.let { "${it.label}: ${formatted(it.value)}" } ?: points.joinToString("; ") { "${it.label}: ${formatted(it.value)}" }
                        customActions = listOf(-1 to L("上一项"), 1 to L("下一项")).map { (direction, label) ->
                            CustomAccessibilityAction(label) {
                                val index = ((selected ?: points.lastIndex) + direction).coerceIn(points.indices)
                                onSelect(index)
                                first = index.coerceIn(0, (points.size - visibleCount.roundToInt()).coerceAtLeast(0)).toFloat()
                                true
                            }
                        }
                    }
                    .pointerInput(points, first, visibleCount) {
                        detectTapGestures { tap ->
                            val localIndex = if (bars) tap.x / size.width * visible.size - .5f
                                else (tap.x - 6.dp.toPx()) / (size.width - 12.dp.toPx()).coerceAtLeast(1f) * (visible.size - 1)
                            onSelect((first.roundToInt() + localIndex.roundToInt()).coerceIn(points.indices))
                        }
                    }
                    .pointerInput(points, scrollable) {
                        if (scrollable) detectTransformGestures { _, pan, zoom, _ ->
                                visibleCount = (visibleCount / zoom).coerceIn(minOf(7f, points.size.toFloat()), points.size.toFloat())
                                first = (first - pan.x / size.width * visibleCount).coerceIn(0f, (points.size - visibleCount).coerceAtLeast(0f))
                        }
                    }) {
                    val width = size.width
                    val height = size.height
                    fun x(index: Int) = if (bars || visible.size == 1) (index + .5f) / visible.size * width
                        else 6.dp.toPx() + index.toFloat() / (visible.size - 1) * (width - 12.dp.toPx())
                    fun y(value: Double) = (height - (value - bottom) / (top - bottom) * height).toFloat()
                    ticks.forEach { drawLine(grid, Offset(0f, y(it)), Offset(width, y(it)), .5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))) }
                    if (bars) visible.forEachIndexed { index, item -> item.value?.let { value ->
                        val barWidth = width / visible.size * .6f
                        val tint = if (value < 0) red else primary.copy(alpha = if (selected == first.roundToInt() + index) 1f else .72f)
                        drawRoundRect(tint, Offset(x(index) - barWidth / 2, minOf(y(value), y(0.0))), Size(barWidth, abs(y(value) - y(0.0)).coerceAtLeast(1f)), androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()))
                    } }
                    run {
                        listOf(false, true).forEach { comparison ->
                            if (bars && !comparison) return@forEach
                            // Missing days break the line and its filled area.
                            val segments = mutableListOf<MutableList<Offset>>()
                            var segment = mutableListOf<Offset>()
                            visible.forEachIndexed { index, item ->
                                val value = if (comparison) item.comparison else item.value
                                if (value == null) {
                                    if (segment.isNotEmpty()) segments += segment
                                    segment = mutableListOf()
                                } else segment += Offset(x(index), y(value))
                            }
                            if (segment.isNotEmpty()) segments += segment
                            segments.forEach { offsets ->
                                val path = Path().apply {
                                    moveTo(offsets.first().x, offsets.first().y)
                                    for (index in 0 until offsets.lastIndex) {
                                        val a = offsets[(index - 1).coerceAtLeast(0)]
                                        val b = offsets[index]
                                        val c = offsets[index + 1]
                                        val d = offsets[(index + 2).coerceAtMost(offsets.lastIndex)]
                                        if (comparison) lineTo(c.x, c.y)
                                        else cubicTo(b.x + (c.x - a.x) / 6, (b.y + (c.y - a.y) / 6).coerceIn(0f, height), c.x - (d.x - b.x) / 6, (c.y - (d.y - b.y) / 6).coerceIn(0f, height), c.x, c.y)
                                    }
                                }
                                if (!comparison) {
                                    val fill = Path().apply { addPath(path); lineTo(offsets.last().x, height); lineTo(offsets.first().x, height); close() }
                                    drawPath(fill, primary.copy(alpha = .10f))
                                }
                                drawPath(path, if (comparison) secondary.copy(alpha = .65f) else primary, style = Stroke(
                                    (if (comparison) if (bars) 2.dp else 1.5.dp else 2.5.dp).toPx(), cap = StrokeCap.Round,
                                    pathEffect = if (comparison) PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx())) else null,
                                ))
                                if (offsets.size == 1) drawCircle(if (comparison) secondary else primary, 3.dp.toPx(), offsets.first())
                            }
                        }
                    }
                    if (!includeZero && selected != points.lastIndex && first.roundToInt() + visible.lastIndex == points.lastIndex) {
                        visible.lastOrNull()?.value?.let { drawCircle(primary, 3.5.dp.toPx(), Offset(x(visible.lastIndex), y(it))) }
                    }
                    val index = selected?.minus(first.roundToInt())
                    if (index != null && index in visible.indices) {
                        drawLine(secondary.copy(alpha = .55f), Offset(x(index), 0f), Offset(x(index), height), 1.dp.toPx())
                        visible[index].value?.let { drawCircle(primary, 5.dp.toPx(), Offset(x(index), y(it))) }
                        visible[index].comparison?.let { drawCircle(secondary, 4.dp.toPx(), Offset(x(index), y(it))) }
                    }
                }
                if (point != null && selected - first.roundToInt() in visible.indices) {
                    ChartTooltip(chartDateLabel(point.label), listOfNotNull(
                        if (hasComparison) L("实际 %@", formatted(point.value)) else if (scrollable) L("%@ 单", formatted(point.value)) else formatted(point.value),
                        if (hasComparison) L("计划 %@", formatted(point.comparison)) else null, point.detail,
                    ), Modifier.align(if (selected - first.roundToInt() < visible.size / 2) Alignment.TopEnd else Alignment.TopStart))
                }
            }
            if (axisOnRight) axisLabels()
        }
        BoxWithConstraints(Modifier.fillMaxWidth().padding(start = if (axisOnRight) 0.dp else 53.dp, end = if (axisOnRight) 36.dp else 0.dp).height(16.dp)) {
            chartLabelIndices(visible.size, maxWidth.value + axisWidth.value + 8).forEach { index ->
                Text(chartDateLabel(visible[index].label), Modifier.align(Alignment { child, space, _ ->
                    val fraction = if (bars || visible.size == 1) (index + .5f) / visible.size else index.toFloat() / (visible.size - 1)
                    IntOffset((space.width * fraction - child.width / 2).roundToInt().coerceIn(0, (space.width - child.width).coerceAtLeast(0)), 0)
                }), fontSize = 10.sp, color = secondary, maxLines = 1)
            }
        }
        if (hasComparison) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(14.dp).height(3.dp).background(primary)); Text(L("实际"), Modifier.padding(start = 5.dp, end = 16.dp), fontSize = 11.sp, color = secondary)
            Box(Modifier.width(14.dp).height(3.dp).background(secondary)); Text(L("计划"), Modifier.padding(start = 5.dp), fontSize = 11.sp, color = secondary)
        }
    }
}

@Composable
private fun AlertPlot(points: List<ChartPoint>, selected: Int?, onSelect: (Int) -> Unit, modifier: Modifier) {
    if (points.isEmpty()) return
    val values = points.map { point -> point.value?.let { if (abs(it) > 1) it else it * 100 } ?: 0.0 }
    val ticks = alertChartTicks(values)
    val minimum = ticks.first()
    val span = ticks.last() - minimum
    val baseline = MaterialTheme.colorScheme.outline
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val negative = MaterialTheme.colorScheme.error
    val point = selected?.let { points.getOrNull(it) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
                Canvas(Modifier.fillMaxSize().semantics {
                    contentDescription = point?.let { "${it.label}: ${analyticsPercent(it.value, true)}; ${it.detail.orEmpty()}" }
                        ?: points.joinToString("; ") { "${it.label}: ${analyticsPercent(it.value, true)}" }
                    customActions = listOf(-1 to L("上一项"), 1 to L("下一项")).map { (direction, label) ->
                        CustomAccessibilityAction(label) { onSelect(((selected ?: 0) + direction).coerceIn(points.indices)); true }
                    }
                }.pointerInput(points) {
                    detectTapGestures { tap -> onSelect((tap.y / size.height * points.size).toInt().coerceIn(points.indices)) }
                }) {
                    fun x(value: Double) = ((value - minimum) / span * size.width).toFloat()
                    val center = x(0.0)
                    ticks.forEach { value -> drawLine(baseline, Offset(x(value), 0f), Offset(x(value), size.height), 1.dp.toPx()) }
                    drawLine(secondary.copy(alpha = .5f), Offset(center, 0f), Offset(center, size.height), 1.dp.toPx())
                    val rowHeight = size.height / points.size
                    val barHeight = minOf(rowHeight * .35f, 14.dp.toPx())
                    values.forEachIndexed { index, value ->
                        drawLine(baseline, Offset(0f, rowHeight * index), Offset(size.width, rowHeight * index), .5.dp.toPx())
                        val width = abs(x(value) - center)
                        val y = rowHeight * (index + .75f)
                        drawRoundRect(if (value >= 0) Color(0xFF34C759) else negative,
                            Offset(if (value < 0) center - width else center, y - barHeight / 2),
                            Size(width, barHeight), androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()))
                        if (selected == index) drawLine(secondary.copy(alpha = .55f), Offset(0f, y), Offset(size.width, y), 1.dp.toPx())
                    }
                }
                Column(Modifier.fillMaxHeight().widthIn(max = 120.dp)) {
                    points.forEachIndexed { index, item ->
                        Box(Modifier.weight(1f).semantics { this.selected = selected == index }
                            .clickable { onSelect(index) }.padding(start = 4.dp, top = 2.dp)) {
                            Text(if (item.label.length > 8) item.label.take(8) + "…" else item.label,
                                fontSize = 10.sp, lineHeight = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = secondary)
                        }
                    }
                }
                if (point != null) {
                    // Clamp using the measured size, including the user's font scale.
                    ChartTooltip(point.label, listOf(L("偏离 %@", analyticsPercent(point.value, true))) + point.detail.orEmpty().lines(),
                        Modifier.align(object : Alignment {
                            override fun align(size: IntSize, space: IntSize, layoutDirection: LayoutDirection) = IntOffset(
                                (space.width - size.width) / 2,
                                chartTooltipTop(space.height, size.height, selected, points.size),
                            )
                        }))
                }
        }
        Box(Modifier.fillMaxWidth()) {
            ticks.forEachIndexed { index, value ->
                Text(String.format(com.blackwave.crest.ui.localization.AppLocalization.locale, "%.0f", value),
                    Modifier.align(object : Alignment {
                        override fun align(size: IntSize, space: IntSize, layoutDirection: LayoutDirection) = IntOffset(
                            (space.width * index / (ticks.size - 1) - size.width / 2).coerceIn(0, (space.width - size.width).coerceAtLeast(0)), 0,
                        )
                    }), fontSize = 10.sp, color = secondary)
            }
        }
    }
}

@Composable
private fun ChartTooltip(title: String, rows: List<String>, modifier: Modifier = Modifier) {
    Surface(modifier.widthIn(max = 230.dp), shape = RoundedCornerShape(6.dp), color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), shadowElevation = 4.dp) {
        Column(Modifier.padding(horizontal = 8.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            rows.forEach { Text(it, fontSize = 11.sp, lineHeight = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}
