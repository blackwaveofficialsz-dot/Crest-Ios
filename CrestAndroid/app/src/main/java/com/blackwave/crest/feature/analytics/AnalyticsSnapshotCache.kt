package com.blackwave.crest.feature.analytics

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** App-private, encrypted snapshots and daily facts, isolated by user/workspace/filter. */
internal class AnalyticsSnapshotCache(context: Context) {
    private val directory = File(context.cacheDir, "analytics-snapshots")
    private val lock = Any()
    private val json = Json { ignoreUnknownKeys = true }
    private var generation = 0L

    fun generation(): Long = synchronized(lock) { generation }

    @Serializable
    data class Snapshot(val savedAt: Long, val value: AnalyticsData) {
        fun isFresh(now: Long = System.currentTimeMillis()) = now - savedAt in 0 until 5 * 60_000
        fun isValid(now: Long = System.currentTimeMillis()) = now - savedAt in 0 until 30L * 24 * 60 * 60_000
    }

    suspend fun read(scope: String): Snapshot? = withContext(Dispatchers.IO) {
        synchronized(lock) {
            runCatching { json.decodeFromString<Snapshot>(readText(scope, false)).takeIf { it.isValid() } }.getOrNull()
        }
    }

    suspend fun readDaily(scope: String): AnalyticsDailyState? = withContext(Dispatchers.IO) {
        synchronized(lock) {
            runCatching { json.decodeFromString<AnalyticsDailyState>(readText(scope, true)).let { it.copy(days = it.validDays(System.currentTimeMillis())) } }.getOrNull()
        }
    }

    suspend fun write(scope: String, data: AnalyticsData, expectedGeneration: Long, savedAt: Long = System.currentTimeMillis()) =
        writeText(scope, json.encodeToString(Snapshot(savedAt, data)), false, expectedGeneration)

    suspend fun writeDaily(scope: String, data: AnalyticsDailyState, expectedGeneration: Long) =
        writeText(scope, json.encodeToString(data), true, expectedGeneration)

    suspend fun remove(scope: String, daily: Boolean = false) = withContext(Dispatchers.IO) { synchronized(lock) { AtomicFile(file(scope, daily)).delete() } }

    fun clear() = synchronized(lock) { generation++; directory.listFiles()?.forEach { it.delete() }; Unit }

    private fun readText(scope: String, daily: Boolean): String {
        val bytes = AtomicFile(file(scope, daily)).readFully()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD((if (daily) "daily:$scope" else scope).toByteArray())
        return cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
    }

    private suspend fun writeText(scope: String, value: String, daily: Boolean, expectedGeneration: Long) = withContext(Dispatchers.IO) {
        val coroutine = currentCoroutineContext()
        synchronized(lock) {
            coroutine.ensureActive()
            // A response already in flight must not recreate a cache cleared by sign-out.
            if (generation == expectedGeneration) runCatching {
                directory.mkdirs()
                val now = System.currentTimeMillis()
                directory.listFiles()?.filter {
                    now - it.lastModified() > if (it.name.startsWith("daily_")) DAILY_CACHE_TTL else 30L * 24 * 60 * 60_000
                }?.forEach { it.delete() }
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key())
                cipher.updateAAD((if (daily) "daily:$scope" else scope).toByteArray())
                val bytes = cipher.iv + cipher.doFinal(value.toByteArray())
                val target = AtomicFile(file(scope, daily))
                val stream = target.startWrite()
                try { stream.write(bytes); target.finishWrite(stream) }
                catch (error: Exception) { target.failWrite(stream); throw error }
            }
            Unit // Caching must never prevent a successful server response from displaying.
        }
    }

    private fun file(scope: String, daily: Boolean): File = File(directory, (if (daily) "daily_" else "") + MessageDigest.getInstance("SHA-256").digest(scope.toByteArray()).joinToString("") { "%02x".format(it) })

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("crest_analytics_cache_v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("crest_analytics_cache_v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
}
