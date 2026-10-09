package com.blackwave.crest.feature.analytics

import com.blackwave.crest.core.model.AnalyticsStoreNode
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.util.Locale
import com.blackwave.crest.ui.localization.AppLocalization

class AnalyticsDataTest {
    @Test fun presetsExcludeTodayIncludingFirstOfMonthAndLeapYear() {
        val today = LocalDate.parse("2024-03-01")
        assertEquals(AnalyticsRange(LocalDate.parse("2024-02-01"), LocalDate.parse("2024-02-29")), AnalyticsPeriod.CURRENT_MONTH.range(today))
        assertEquals(AnalyticsRange(LocalDate.parse("2024-01-01"), LocalDate.parse("2024-01-31")), AnalyticsPeriod.PREVIOUS_MONTH.range(today))
        assertEquals(LocalDate.parse("2024-02-23"), AnalyticsPeriod.LAST_SEVEN_DAYS.range(today).from)
        assertEquals(LocalDate.parse("2024-02-29"), AnalyticsPeriod.YESTERDAY.range(today).from)
    }

    @Test fun storeTreeKeepsAuthorizedLeaves() {
        val tree = AnalyticsStoreNode("region", "region", "地区", children = listOf(AnalyticsStoreNode("shop", "shop", "一店", "s1")))
        assertEquals(listOf("s1" to "一店"), tree.stores())
    }

    @Test fun csvEscapesLabelsAndNeutralizesFormulasWithoutChangingNumbers() {
        val csv = analyticsCsv(listOf(listOf("=SUM(A1)", "a,\"b\"", "-12.5", "a\nb"))).toString(Charsets.UTF_8)
        assertEquals("\uFEFF\"'=SUM(A1)\",\"a,\"\"b\"\"\",\"-12.5\",\"a\nb\"", csv)
    }

    @Test fun snapshotFreshnessAndExpiryMatchIosAndRejectFutureTimestamps() {
        val snapshot = AnalyticsSnapshotCache.Snapshot(1000, AnalyticsData())
        assertTrue(snapshot.isFresh(1000 + 299_999))
        assertFalse(snapshot.isFresh(1000 + 300_000))
        assertTrue(snapshot.isValid(1000 + 29L * 24 * 60 * 60_000))
        assertFalse(snapshot.isValid(1000 + 30L * 24 * 60 * 60_000))
        assertFalse(snapshot.isFresh(999))
    }

    @Test fun revenueCompactCurrencyMatchesIosChineseThresholds() {
        val previous = AppLocalization.systemLocale
        try {
            AppLocalization.systemLocale = Locale.SIMPLIFIED_CHINESE
            assertEquals("—", analyticsCompactCurrency(null))
            assertEquals("¥0", analyticsCompactCurrency(0.0))
            assertEquals("¥999", analyticsCompactCurrency(999.0))
            assertEquals("¥1k", analyticsCompactCurrency(1_000.0))
            assertEquals("¥10k", analyticsCompactCurrency(9_999.0))
            assertEquals("¥1.0万", analyticsCompactCurrency(10_000.0))
            assertEquals("¥8.9万", analyticsCompactCurrency(89_000.0))
            assertEquals("¥10万", analyticsCompactCurrency(100_000.0))
            assertEquals("¥-8.9万", analyticsCompactCurrency(-89_000.0))
            assertEquals("¥89,000", analyticsCurrency(89_000.0)) // Detail and KPI remain unabridged.
        } finally { AppLocalization.systemLocale = previous }
    }

    @Test fun revenueCompactCurrencyUsesThousandsInEnglish() {
        val previous = AppLocalization.systemLocale
        try {
            AppLocalization.systemLocale = Locale.ENGLISH
            assertEquals("¥89k", analyticsCompactCurrency(89_000.0))
            assertEquals("¥-89k", analyticsCompactCurrency(-89_000.0))
            assertEquals("¥1,000k", analyticsCompactCurrency(1_000_000.0))
        } finally { AppLocalization.systemLocale = previous }
    }
}
