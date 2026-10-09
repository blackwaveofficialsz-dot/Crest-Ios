package com.blackwave.crest.feature.analytics

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

/** Only the dashboard uses a padded range; the other iOS charts include zero. */
internal fun chartDomain(values: List<Double>, includeZero: Boolean): ClosedFloatingPointRange<Double> {
    val finite = values.filter { it.isFinite() }
    if (finite.isEmpty()) return 0.0..1.0
    val low = finite.min()
    val high = finite.max()
    if (includeZero) {
        val minimum = minOf(0.0, low)
        val maximum = maxOf(0.0, high)
        val span = maximum - minimum
        if (span == 0.0 || !span.isFinite()) return 0.0..1.0
        val target = span / 3
        val magnitude = 10.0.pow(floor(log10(target)))
        val step = listOf(1.0, 2.0, 2.5, 5.0, 10.0).first { it * magnitude >= target } * magnitude
        if (step <= 0 || !step.isFinite()) return minimum..maximum
        return floor(minimum / step) * step..ceil(maximum / step) * step
    }
    val padding = maxOf((high - low) * .18, abs(high) * .02, 1.0)
    val bottom = if (low >= 0) maxOf(0.0, low - padding) else low - padding
    return bottom..maxOf(bottom + 1.0, high + padding)
}

internal fun rankingFraction(value: Double, maximum: Double): Float =
    if (!value.isFinite() || !maximum.isFinite() || maximum <= 0) 0f else (value / maximum).coerceIn(0.0, 1.0).toFloat()

/** Readable ticks inside the padded plot, rather than arbitrary domain endpoints. */
internal fun trendChartTicks(domain: ClosedFloatingPointRange<Double>): List<Double> {
    val span = domain.endInclusive - domain.start
    if (!span.isFinite() || span <= 0) return emptyList()
    val target = span / 3
    val magnitude = 10.0.pow(floor(log10(target)))
    val step = listOf(1.0, 2.0, 2.5, 5.0, 10.0).minBy { abs(it * magnitude - target) } * magnitude
    if (step <= 0 || !step.isFinite()) return emptyList()
    val first = ceil(domain.start / step)
    val last = floor(domain.endInclusive / step)
    return (0..(last - first).toInt().coerceAtMost(64)).map { (first + it) * step }
}

/** Same width-based date-label selection as the iOS trend chart. */
internal fun chartLabelIndices(count: Int, widthDp: Float): List<Int> {
    if (count <= 0) return emptyList()
    val labels = minOf(count, (widthDp / 68).toInt().coerceIn(2, 7))
    if (labels == 1) return listOf(0)
    return (0 until labels).map { (it.toDouble() * (count - 1) / (labels - 1)).roundToInt() }
}

internal fun chartDateLabel(period: String): String = period.takeLast(5).replace('-', '/')

internal fun chartTooltipTop(containerHeight: Int, tooltipHeight: Int, index: Int, count: Int): Int =
    (containerHeight * (index + .5f) / count.coerceAtLeast(1) - tooltipHeight / 2f)
        .toInt().coerceIn(0, (containerHeight - tooltipHeight).coerceAtLeast(0))

/** Zero remains in the domain without forcing positive and negative ranges to be equal. */
internal fun alertChartTicks(values: List<Double>): List<Double> {
    val finite = values.filter { it.isFinite() }
    val low = minOf(0.0, finite.minOrNull() ?: 0.0)
    val high = maxOf(0.0, finite.maxOrNull() ?: 0.0)
    if (high == low || !(high - low).isFinite()) return listOf(-1.0, 0.0, 1.0)
    val targetStep = (high - low) / 3
    val magnitude = 10.0.pow(floor(log10(targetStep)))
    val step = listOf(1.0, 2.5, 5.0, 10.0).first { it * magnitude >= targetStep } * magnitude
    val first = floor(low / step)
    val last = ceil(high / step)
    return (0..(last - first).toInt()).map { (first + it) * step }
}
