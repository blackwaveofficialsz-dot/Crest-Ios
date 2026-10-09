package com.blackwave.crest.feature.analytics

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/** Uses the device's real Keystore, but never reads or clears the user's cache. */
@RunWith(AndroidJUnit4::class)
class AnalyticsSnapshotCacheDeviceTest {
    private lateinit var root: File
    private lateinit var context: Context
    private lateinit var cache: AnalyticsSnapshotCache

    @Before fun setUp() {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        root = File(target.cacheDir, "analytics-device-test-${UUID.randomUUID()}")
        context = object : ContextWrapper(target) { override fun getCacheDir() = root }
        cache = AnalyticsSnapshotCache(context)
    }

    @After fun tearDown() { root.deleteRecursively() }

    @Test fun encryptedSnapshotAndDailyFactsSurviveReopening() = runBlocking {
        val scope = "test-user/test-workspace/test-filter"
        val daily = dailyState()
        cache.write(scope, AnalyticsData(), cache.generation())
        cache.writeDaily(scope, daily, cache.generation())

        val reopened = AnalyticsSnapshotCache(context)
        assertEquals(AnalyticsData(), reopened.read(scope)?.value)
        assertEquals(daily, reopened.readDaily(scope))
        val files = File(root, "analytics-snapshots").listFiles().orEmpty()
        assertEquals(2, files.size)
        files.forEach {
            val bytes = it.readBytes()
            assertTrue(bytes.size > 28) // 12-byte IV + authenticated ciphertext.
            assertFalse(bytes.toString(Charsets.UTF_8).contains("cache-test-sensitive-label"))
            assertFalse(it.name.contains("test-user"))
        }
    }

    @Test fun scopesAreIsolatedAndCiphertextCannotBeMovedBetweenScopes() = runBlocking {
        cache.write("user-a/workspace-a", AnalyticsData(), cache.generation())
        assertNull(cache.read("user-b/workspace-a"))
        assertNull(cache.read("user-a/workspace-b"))
        val directory = File(root, "analytics-snapshots")
        directory.listFiles()!!.single().copyTo(File(directory, hash("user-b/workspace-a")))
        assertNull(cache.read("user-b/workspace-a")) // AAD rejects even a renamed valid file.
    }

    @Test fun expiredAndFutureDatedSnapshotsAreRejected() = runBlocking {
        val now = System.currentTimeMillis()
        cache.write("expired", AnalyticsData(), cache.generation(), now - 31L * 24 * 60 * 60_000)
        cache.write("future", AnalyticsData(), cache.generation(), now + 24 * 60 * 60_000)
        cache.write("stale", AnalyticsData(), cache.generation(), now - 6 * 60_000)
        assertNull(cache.read("expired"))
        assertNull(cache.read("future"))
        assertNotNull(cache.read("stale"))
        assertFalse(cache.read("stale")!!.isFresh())
    }

    @Test fun expiredAndFutureDailyFactsArePrunedOnDevice() = runBlocking {
        val valid = dailyState()
        val entry = valid.days.values.single()
        val state = valid.copy(days = valid.days + mapOf(
            "expired" to entry.copy(savedAt = System.currentTimeMillis() - DAILY_CACHE_TTL - 1_000),
            "future" to entry.copy(savedAt = System.currentTimeMillis() + 60_000),
        ))
        cache.writeDaily("daily", state, cache.generation())
        assertEquals(valid, cache.readDaily("daily"))
    }

    @Test fun clearedCacheCannotBeRecreatedByAnInFlightResponse() = runBlocking {
        val generation = cache.generation()
        cache.write("before", AnalyticsData(), generation)
        cache.writeDaily("before", dailyState(), generation)
        val responseReady = CompletableDeferred<Unit>()
        val pending = async {
            responseReady.await()
            cache.write("late", AnalyticsData(), generation)
            cache.writeDaily("late", dailyState(), generation)
        }
        cache.clear()
        responseReady.complete(Unit)
        pending.await()
        assertNull(cache.read("before"))
        assertNull(cache.readDaily("before"))
        assertNull(cache.read("late"))
        assertNull(cache.readDaily("late"))
        assertEquals(0, File(root, "analytics-snapshots").listFiles().orEmpty().size)
        cache.write("new-session", AnalyticsData(), cache.generation())
        assertNotNull(cache.read("new-session"))
    }

    @Test fun corruptCacheFallsBackWithoutThrowing() = runBlocking {
        cache.write("corrupt", AnalyticsData(), cache.generation())
        val target = File(root, "analytics-snapshots").listFiles()!!.single()
        val bytes = target.readBytes()
        bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
        target.writeBytes(bytes)
        assertNull(cache.read("corrupt"))
        cache.write("corrupt", AnalyticsData(), cache.generation())
        assertNotNull(cache.read("corrupt"))
    }

    private fun dailyState() = AnalyticsDailyState(
        days = mapOf("2026-10-01" to AnalyticsCachedDay("version-1", buildJsonObject {
            put("period", "2026-10-01")
            put("label", "cache-test-sensitive-label")
        }, System.currentTimeMillis())),
        metadata = AnalyticsDailyMetadata(PRODUCT_DAILY_SCHEMA, "access", "namespace", "params"),
        productName = "cache-test-sensitive-label",
    )

    private fun hash(value: String) = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
}
