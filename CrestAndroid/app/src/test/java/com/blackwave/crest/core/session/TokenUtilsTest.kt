package com.blackwave.crest.core.session

import java.util.Base64
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TokenUtilsTest {
    @Test
    fun tokenExpiringInsideWindowNeedsRefresh() {
        val token = tokenWithExpiry(1_500)

        assertTrue(jwtExpiresWithin(token, seconds = 600, nowEpochSeconds = 1_000))
    }

    @Test
    fun tokenOutsideWindowCanBeReused() {
        val token = tokenWithExpiry(2_000)

        assertFalse(jwtExpiresWithin(token, seconds = 600, nowEpochSeconds = 1_000))
    }

    @Test
    fun malformedTokenNeedsRefresh() {
        assertTrue(jwtExpiresWithin("not-a-jwt", seconds = 600, nowEpochSeconds = 1_000))
    }

    private fun tokenWithExpiry(expiry: Long): String {
        val payload = Base64.getUrlEncoder().withoutPadding()
            .encodeToString("{\"exp\":$expiry}".toByteArray())
        return "header.$payload.signature"
    }
}
