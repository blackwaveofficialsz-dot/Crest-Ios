package com.blackwave.crest.core.network

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AvatarUploadTest {
    @Test
    fun sendsIosCompatibleMultipartRequest() = runBlocking {
        var sentRequest: Request? = null
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            sentRequest = request
            Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body("""{"user_id":"user-1","username":"tester","display_name":"Tester","has_avatar":true}""".toResponseBody("application/json".toMediaType()))
                .build()
        }.build()

        val profile = ApiClient(client, "https://example.test/").uploadAccountAvatar(byteArrayOf(1, 2, 3), "test-token")

        val request = requireNotNull(sentRequest)
        assertEquals("PUT", request.method)
        assertEquals("/api/v1/auth/profile/avatar", request.url.encodedPath)
        assertEquals("Bearer test-token", request.header("Authorization"))
        assertTrue(request.body?.contentType().toString().startsWith("multipart/form-data; boundary="))
        val multipart = request.body as okhttp3.MultipartBody
        assertEquals(1, multipart.parts.size)
        assertEquals("form-data; name=\"file\"; filename=\"avatar.jpg\"", multipart.parts[0].headers?.get("Content-Disposition"))
        assertEquals("image/jpeg", multipart.parts[0].body.contentType().toString())
        assertTrue(profile.hasAvatar)
        assertEquals("Tester", profile.displayName)
    }
}
