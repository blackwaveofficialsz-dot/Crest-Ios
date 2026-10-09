package com.blackwave.crest.core.network

import com.blackwave.crest.core.model.AnalyticsStoreScope
import com.blackwave.crest.core.model.AnalyticsRevenueTrend
import com.blackwave.crest.core.model.AnalyticsProducts
import com.blackwave.crest.core.model.AnalyticsProductTrend
import com.blackwave.crest.core.model.AnalyticsLabor
import com.blackwave.crest.core.model.AnalyticsAlerts

import com.blackwave.crest.BuildConfig
import com.blackwave.crest.core.model.ChatAgentResponse
import com.blackwave.crest.core.model.AcceptInvitationResponse
import com.blackwave.crest.core.model.AccountProfile
import com.blackwave.crest.core.model.AnalyticsOverview
import com.blackwave.crest.core.model.ChatApproval
import com.blackwave.crest.core.model.ChatFailure
import com.blackwave.crest.core.model.ChatInteraction
import com.blackwave.crest.core.model.ChatSessionDetail
import com.blackwave.crest.core.model.ChatSessionSummary
import com.blackwave.crest.core.model.ChatStreamEvent
import com.blackwave.crest.core.model.supportedParts
import com.blackwave.crest.core.model.supportedActions
import com.blackwave.crest.core.model.ChangePasswordResponse
import com.blackwave.crest.core.model.InitialPasswordResponse
import com.blackwave.crest.core.model.LoginResponse
import com.blackwave.crest.core.model.PhoneStatusResponse
import com.blackwave.crest.core.model.ResetPasswordResponse
import com.blackwave.crest.core.model.VerificationConfirmResponse
import com.blackwave.crest.core.model.VerificationCreateResponse
import com.blackwave.crest.core.model.WorkspaceListResponse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.job
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class ApiException(
    val statusCode: Int? = null,
    override val message: String,
) : IOException(message) {
    val isUnauthorized: Boolean get() = statusCode == 401
}

