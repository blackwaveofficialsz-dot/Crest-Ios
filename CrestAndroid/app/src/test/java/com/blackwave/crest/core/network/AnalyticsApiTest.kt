package com.blackwave.crest.core.network

import kotlinx.coroutines.runBlocking
import com.blackwave.crest.feature.analytics.AnalyticsDailyState
import com.blackwave.crest.feature.analytics.analyticsDeltaRequest
import kotlinx.serialization.json.Json
import okhttp3.RequestBody
import okio.Buffer
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class AnalyticsApiTest {
    private val requests = mutableListOf<Request>()
    private val api = ApiClient(OkHttpClient.Builder().addInterceptor { chain ->
        val request = chain.request().also { requests += it }
        val payload = when (request.url.encodedPath.substringAfterLast('/')) {
            "store-scope-tree" -> """{"nodes":[],"store_count":0}"""
            "products" -> """{"data_status":"empty","items":[],"total":0}"""
            "labor" -> """{"data_status":"empty","points":[],"summary":{"actual_hours":0,"planned_hours":0,"net_revenue":0,"headcount":0}}"""
            "revenue-alerts" -> """{"alerts":[]}"""
            "trend" -> """{"product_key":"tea","points":[]}"""
            "delta" -> """{"changed_days":[],"unchanged_days":[],"deleted_days":[],"schema_version":"product-daily-fact-v2","access_scope_hash":"scope","namespace":"products","params_hash":"params","reset_required":false}"""
            else -> """{"points":[]}"""
        }
        Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
            .body(payload.toResponseBody("application/json".toMediaType())).build()
    }.build(), "https://example.test/")

    @Test fun periodRequestsMatchIosContract() = runBlocking {
        api.analyticsProducts("2026-09-01", "2026-09-30", listOf("b", "a", "b"), "test-token")
        val request = requests.last()
        assertEquals("/api/v1/analytics/operations/products", request.url.encodedPath)
        assertEquals(listOf("a", "b"), request.url.queryParameterValues("store_keys"))
        assertEquals("previous", request.url.queryParameter("compare"))
        assertEquals("day", request.url.queryParameter("granularity"))
        assertEquals("30", request.url.queryParameter("limit"))
        assertEquals("2026-09-01", request.url.queryParameter("date_from"))
        assertEquals("2026-09-30", request.url.queryParameter("date_to"))
        assertEquals("Bearer test-token", request.header("Authorization"))
    }

    @Test fun productTrendUsesShopOnlyForSingleStore() = runBlocking {
        api.analyticsProductTrend("tea", "2026-09-01", "2026-09-30", listOf("a"), "test-token")
        assertEquals("shop", requests.last().url.queryParameter("dim_type"))
        assertEquals("a", requests.last().url.queryParameter("dim_key"))
        api.analyticsProductTrend("tea", "2026-09-01", "2026-09-30", listOf("a", "b"), "test-token")
        assertEquals("all", requests.last().url.queryParameter("dim_type"))
        assertEquals("ALL", requests.last().url.queryParameter("dim_key"))
        assertEquals("false", requests.last().url.queryParameter("include_current"))
    }

    @Test fun otherAnalyticsEndpointsDecodeEmptyStates() = runBlocking {
        assertTrue(api.analyticsStoreScope("test-token").nodes.isEmpty())
        assertEquals("empty", api.analyticsLabor("2026-09-01", "2026-09-30", emptyList(), "test-token").dataStatus)
        assertTrue(api.analyticsAlerts("2026-09-30", "test-token").alerts.isEmpty())
        assertEquals("2026-09-30", requests.last().url.queryParameter("business_date"))
        assertTrue(api.analyticsRevenueTrend("2026-09-01", "2026-09-30", emptyList(), "test-token").points.isEmpty())
        assertEquals("ALL", requests.last().url.queryParameter("store_key"))
        assertEquals("all", requests.last().url.queryParameter("source_type"))
        assertTrue(requests.all { it.method == "GET" })
    }

    @Test fun deltaRequestsPostIosProtocolBodies() = runBlocking {
        val dates = listOf("2026-09-01")
        val revenue = analyticsDeltaRequest(dates, AnalyticsDailyState(), null, null, false)
        assertTrue(api.analyticsRevenueDelta(revenue, "test-token").changedDays.isEmpty())
        assertEquals("/api/v1/analytics/trends/revenue/delta", requests.last().url.encodedPath)
        assertEquals(revenue, Json.parseToJsonElement(requests.last().body!!.text()))
        val product = analyticsDeltaRequest(dates, AnalyticsDailyState(), "shop-a", "tea", true)
        assertEquals("scope", api.analyticsProductDelta(product, "test-token").accessScopeHash)
        assertEquals("/api/v1/analytics/products/trend/delta", requests.last().url.encodedPath)
        assertEquals(product, Json.parseToJsonElement(requests.last().body!!.text()))
        assertTrue(requests.all { it.method == "POST" && it.header("Authorization") == "Bearer test-token" })
    }

    private fun RequestBody.text() = Buffer().also { writeTo(it) }.readUtf8()
}
