package com.blackwave.crest.feature.analytics

import org.junit.Assert.*
import org.junit.Test

class ChartGeometryTest {
    @Test fun trendTicksUseReadableValuesWithinPaddedRevenueDomain() {
        assertEquals(listOf(70000.0, 80000.0, 90000.0, 100000.0), trendChartTicks(67000.0..101000.0))
        assertEquals(listOf(-50.0, 0.0, 50.0), trendChartTicks(-80.0..80.0))
        assertTrue(trendChartTicks(1.0..1.0).isEmpty())
        assertTrue(trendChartTicks(0.0..Double.POSITIVE_INFINITY).isEmpty())
    }

    @Test fun dateLabelsFollowIosWidthRuleAndIncludeBothEndsWithoutDuplicates() {
        assertEquals(emptyList<Int>(), chartLabelIndices(0, 300f))
        assertEquals(listOf(0), chartLabelIndices(1, 300f))
        assertEquals(listOf(0, 2, 4, 6), chartLabelIndices(7, 300f))
        assertEquals(listOf(0, 6), chartLabelIndices(7, 68f))
        assertEquals(7, chartLabelIndices(31, 900f).size)
        assertEquals(30, chartLabelIndices(31, 900f).last())
        assertEquals(listOf(0, 1), chartLabelIndices(2, 900f))
    }
    @Test fun nativeAreaAndBarChartsUseZeroAndReadableOuterBounds() {
        assertEquals(0.0..20000.0, chartDomain(listOf(9180.0, 15028.0), true))
        assertEquals(0.0..6000.0, chartDomain(listOf(4200.0, 5910.0), true))
        assertEquals(0.0..100.0, chartDomain(listOf(75.0, 99.0), true))
        val hours = chartDomain(listOf(931.5, 1043.4), true)
        assertEquals(0.0..1500.0, hours)
        assertEquals(listOf(0.0, 500.0, 1000.0, 1500.0), trendChartTicks(hours))
        assertEquals(0.0..1.0, chartDomain(listOf(0.0, 0.0), true))
        assertTrue(-20.0 in chartDomain(listOf(-20.0, 15.0), true))
    }

    @Test fun datesMatchIosShortLabels() {
        assertEquals("10/07", chartDateLabel("2026-10-07"))
        assertEquals("10/07", chartDateLabel("10/07"))
        assertEquals("", chartDateLabel(""))
    }

    @Test fun emptyAndConstantDomainsHaveUsableHeight() {
        assertEquals(0.0..1.0, chartDomain(emptyList(), false))
        assertEquals(0.0..1.0, chartDomain(listOf(Double.NaN), false))
        listOf(0.0, 42.0, -42.0).forEach { value ->
            val domain = chartDomain(listOf(value, value), false)
            assertTrue(domain.endInclusive > domain.start)
            assertTrue(value in domain)
        }
    }
    @Test fun linesUsePaddedDataRangeAndBarsIncludeZero() {
        val line = chartDomain(listOf(100.0, 200.0), false)
        assertEquals(82.0, line.start, .001)
        assertEquals(218.0, line.endInclusive, .001)
        assertEquals(0.0, chartDomain(listOf(100.0, 200.0), true).start, .001)
        assertTrue(-10.0 in chartDomain(listOf(-10.0, 5.0), true))
        assertTrue(0.0 in chartDomain(listOf(-100.0, -50.0), true))
    }
    @Test fun rankingBarsClampMissingNegativeAndOversizedValues() {
        assertEquals(0f, rankingFraction(10.0, 0.0))
        assertEquals(0f, rankingFraction(Double.NaN, 20.0))
        assertEquals(0f, rankingFraction(-1.0, 20.0))
        assertEquals(.5f, rankingFraction(10.0, 20.0))
        assertEquals(1f, rankingFraction(30.0, 20.0))
    }

    @Test fun tooltipFollowsSelectedRowAndStaysInsideBothEdges() {
        assertEquals(0, chartTooltipTop(300, 96, 0, 7))
        assertEquals(102, chartTooltipTop(300, 96, 3, 7))
        assertEquals(204, chartTooltipTop(300, 96, 6, 7))
    }

    @Test fun tooltipUsesMeasuredHeightForLargeFontsAndShortLandscapePlots() {
        assertEquals(0, chartTooltipTop(300, 168, 0, 7))
        assertEquals(132, chartTooltipTop(300, 168, 6, 7))
        assertEquals(0, chartTooltipTop(80, 168, 6, 7))
        assertEquals(0, chartTooltipTop(0, 0, 0, 0))
    }

    @Test fun alertAxisUsesAsymmetricNiceTicksLikeIosInsteadOfCenteringZero() {
        assertEquals(listOf(-50.0, -25.0, 0.0, 25.0), alertChartTicks(listOf(-33.7, -26.7, 23.6, 21.3)))
        assertEquals(listOf(-25.0, 0.0, 25.0, 50.0), alertChartTicks(listOf(-21.3, 33.7)))
    }

    @Test fun alertAxisIncludesZeroAndAllValuesForOneSidedOrEmptyData() {
        listOf(listOf(12.0, 20.0), listOf(-12.0, -20.0), listOf(0.0), emptyList()).forEach { values ->
            val ticks = alertChartTicks(values)
            assertTrue(ticks.last() > ticks.first())
            assertTrue(0.0 in ticks)
            assertTrue(values.all { it in ticks.first()..ticks.last() })
        }
        assertEquals(listOf(-1.0, 0.0, 1.0), alertChartTicks(listOf(Double.NaN)))
    }
}
