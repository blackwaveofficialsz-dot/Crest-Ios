package com.blackwave.crest.feature.analytics

import com.blackwave.crest.core.model.AnalyticsProductPoint
import com.blackwave.crest.core.model.AnalyticsProductTrend
import com.blackwave.crest.core.model.AnalyticsRevenuePoint
import com.blackwave.crest.core.model.AnalyticsRevenueTrend
import com.blackwave.crest.core.network.ApiException
import com.blackwave.crest.core.session.SessionStore
import com.blackwave.crest.core.session.SessionUser
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement

internal suspend fun SessionStore.loadRevenueTrend(user: SessionUser, from: String, to: String, stores: List<String>, refresh: Boolean): AnalyticsRevenueTrend =
    loadDailyTrend(user, from, to, stores, null, refresh,
        full = { authenticated { api.analyticsRevenueTrend(from, to, stores, it) } },
        decode = { dates, state -> AnalyticsRevenueTrend(dates.map { api.json.decodeFromJsonElement<AnalyticsRevenuePoint>(state.days.getValue(it).payload) }) })

internal suspend fun SessionStore.loadProductTrend(user: SessionUser, product: String, from: String, to: String, stores: List<String>, refresh: Boolean): AnalyticsProductTrend =
    loadDailyTrend(user, from, to, stores, product, refresh,
        full = { authenticated { api.analyticsProductTrend(product, from, to, stores, it) } },
        decode = { dates, state -> AnalyticsProductTrend(product, state.productName, dates.mapNotNull { date ->
            state.days[date]?.let { api.json.decodeFromJsonElement<AnalyticsProductPoint>(it.payload) }
        }) })

/** Daily versions apply only to ALL or one store; multi-store keeps the existing full API. */
private suspend fun <T> SessionStore.loadDailyTrend(
    user: SessionUser, from: String, to: String, stores: List<String>, product: String?, refresh: Boolean,
    full: suspend () -> T, decode: (List<String>, AnalyticsDailyState) -> T,
): T {
    val keys = stores.distinct()
    if (keys.size > 1) return full()
    val generation = analyticsCache.generation()
    val scope = JsonArray(listOf(user.userId, user.activeWorkspaceId,
        if (product == null) "revenue-daily-v1" else PRODUCT_DAILY_SCHEMA,
        if (keys.isEmpty()) "all" else "shop", keys.singleOrNull() ?: "ALL", product ?: "all").map(::JsonPrimitive)).toString()
    try {
        val dates = analyticsDates(from, to)
        var previous = if (refresh) null else analyticsCache.readDaily(scope)
        if (refresh || product != null && previous?.metadata.let { it == null || it.schemaVersion != PRODUCT_DAILY_SCHEMA || it.accessScopeHash.isBlank() }) {
            analyticsCache.remove(scope, daily = true)
            previous = null
        }
        val state = previous ?: AnalyticsDailyState()
        val request = analyticsDeltaRequest(dates, state, keys.singleOrNull(), product, refresh)
        val delta = authenticated { token ->
            if (product == null) api.analyticsRevenueDelta(request, token) else api.analyticsProductDelta(request, token)
        }
        val merged = mergeAnalyticsDays(state, delta, dates, product != null, System.currentTimeMillis())
        // Validate typed payloads before committing either facts or access-scope metadata.
        val result = decode(dates, merged)
        analyticsCache.writeDaily(scope, merged, generation)
        return result
    } catch (cancel: CancellationException) {
        throw cancel
    } catch (failure: Exception) {
        if (failure is ApiException && failure.statusCode in listOf(401, 403)) throw failure
        return full()
    }
}
