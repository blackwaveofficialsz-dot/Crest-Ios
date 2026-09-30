package com.blackwave.crest.core.session

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.util.Base64

internal fun jwtExpiresWithin(
    token: String,
    seconds: Long,
    nowEpochSeconds: Long = System.currentTimeMillis() / 1_000,
): Boolean {
    val payload = token.split('.').getOrNull(1) ?: return true
    val decoded = runCatching { String(Base64.getUrlDecoder().decode(payload), Charsets.UTF_8) }.getOrNull()
        ?: return true
    val expiresAt = runCatching {
        Json.parseToJsonElement(decoded).jsonObject["exp"]?.jsonPrimitive?.longOrNull
    }.getOrNull() ?: return true
    return expiresAt <= nowEpochSeconds + seconds
}
