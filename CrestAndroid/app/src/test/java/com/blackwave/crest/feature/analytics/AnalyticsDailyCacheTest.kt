package com.blackwave.crest.feature.analytics

import com.blackwave.crest.core.model.AnalyticsChangedDay
import com.blackwave.crest.core.model.AnalyticsDelta
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class AnalyticsDailyCacheTest {
    private val dates = listOf("2026-09-01", "2026-09-02")
    private val now = 100_000L
    private val metadata = AnalyticsDailyMetadata(PRODUCT_DAILY_SCHEMA, "scope-a", "products", "params")
    private fun payload(date: String) = buildJsonObject { put("period", date); put("net_income", 12); put("order_count", 2) }
    private fun changed(date: String, version: String = "v2") = AnalyticsChangedDay(date, version, payload(date))
    private fun previous() = AnalyticsDailyState(dates.associateWith { AnalyticsCachedDay("v1", payload(it), now - 1) })
    private fun productDelta(changed: List<AnalyticsChangedDay> = emptyList(), unchanged: List<String> = emptyList(), deleted: List<String> = emptyList(), reset: Boolean = false, hash: String = "scope-a") =
        AnalyticsDelta(changed, unchanged, deleted, "奶茶", PRODUCT_DAILY_SCHEMA, hash, "products", "params", reset)
    private fun rejected(block: () -> Unit) { assertThrows(IllegalArgumentException::class.java) { block() } }

    @Test fun datesAreInclusiveHandleLeapDaysAndLimit365Days() {
        assertEquals(listOf("2024-02-28", "2024-02-29", "2024-03-01"), analyticsDates("2024-02-28", "2024-03-01"))
        assertEquals(365, analyticsDates("2025-01-01", "2025-12-31").size)
        rejected { analyticsDates("2024-01-01", "2024-12-31") }
        rejected { analyticsDates("2026-09-02", "2026-09-01") }
    }

    @Test fun revenueMergesChangedAndUnchangedVersionsWithoutRenewingOldDays() {
        val result = mergeAnalyticsDays(previous(), AnalyticsDelta(listOf(changed(dates[1])), listOf(dates[0])), dates, false, now)
        assertEquals(dates, result.days.keys.toList())
        assertEquals("v1", result.days.getValue(dates[0]).version)
        assertEquals("v2", result.days.getValue(dates[1]).version)
        assertEquals(now - 1, result.days.getValue(dates[0]).savedAt)
        assertEquals(now, result.days.getValue(dates[1]).savedAt)
    }

    @Test fun incompleteDuplicateAndUnrequestedDaysAreRejected() {
        listOf(
            AnalyticsDelta(listOf(changed(dates[0])), emptyList()),
            AnalyticsDelta(listOf(changed(dates[0])), dates),
            AnalyticsDelta(listOf(changed("2026-08-31")), dates),
            AnalyticsDelta(emptyList(), listOf(dates[0], dates[0], dates[1])),
        ).forEach { delta -> rejected { mergeAnalyticsDays(previous(), delta, dates, false, now) } }
        rejected { mergeAnalyticsDays(AnalyticsDailyState(), AnalyticsDelta(emptyList(), dates), dates, false, now) }
    }

    @Test fun deletedOrMismatchedRevenuePayloadNeverProducesPartialSeries() {
        rejected { mergeAnalyticsDays(previous(), AnalyticsDelta(listOf(AnalyticsChangedDay(dates[0], "v2")), listOf(dates[1])), dates, false, now) }
        rejected { mergeAnalyticsDays(previous(), AnalyticsDelta(listOf(changed(dates[0]).copy(payload = payload(dates[1]))), listOf(dates[1])), dates, false, now) }
        rejected { mergeAnalyticsDays(previous(), AnalyticsDelta(listOf(changed(dates[0], "")), listOf(dates[1])), dates, false, now) }
    }

    @Test fun productDeletedDatesAndNameAreApplied() {
        val result = mergeAnalyticsDays(previous().copy(metadata = metadata), productDelta(unchanged = listOf(dates[0]), deleted = listOf(dates[1])), dates, true, now)
        assertEquals(listOf(dates[0]), result.days.keys.toList())
        assertEquals("奶茶", result.productName)
        assertEquals(metadata, result.metadata)
    }

    @Test fun permissionChangeRequiresResetAndResetDropsUnrequestedOldDays() {
        val oldDate = "2026-08-31"
        val old = previous().copy(metadata = metadata, days = previous().days + (oldDate to AnalyticsCachedDay("v1", payload(oldDate), now)))
        rejected { mergeAnalyticsDays(old, productDelta(changed = dates.map { changed(it) }, hash = "scope-b"), dates, true, now) }
        val result = mergeAnalyticsDays(old, productDelta(changed = dates.map { changed(it) }, hash = "scope-b", reset = true), dates, true, now)
        assertEquals(dates, result.days.keys.toList())
        assertEquals("scope-b", result.metadata?.accessScopeHash)
        rejected { mergeAnalyticsDays(old, productDelta(unchanged = dates, reset = true), dates, true, now) }
    }

    @Test fun productSchemaAndRequiredMetadataAreValidated() {
        val valid = productDelta(changed = dates.map { changed(it) })
        listOf(valid.copy(schemaVersion = "v1"), valid.copy(accessScopeHash = ""), valid.copy(namespace = ""),
            valid.copy(paramsHash = ""), valid.copy(resetRequired = null), valid.copy(deletedDays = null),
            valid.copy(changedDays = listOf(changed(dates[0]).copy(payload = null), changed(dates[1]))),
            valid.copy(deletedDays = listOf(dates[0])),
        ).forEach { delta -> rejected { mergeAnalyticsDays(AnalyticsDailyState(), delta, dates, true, now) } }
    }

    @Test fun expiredAndFutureDatedFactsCannotSatisfyUnchangedResponse() {
        val delta = AnalyticsDelta(emptyList(), dates)
        listOf(now - DAILY_CACHE_TTL, now + 1).forEach { timestamp ->
            val old = previous().copy(days = previous().days.mapValues { it.value.copy(savedAt = timestamp) })
            assertTrue(old.validDays(now).isEmpty())
            rejected { mergeAnalyticsDays(old, delta, dates, false, now) }
        }
    }

    @Test fun cacheKeepsAtMost365RecentDays() {
        val start = LocalDate.parse("2025-01-01")
        val old = AnalyticsDailyState((0..364).associate { index ->
            val date = start.plusDays(index.toLong()).toString()
            date to AnalyticsCachedDay("v1", payload(date), now)
        })
        val result = mergeAnalyticsDays(old, AnalyticsDelta(listOf(changed("2026-01-01")), emptyList()), listOf("2026-01-01"), false, now)
        assertEquals(365, result.days.size)
        assertFalse(result.days.containsKey("2025-01-01"))
        assertTrue(result.days.containsKey("2026-01-01"))
    }

    @Test fun requestsUseIosScopesVersionsAndForceRefreshRules() {
        val cached = previous().copy(metadata = metadata)
        val revenue = analyticsDeltaRequest(dates, cached, null, null, false)
        assertEquals("ALL", revenue.getValue("params").jsonObject.getValue("store_key").jsonPrimitive.content)
        assertFalse(revenue.containsKey("schema_version"))
        assertEquals(2, revenue.getValue("client_days").jsonArray.size)
        val product = analyticsDeltaRequest(dates, cached, "shop-a", "tea", false)
        assertEquals("shop", product.getValue("params").jsonObject.getValue("dim_type").jsonPrimitive.content)
        assertEquals("shop-a", product.getValue("params").jsonObject.getValue("dim_key").jsonPrimitive.content)
        assertEquals("tea", product.getValue("params").jsonObject.getValue("product_key").jsonPrimitive.content)
        assertEquals("scope-a", product.getValue("client_access_scope_hash").jsonPrimitive.content)
        val force = analyticsDeltaRequest(dates, cached, null, "tea", true)
        assertTrue(force.getValue("client_days").jsonArray.isEmpty())
        assertFalse(force.containsKey("client_access_scope_hash"))
        assertTrue(force.getValue("force_refresh").jsonPrimitive.boolean)
        assertEquals("all", force.getValue("params").jsonObject.getValue("dim_type").jsonPrimitive.content)
    }
}
