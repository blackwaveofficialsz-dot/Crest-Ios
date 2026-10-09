package com.blackwave.crest.feature.analytics

import com.blackwave.crest.core.model.AnalyticsDelta
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.time.LocalDate
import java.time.temporal.ChronoUnit

internal const val PRODUCT_DAILY_SCHEMA = "product-daily-fact-v2"
internal const val DAILY_CACHE_TTL = 365L * 24 * 60 * 60_000

@Serializable
internal data class AnalyticsDailyMetadata(val schemaVersion: String, val accessScopeHash: String, val namespace: String, val paramsHash: String)

@Serializable
internal data class AnalyticsCachedDay(val version: String, val payload: JsonObject, val savedAt: Long)

@Serializable
internal data class AnalyticsDailyState(
    val days: Map<String, AnalyticsCachedDay> = emptyMap(),
    val metadata: AnalyticsDailyMetadata? = null,
    val productName: String? = null,
) {
    fun validDays(now: Long) = days.filterValues { now - it.savedAt in 0 until DAILY_CACHE_TTL }
}

internal fun analyticsDates(from: String, to: String): List<String> {
    val first = LocalDate.parse(from)
    val count = ChronoUnit.DAYS.between(first, LocalDate.parse(to)) + 1
    require(count in 1..365) { "经营分析日期范围无效" }
    return (0 until count).map { first.plusDays(it).toString() }
}

internal fun analyticsDeltaRequest(dates: List<String>, state: AnalyticsDailyState, store: String?, product: String?, refresh: Boolean): JsonObject = buildJsonObject {
    put("date_from", dates.first())
    put("date_to", dates.last())
    put("force_refresh", refresh)
    putJsonArray("client_days") {
        if (!refresh) dates.forEach { date -> state.days[date]?.let { entry -> add(buildJsonObject { put("date", date); put("version", entry.version) }) } }
    }
    putJsonObject("params") {
        if (product == null) { put("store_key", store ?: "ALL"); put("source_type", "all") }
        else { put("dim_key", store ?: "ALL"); put("dim_type", if (store == null) "all" else "shop"); put("product_key", product) }
    }
    if (product != null) {
        put("schema_version", PRODUCT_DAILY_SCHEMA)
        if (!refresh) state.metadata?.accessScopeHash?.let { put("client_access_scope_hash", it) }
    }
}

/** Validate the complete response before publishing any day or access metadata. */
internal fun mergeAnalyticsDays(previous: AnalyticsDailyState, delta: AnalyticsDelta, dates: List<String>, product: Boolean, now: Long): AnalyticsDailyState {
    val expected = dates.toSet()
    val existing = previous.validDays(now)
    val resolved = mutableSetOf<String>()
    fun resolve(date: String) { require(date in expected && resolved.add(date)) { "经营分析增量协议无效" } }
    val reset = delta.resetRequired == true
    val metadata = if (product) {
        require(delta.schemaVersion == PRODUCT_DAILY_SCHEMA && delta.resetRequired != null && delta.deletedDays != null &&
            !delta.accessScopeHash.isNullOrEmpty() && !delta.namespace.isNullOrEmpty() && !delta.paramsHash.isNullOrEmpty()) { "经营分析 V2 增量协议无效" }
        val next = AnalyticsDailyMetadata(delta.schemaVersion, delta.accessScopeHash, delta.namespace, delta.paramsHash)
        require(previous.metadata == null || previous.metadata.accessScopeHash == next.accessScopeHash || reset) { "经营分析数据权限范围已变化" }
        next
    } else null
    delta.changedDays.forEach { day ->
        resolve(day.date)
        require(day.version.isNotBlank()) { "经营分析日版本无效" }
        if (product) require(day.payload != null) { "经营分析 V2 日数据无效" }
        day.payload?.let { require(it["period"]?.jsonPrimitive?.content == day.date) { "经营分析日数据日期不一致" } }
    }
    delta.unchangedDays.forEach { date ->
        resolve(date)
        require(!reset && date in existing) { "经营分析日缓存不完整" }
    }
    val deleted = delta.deletedDays.orEmpty()
    require(product || deleted.isEmpty()) { "经营分析增量协议无效" }
    deleted.forEach(::resolve)
    require(resolved == expected) { "经营分析日缓存不完整" }
    val merged = (if (reset) emptyMap() else existing).toMutableMap()
    delta.changedDays.forEach { day ->
        if (day.payload == null) merged.remove(day.date)
        else merged[day.date] = AnalyticsCachedDay(day.version, day.payload, now)
    }
    deleted.forEach(merged::remove)
    require(dates.all { it in merged || product && it in deleted }) { "经营分析日缓存不完整" }
    return AnalyticsDailyState(merged.toSortedMap().toList().takeLast(365).toMap(), metadata, delta.productName ?: previous.productName)
}