class ApiClient(
    private val client: OkHttpClient = OkHttpClient(),
    private val baseUrl: String = BuildConfig.API_BASE_URL,
) {
    internal val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    suspend fun phoneStatus(phone: String): PhoneStatusResponse = post(
        path = "api/v1/auth/phone-status",
        body = buildJsonObject {
            put("phone", JsonPrimitive(phone))
            put("country_code", JsonPrimitive("+86"))
            put("client_type", JsonPrimitive("mobile"))
        },
        fallback = "手机号状态查询失败",
    )

    suspend fun login(phone: String, password: String): LoginResponse = post(
        path = "api/v1/auth/login",
        body = buildJsonObject {
            put("identifier_type", JsonPrimitive("phone"))
            put("identifier", JsonPrimitive(phone))
            put("password", JsonPrimitive(password))
            put("client_type", JsonPrimitive("mobile"))
            put("device_name", JsonPrimitive("crest-android"))
        },
        fallback = "登录失败",
    )

    suspend fun sendPhoneCode(
        phone: String,
        purpose: String,
    ): VerificationCreateResponse = post(
        path = "api/v1/auth/verifications",
        body = buildJsonObject {
            put("channel", JsonPrimitive("sms"))
            put("purpose", JsonPrimitive(purpose))
            put("target", JsonPrimitive(phone))
            put("invite_token", JsonPrimitive(""))
        },
        fallback = "验证码发送失败",
    )

    suspend fun confirmPhoneCode(
        challengeId: String,
        code: String,
    ): VerificationConfirmResponse = post(
        path = "api/v1/auth/verifications/$challengeId/confirm",
        body = buildJsonObject { put("code", JsonPrimitive(code)) },
        fallback = "验证码校验失败",
    )

    suspend fun loginWithCode(verificationToken: String): LoginResponse = codeSession(
        path = "api/v1/auth/login/code",
        verificationToken = verificationToken,
        fallback = "验证码登录失败",
    )

    suspend fun registerPersonal(verificationToken: String): LoginResponse = codeSession(
        path = "api/v1/auth/personal-register",
        verificationToken = verificationToken,
        fallback = "个人账号创建失败",
    )

    suspend fun resetPassword(
        verificationToken: String,
        newPassword: String,
    ): ResetPasswordResponse = post(
        path = "api/v1/auth/reset-password",
        body = buildJsonObject {
            put("verification_token", JsonPrimitive(verificationToken))
            put("new_password", JsonPrimitive(newPassword))
        },
        fallback = "密码重置失败",
    )

    suspend fun accountProfile(accessToken: String): AccountProfile = get(
        path = "api/v1/auth/profile",
        accessToken = accessToken,
        fallback = "个人资料加载失败",
    )

    suspend fun accountAvatar(accessToken: String): ByteArray {
        val request = Request.Builder()
            .url(url("api/v1/auth/profile/avatar"))
            .header("Authorization", "Bearer $accessToken")
            .get()
            .build()
        return client.newCall(request).await().use { response ->
            if (!response.isSuccessful) throw errorFrom(response, "头像加载失败")
            response.body?.bytes() ?: throw ApiException(message = "头像加载失败")
        }
    }

    suspend fun updateDisplayName(
        displayName: String,
        accessToken: String,
    ): AccountProfile = requestAndDecode(
        method = "PATCH",
        path = "api/v1/auth/profile",
        body = buildJsonObject { put("display_name", JsonPrimitive(displayName)) },
        accessToken = accessToken,
        fallback = "昵称修改失败",
    )

    suspend fun uploadAccountAvatar(imageData: ByteArray, accessToken: String): AccountProfile {
        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart(
                "file",
                "avatar.jpg",
                imageData.toRequestBody("image/jpeg".toMediaType()),
            )
            .build()
        val request = Request.Builder()
            .url(url("api/v1/auth/profile/avatar"))
            .header("Authorization", "Bearer $accessToken")
            .put(body)
            .build()
        return client.newCall(request).await().use { response ->
            if (!response.isSuccessful) throw errorFrom(response, "头像上传失败")
            val content = response.body?.string() ?: throw ApiException(message = "头像上传失败")
            json.decodeFromString(content)
        }
    }

    suspend fun setInitialPassword(
        newPassword: String,
        accessToken: String,
    ): InitialPasswordResponse = post(
        path = "api/v1/auth/password/initial",
        body = buildJsonObject { put("new_password", JsonPrimitive(newPassword)) },
        fallback = "密码设置失败",
        accessToken = accessToken,
    )

    suspend fun changePassword(
        oldPassword: String,
        newPassword: String,
        accessToken: String,
    ): ChangePasswordResponse = post(
        path = "api/v1/auth/change-password",
        body = buildJsonObject {
            put("old_password", JsonPrimitive(oldPassword))
            put("new_password", JsonPrimitive(newPassword))
        },
        fallback = "密码修改失败",
        accessToken = accessToken,
    )

    suspend fun refreshSession(refreshToken: String): LoginResponse = post(
        path = "api/v1/auth/refresh",
        body = mobileSessionBody(refreshToken),
        fallback = "登录状态刷新失败",
    )

    suspend fun logout(refreshToken: String) {
        request(
            method = "POST",
            path = "api/v1/auth/logout",
            body = mobileSessionBody(refreshToken),
            fallback = "退出登录失败",
        )
    }

    suspend fun listWorkspaces(accessToken: String): WorkspaceListResponse = get(
        path = "api/v1/auth/workspaces",
        accessToken = accessToken,
        fallback = "工作空间加载失败",
    )

    suspend fun acceptInvitation(
        inviteToken: String,
        accessToken: String,
    ): AcceptInvitationResponse = post(
        path = "api/v1/auth/accept-invite",
        body = buildJsonObject { put("invite_token", JsonPrimitive(inviteToken)) },
        fallback = "加入团队失败",
        accessToken = accessToken,
    )

    suspend fun analyticsOverview(
        dateFrom: String,
        dateTo: String,
        refresh: Boolean,
        accessToken: String,
        storeKeys: List<String> = emptyList(),
    ): AnalyticsOverview = get(
        path = "api/v1/analytics/operations/overview",
        accessToken = accessToken,
        fallback = "经营概览加载失败",
        query = analyticsPeriod(dateFrom, dateTo, storeKeys) + listOf(
            "compare" to "previous",
            "granularity" to "day",
            "order_breakdown" to "channel",
            "refresh" to refresh.toString(),
        ),
    )

    suspend fun analyticsStoreScope(accessToken: String): AnalyticsStoreScope = get(
        "api/v1/analytics/store-scope-tree", accessToken, "门店范围加载失败",
    )

    suspend fun analyticsProducts(dateFrom: String, dateTo: String, storeKeys: List<String>, accessToken: String): AnalyticsProducts = get(
        "api/v1/analytics/operations/products", accessToken, "产品分析加载失败",
        analyticsPeriod(dateFrom, dateTo, storeKeys) + listOf("compare" to "previous", "granularity" to "day", "limit" to "30"),
    )

    suspend fun analyticsLabor(dateFrom: String, dateTo: String, storeKeys: List<String>, accessToken: String): AnalyticsLabor = get(
        "api/v1/analytics/operations/labor", accessToken, "人效分析加载失败",
        analyticsPeriod(dateFrom, dateTo, storeKeys) + listOf("compare" to "previous", "granularity" to "day"),
    )

    suspend fun analyticsAlerts(businessDate: String, accessToken: String): AnalyticsAlerts = get(
        "api/v1/analytics/revenue-alerts", accessToken, "营收报警加载失败", listOf("business_date" to businessDate),
    )

    suspend fun analyticsRevenueTrend(dateFrom: String, dateTo: String, storeKeys: List<String>, accessToken: String): AnalyticsRevenueTrend = get(
        "api/v1/analytics/trends/revenue", accessToken, "营收趋势加载失败",
        analyticsPeriod(dateFrom, dateTo, storeKeys) + listOf("store_key" to "ALL", "source_type" to "all", "granularity" to "day", "include_current" to "false"),
    )

    suspend fun analyticsProductTrend(productKey: String, dateFrom: String, dateTo: String, storeKeys: List<String>, accessToken: String): AnalyticsProductTrend = get(
        "api/v1/analytics/products/trend", accessToken, "产品趋势加载失败",
        analyticsPeriod(dateFrom, dateTo, storeKeys) + listOf(
            "product_key" to productKey, "dim_key" to (storeKeys.singleOrNull() ?: "ALL"),
            "dim_type" to if (storeKeys.size == 1) "shop" else "all", "granularity" to "day", "include_current" to "false",
        ),
    )

    private fun analyticsPeriod(from: String, to: String, stores: List<String>) =
        listOf("date_from" to from, "date_to" to to) + stores.distinct().sorted().map { "store_keys" to it }

    suspend fun analyticsRevenueDelta(body: JsonObject, accessToken: String): com.blackwave.crest.core.model.AnalyticsDelta = post(
        "api/v1/analytics/trends/revenue/delta", body, "营收趋势增量加载失败", accessToken,
    )

    suspend fun analyticsProductDelta(body: JsonObject, accessToken: String): com.blackwave.crest.core.model.AnalyticsDelta = post(
        "api/v1/analytics/products/trend/delta", body, "产品趋势增量加载失败", accessToken,
    )

    suspend fun switchWorkspace(
        workspaceId: String,
        refreshToken: String,
        accessToken: String,
    ): LoginResponse = post(
        path = "api/v1/auth/workspaces/switch",
        body = buildJsonObject {
            put("workspace_id", JsonPrimitive(workspaceId))
            put("client_type", JsonPrimitive("mobile"))
            put("refresh_token", JsonPrimitive(refreshToken))
        },
        fallback = "工作空间切换失败",
        accessToken = accessToken,
    )

    suspend fun listChatSessions(accessToken: String): List<ChatSessionSummary> = get(
        path = "api/v1/sessions",
        accessToken = accessToken,
        fallback = "对话历史加载失败",
    )

    suspend fun chatSessionDetail(
        sessionId: String,
        accessToken: String,
    ): ChatSessionDetail = get(
        path = "api/v1/sessions/$sessionId",
        accessToken = accessToken,
        fallback = "对话加载失败",
    )

    suspend fun updateChatSession(
        sessionId: String,
        title: String? = null,
        isPinned: Boolean? = null,
        accessToken: String,
    ): ChatSessionSummary = requestAndDecode(
        method = "PATCH",
        path = "api/v1/sessions/$sessionId",
        body = buildJsonObject {
            title?.let { put("title", JsonPrimitive(it)) }
            isPinned?.let { put("is_pinned", JsonPrimitive(it)) }
        },
        accessToken = accessToken,
        fallback = "对话更新失败",
    )

    suspend fun deleteChatSession(sessionId: String, accessToken: String) {
        request(
            method = "DELETE",
            path = "api/v1/sessions/$sessionId",
            accessToken = accessToken,
            fallback = "对话删除失败",
        )
    }

    suspend fun cancelAgentRun(runId: String, accessToken: String) {
        request(
            method = "POST",
            path = "api/v1/agent-runs/cancel",
            body = buildJsonObject {
                put("run_id", JsonPrimitive(runId))
                put("request_id", JsonPrimitive(UUID.randomUUID().toString()))
                put("reason", JsonPrimitive("user_cancelled"))
            },
            accessToken = accessToken,
            fallback = "停止回复失败",
        )
    }

    suspend fun decideAgentRun(
        runId: String,
        decision: String,
        accessToken: String,
    ) {
        request(
            method = "POST",
            path = "api/v1/agent-runs/approve-action",
            body = buildJsonObject {
                put("run_id", JsonPrimitive(runId))
                put("request_id", JsonPrimitive(UUID.randomUUID().toString()))
                put("decision", JsonPrimitive(decision))
                put("note", JsonNull)
            },
            accessToken = accessToken,
            fallback = "提交确认失败",
        )
    }

    suspend fun streamChat(
        message: String,
        sessionId: String,
        runId: String,
        userMessageId: String,
        afterEventId: String? = null,
        interaction: ChatInteraction? = null,
        accessToken: String,
        onEvent: suspend (ChatStreamEvent) -> Unit,
    ) = withContext(Dispatchers.IO) {
        val parser = ChatEventParser(json, sessionId, runId)
        var cursor = afterEventId

        repeat(3) { attempt ->
            currentCoroutineContext().ensureActiveSafely()
            val request = Request.Builder()
                .url(url("api/v1/agui/runs"))
                .header("Content-Type", "application/json")
                .header("Accept", "text/event-stream")
                .header("Authorization", "Bearer $accessToken")
                .apply { cursor?.let { header("Last-Event-ID", it) } }
                .post(chatBody(sessionId, runId, userMessageId, message, cursor, interaction).toString()
                    .toRequestBody(JSON_MEDIA_TYPE))
                .build()

            val call = client.newCall(request)
            val cancellationHandle = currentCoroutineContext().job.invokeOnCompletion { cause ->
                if (cause is CancellationException) call.cancel()
            }

            try {
                call.execute().use { response ->
                    if (!response.isSuccessful) {
                        throw errorFrom(response, "消息发送失败")
                    }
                    val contentType = response.header("Content-Type").orEmpty()
                    if (!contentType.contains("text/event-stream")) {
                        throw ApiException(message = "新对话接口未返回事件流")
                    }

                    val source = response.body?.source()
                        ?: throw ApiException(message = "服务器响应异常")
                    val dataLines = mutableListOf<String>()
                    var frameId: String? = null
                    var completed = false

                    suspend fun flushFrame() {
                        if (dataLines.isEmpty()) {
                            frameId = null
                            return
                        }
                        val parsed = parser.parse(dataLines.joinToString("\n"))
                        if (frameId != null && parsed.eventId != frameId) {
                            throw ApiException(message = "事件游标与响应内容不一致")
                        }
                        cursor = parsed.eventId
                        onEvent(ChatStreamEvent.Cursor(parsed.eventId))
                        parsed.events.forEach { onEvent(it) }
                        completed = completed || parsed.isTerminal
                        dataLines.clear()
                        frameId = null
                    }

                    while (!source.exhausted() && !completed) {
                        currentCoroutineContext().ensureActiveSafely()
                        val line = source.readUtf8Line()?.trimEnd('\r') ?: break
                        when {
                            line.isEmpty() -> flushFrame()
                            line.startsWith("id:") -> {
                                if (dataLines.isNotEmpty()) flushFrame()
                                frameId = line.removePrefix("id:").trim()
                            }
                            line.startsWith("data:") -> dataLines += line.removePrefix("data:").trim()
                        }
                    }
                    if (!completed) flushFrame()
                    if (completed) {
                        onEvent(ChatStreamEvent.Done)
                        return@withContext
                    }
                }
            } catch (error: ApiException) {
                throw error
            } catch (error: CancellationException) {
                throw error
            } catch (error: IOException) {
                if (attempt == 2) throw error
                kotlinx.coroutines.delay(if (attempt == 0) 300 else 700)
            } finally {
                cancellationHandle.dispose()
            }
        }
        throw ApiException(message = "回复中断，请重新发送")
    }

    private suspend fun codeSession(
        path: String,
        verificationToken: String,
        fallback: String,
    ): LoginResponse = post(
        path = path,
        body = buildJsonObject {
            put("verification_token", JsonPrimitive(verificationToken))
            put("client_type", JsonPrimitive("mobile"))
            put("device_name", JsonPrimitive("crest-android"))
        },
        fallback = fallback,
    )

    private fun mobileSessionBody(refreshToken: String) = buildJsonObject {
        put("client_type", JsonPrimitive("mobile"))
        put("refresh_token", JsonPrimitive(refreshToken))
    }

    private fun chatBody(
        sessionId: String,
        runId: String,
        messageId: String,
        message: String,
        afterEventId: String?,
        interaction: ChatInteraction?,
    ) = buildJsonObject {
        put("threadId", JsonPrimitive(sessionId))
        put("runId", JsonPrimitive(runId))
        put("parentRunId", JsonNull)
        put("state", JsonObject(emptyMap()))
        put("messages", buildJsonArray {
            add(buildJsonObject {
                put("id", JsonPrimitive(messageId))
                put("role", JsonPrimitive("user"))
                put("content", JsonPrimitive(message))
            })
        })
        put("tools", JsonArray(emptyList()))
        put("context", JsonArray(emptyList()))
        put("forwardedProps", buildJsonObject {
            interaction?.let {
                put("interaction", buildJsonObject {
                    put("kind", JsonPrimitive("clarification_choice"))
                    put("source_turn_id", JsonPrimitive(it.sourceTurnId))
                    put("candidate_id", JsonPrimitive(it.candidateId))
                })
            }
            afterEventId?.let { put("afterEventId", JsonPrimitive(it)) }
        })
    }

    private suspend inline fun <reified T> post(
        path: String,
        body: JsonObject,
        fallback: String,
        accessToken: String? = null,
    ): T = requestAndDecode("POST", path, body, accessToken, fallback)

    private suspend inline fun <reified T> get(
        path: String,
        accessToken: String,
        fallback: String,
        query: List<Pair<String, String>> = emptyList(),
    ): T = requestAndDecode("GET", path, null, accessToken, fallback, query)

    private suspend inline fun <reified T> requestAndDecode(
        method: String,
        path: String,
        body: JsonObject?,
        accessToken: String?,
        fallback: String,
        query: List<Pair<String, String>> = emptyList(),
    ): T = json.decodeFromString(request(method, path, body, accessToken, fallback, query))

    private suspend fun request(
        method: String,
        path: String,
        body: JsonObject? = null,
        accessToken: String? = null,
        fallback: String,
        query: List<Pair<String, String>> = emptyList(),
    ): String {
        val builder = Request.Builder().url(url(path, query))
        accessToken?.let { builder.header("Authorization", "Bearer $it") }
        val requestBody = body?.toString()?.toRequestBody(JSON_MEDIA_TYPE)
        builder.method(method, requestBody)
        if (body != null) builder.header("Content-Type", "application/json")

        return client.newCall(builder.build()).await().use { response ->
            if (!response.isSuccessful) throw errorFrom(response, fallback)
            response.body?.string().orEmpty()
        }
    }

    private fun url(path: String, query: List<Pair<String, String>> = emptyList()) =
        baseUrl.toHttpUrl().newBuilder()
            .addPathSegments(path.trimStart('/'))
            .apply { query.forEach { (name, value) -> addQueryParameter(name, value) } }
            .build()

    private fun errorFrom(response: Response, fallback: String): ApiException {
        val raw = response.body?.string().orEmpty()
        val detail = runCatching {
            json.parseToJsonElement(raw).jsonObject["detail"]?.jsonPrimitive?.contentOrNull
        }.getOrNull()
        return ApiException(
            statusCode = response.code,
            message = detail?.takeIf { it.isNotBlank() } ?: "$fallback（${response.code}）",
        )
    }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                if (continuation.isActive) continuation.resumeWithException(error)
            }

            override fun onResponse(call: Call, response: Response) {
                if (continuation.isActive) continuation.resume(response) else response.close()
            }
        })
    }

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}

internal data class ParsedChatEvent(
    val eventId: String,
    val events: List<ChatStreamEvent>,
    val isTerminal: Boolean,
)

internal class ChatEventParser(
    private val json: Json,
    private val threadId: String,
    private val runId: String,
) {
    private val seenEventIds = mutableSetOf<String>()
    private var textMessageId: String? = null
    private var hasReceivedText = false

    fun parse(raw: String): ParsedChatEvent {
        val objectValue = runCatching { json.parseToJsonElement(raw).jsonObject }
            .getOrElse { throw ApiException(message = "新对话事件不是有效 JSON") }
        val type = objectValue.string("type") ?: throw ApiException(message = "新对话事件缺少 type")
        val eventId = objectValue.string("eventId") ?: throw ApiException(message = "新对话事件缺少 eventId")
        val sequence = objectValue["sequence"]?.jsonPrimitive?.intOrNull
            ?: throw ApiException(message = "新对话事件缺少有效 sequence")
        val eventRunId = objectValue.string("runId")
            ?: throw ApiException(message = "新对话事件缺少 runId")
        val eventThreadId = objectValue.string("threadId")
            ?: throw ApiException(message = "新对话事件缺少 threadId")
        if (eventRunId != runId) throw ApiException(message = "新对话事件 runId 不一致")
        if (eventThreadId != threadId) throw ApiException(message = "新对话事件 threadId 不一致")

        val idParts = eventId.split(':')
        if (idParts.size != 3 || idParts[0] != runId || idParts[1] != sequence.toString() || idParts[2].toIntOrNull() == null) {
            throw ApiException(message = "新对话事件 eventId 格式不正确")
        }
        if (!seenEventIds.add(eventId)) return ParsedChatEvent(eventId, emptyList(), false)

        return when (type) {
            "RUN_STARTED" -> parsed(eventId, ChatStreamEvent.Metadata(threadId), ChatStreamEvent.Stage("正在处理"))
            "TEXT_MESSAGE_START" -> {
                val messageId = objectValue.string("messageId")
                if (messageId == null || objectValue.string("role") != "assistant") {
                    throw ApiException(message = "回复消息格式不匹配")
                }
                textMessageId = messageId
                val separator = if (hasReceivedText) listOf(ChatStreamEvent.Text("\n\n")) else emptyList()
                ParsedChatEvent(eventId, separator, false)
            }
            "TEXT_MESSAGE_CONTENT" -> {
                val messageId = objectValue.string("messageId")
                val delta = objectValue.string("delta")
                if (messageId != textMessageId || delta == null) {
                    throw ApiException(message = "回复片段无法关联到当前消息")
                }
                hasReceivedText = hasReceivedText || delta.isNotEmpty()
                ParsedChatEvent(eventId, if (delta.isEmpty()) emptyList() else listOf(ChatStreamEvent.Text(delta)), false)
            }
            "TOOL_CALL_START" -> parsed(eventId, ChatStreamEvent.Stage("正在查询数据"))
            "STATE_SNAPSHOT" -> parseSnapshot(eventId, objectValue["snapshot"] as? JsonObject)
            "TOOL_CALL_RESULT" -> {
                val label = objectValue.string("content")?.let { content ->
                    runCatching { json.parseToJsonElement(content).jsonObject.string("label") }.getOrNull()
                }
                if (label.isNullOrBlank()) ParsedChatEvent(eventId, emptyList(), false)
                else parsed(eventId, ChatStreamEvent.Stage(label))
            }
            "RUN_ERROR" -> ParsedChatEvent(
                eventId,
                listOf(ChatStreamEvent.Failure(ChatFailure(
                    message = objectValue.string("message")?.trim()?.takeIf { it.isNotEmpty() } ?: "消息处理失败",
                    code = objectValue.string("code"),
                ))),
                true,
            )
            "RUN_FINISHED" -> ParsedChatEvent(eventId, emptyList(), true)
            else -> ParsedChatEvent(eventId, emptyList(), false)
        }
    }

    private fun parseSnapshot(eventId: String, snapshot: JsonObject?): ParsedChatEvent {
        if (snapshot == null) return ParsedChatEvent(eventId, emptyList(), false)
        val approval = snapshot["approval"] as? JsonObject
        if (approval != null) {
            val value = ChatApproval(
                approvalId = approval.string("approval_id") ?: return ParsedChatEvent(eventId, emptyList(), false),
                toolLabel = approval.string("tool_label") ?: return ParsedChatEvent(eventId, emptyList(), false),
                message = approval.string("message") ?: return ParsedChatEvent(eventId, emptyList(), false),
                expiresAt = approval.string("expires_at") ?: return ParsedChatEvent(eventId, emptyList(), false),
                runId = runId,
                lastEventId = eventId,
            )
            return parsed(eventId, ChatStreamEvent.Approval(value))
        }
        val response = snapshot["agent_response"] ?: return ParsedChatEvent(eventId, emptyList(), false)
        val agentResponse = runCatching { json.decodeFromJsonElement<ChatAgentResponse>(response) }.getOrNull()
            ?: return ParsedChatEvent(eventId, emptyList(), false)
        return ParsedChatEvent(
            eventId,
            listOf(
                ChatStreamEvent.Parts(agentResponse.supportedParts),
                ChatStreamEvent.Actions(agentResponse.supportedActions),
                ChatStreamEvent.ResponseStatus(agentResponse.resultStatus),
            ),
            false,
        )
    }

    private fun parsed(eventId: String, vararg events: ChatStreamEvent) =
        ParsedChatEvent(eventId, events.toList(), false)

    private fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
}

private fun kotlin.coroutines.CoroutineContext.ensureActiveSafely() {
    if (!job.isActive) throw CancellationException()
}
