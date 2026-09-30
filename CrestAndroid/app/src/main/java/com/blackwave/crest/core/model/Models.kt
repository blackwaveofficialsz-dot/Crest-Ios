package com.blackwave.crest.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

@Serializable
data class LoginResponse(
    val token: String,
    val username: String,
    @SerialName("tenant_id") val tenantId: String? = null,
    @SerialName("user_id") val userId: String,
    val role: String,
    @SerialName("has_password") val hasPassword: Boolean,
    @SerialName("workspace_type") val workspaceType: String,
    @SerialName("active_workspace_id") val activeWorkspaceId: String,
    @SerialName("refresh_token") val refreshToken: String? = null,
)

@Serializable
data class PhoneStatusResponse(
    @SerialName("is_registered") val isRegistered: Boolean,
    @SerialName("has_password") val hasPassword: Boolean,
)

@Serializable
data class VerificationCreateResponse(
    @SerialName("challenge_id") val challengeId: String,
    val message: String,
    @SerialName("expires_in") val expiresIn: Int,
    @SerialName("resend_after") val resendAfter: Int,
)

@Serializable
data class VerificationConfirmResponse(
    @SerialName("verification_token") val verificationToken: String,
    @SerialName("expires_in") val expiresIn: Int,
)

@Serializable
data class ResetPasswordResponse(val message: String)

@Serializable
data class InitialPasswordResponse(
    val message: String,
    @SerialName("has_password") val hasPassword: Boolean,
)

@Serializable
data class AccountProfile(
    @SerialName("user_id") val userId: String,
    val username: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("has_avatar") val hasAvatar: Boolean,
)

@Serializable
data class ChangePasswordResponse(val message: String)

@Serializable
data class WorkspaceSummary(
    @SerialName("workspace_id") val workspaceId: String,
    @SerialName("workspace_type") val workspaceType: String,
    val name: String,
    @SerialName("tenant_id") val tenantId: String? = null,
    val role: String,
    @SerialName("is_active") val isActive: Boolean = false,
)

@Serializable
data class WorkspaceListResponse(
    @SerialName("active_workspace_id") val activeWorkspaceId: String,
    val items: List<WorkspaceSummary>,
)

@Serializable
data class AcceptInvitationResponse(
    val workspace: WorkspaceSummary,
    val message: String,
)

@Serializable
data class AnalyticsDateRange(
    @SerialName("date_from") val dateFrom: String,
    @SerialName("date_to") val dateTo: String,
)

@Serializable
data class AnalyticsMetricComparison(
    val current: Double? = null,
    val previous: Double? = null,
    val difference: Double? = null,
    @SerialName("change_rate") val changeRate: Double? = null,
    val status: String = "",
)

@Serializable
data class AnalyticsDimensionRow(
    @SerialName("dim_key") val dimensionKey: String? = null,
    @SerialName("dim_label") val dimensionLabel: String? = null,
    @SerialName("store_key") val storeKey: String? = null,
    @SerialName("store_label") val storeLabel: String? = null,
    val metrics: Map<String, AnalyticsMetricComparison> = emptyMap(),
) {
    val id: String get() = storeKey ?: dimensionKey ?: label
    val label: String get() = storeLabel ?: dimensionLabel ?: storeKey ?: dimensionKey ?: "未命名"
}

@Serializable
data class AnalyticsOverview(
    val period: AnalyticsDateRange,
    @SerialName("previous_period") val previousPeriod: AnalyticsDateRange? = null,
    val metrics: Map<String, AnalyticsMetricComparison> = emptyMap(),
    val channels: List<AnalyticsDimensionRow> = emptyList(),
    val stores: List<AnalyticsDimensionRow> = emptyList(),
    @SerialName("generated_at") val generatedAt: String? = null,
)

@Serializable
data class ChatSessionSummary(
    @SerialName("session_id") val sessionId: String,
    val title: String,
    @SerialName("is_pinned") val isPinned: Boolean = false,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class ChatResponseActionParameters(
    @SerialName("candidate_id") val candidateId: String? = null,
    val message: String? = null,
)

@Serializable
data class ChatResponseAction(
    @SerialName("action_id") val actionId: String,
    val kind: String,
    val label: String,
    @SerialName("source_turn_id") val sourceTurnId: String? = null,
    val params: ChatResponseActionParameters? = null,
)

@Serializable
data class ChatResponseColumn(
    val key: String,
    val label: String,
    @SerialName("data_type") val dataType: String? = null,
    val unit: String? = null,
)

@Serializable
data class ChatResponseMetric(
    val key: String,
    val label: String? = null,
    val value: String,
    val unit: String? = null,
)

@Serializable
data class ChatResponseInsight(
    @SerialName("statement_type") val statementType: String,
    val text: String,
    @SerialName("evidence_refs") val evidenceRefs: List<String> = emptyList(),
)

@Serializable
data class ChatResponsePart(
    val kind: String,
    val title: String? = null,
    val message: String? = null,
    val metrics: List<ChatResponseMetric>? = null,
    val items: List<ChatResponseInsight>? = null,
    val severity: String? = null,
    val code: String? = null,
    @SerialName("reason_code") val reasonCode: String? = null,
    @SerialName("missing_fields") val missingFields: List<String>? = null,
    @SerialName("allow_free_text") val allowFreeText: Boolean? = null,
    @SerialName("table_id") val tableId: String? = null,
    @SerialName("row_count") val rowCount: Int? = null,
    val columns: List<ChatResponseColumn>? = null,
    @SerialName("preview_rows") val previewRows: List<Map<String, JsonElement>>? = null,
)

@Serializable
data class ChatAgentResponse(
    val version: Int,
    val domain: String? = null,
    val task: String? = null,
    @SerialName("result_status") val resultStatus: String? = null,
    @SerialName("result_id") val resultId: String? = null,
    @SerialName("source_turn_id") val sourceTurnId: String,
    val parts: List<ChatResponsePart> = emptyList(),
    val actions: List<ChatResponseAction> = emptyList(),
)

val ChatAgentResponse.supportedParts: List<ChatResponsePart>
    get() {
        if (version != 1 || sourceTurnId.isBlank()) return emptyList()
        return parts.take(6).filter { part ->
            when (part.kind) {
                "table" -> !part.columns.isNullOrEmpty()
                "summary" -> !part.metrics.isNullOrEmpty() || !part.message.isNullOrBlank()
                "insights" -> !part.items.isNullOrEmpty()
                "notice" -> !part.message.isNullOrBlank() && part.severity in listOf("info", "warning", "error")
                "clarification" -> !part.message.isNullOrBlank()
                else -> false
            }
        }
    }

val ChatAgentResponse.supportedActions: List<ChatResponseAction>
    get() {
        if (version != 1 || sourceTurnId.isBlank()) return emptyList()
        return actions.take(6).filter { action ->
            action.actionId.isNotEmpty() && action.label.isNotBlank() &&
                !action.params?.message.isNullOrBlank() && action.sourceTurnId == sourceTurnId &&
                (action.kind == "prompt" || action.kind == "clarify" && !action.params?.candidateId.isNullOrBlank())
        }
    }

@Serializable(with = ChatHistoryMetadataSerializer::class)
data class ChatHistoryMetadata(
    @SerialName("agent_response") val agentResponse: ChatAgentResponse? = null,
    @SerialName("delivery_status") val deliveryStatus: String? = null,
)

/** A damaged legacy agent_response must not make the whole conversation unreadable. */
object ChatHistoryMetadataSerializer : KSerializer<ChatHistoryMetadata> {
    override val descriptor = buildClassSerialDescriptor("ChatHistoryMetadata")

    override fun deserialize(decoder: Decoder): ChatHistoryMetadata {
        val jsonDecoder = decoder as JsonDecoder
        val objectValue = jsonDecoder.decodeJsonElement() as? JsonObject ?: return ChatHistoryMetadata()
        val response = objectValue["agent_response"]?.let { element ->
            runCatching { jsonDecoder.json.decodeFromJsonElement<ChatAgentResponse>(element) }.getOrNull()
        }
        return ChatHistoryMetadata(response, objectValue["delivery_status"]?.jsonPrimitive?.contentOrNull)
    }

    override fun serialize(encoder: Encoder, value: ChatHistoryMetadata) {
        val jsonEncoder = encoder as JsonEncoder
        jsonEncoder.encodeJsonElement(buildJsonObject {
            value.agentResponse?.let { put("agent_response", jsonEncoder.json.encodeToJsonElement(it)) }
            value.deliveryStatus?.let { put("delivery_status", JsonPrimitive(it)) }
        })
    }
}

@Serializable
data class ChatHistoryMessage(
    val id: String,
    val role: String,
    val content: String,
    @SerialName("created_at") val createdAt: String,
    val metadata: ChatHistoryMetadata? = null,
)

@Serializable
data class ChatSessionDetail(
    @SerialName("session_id") val sessionId: String,
    val title: String,
    val messages: List<ChatHistoryMessage>,
)

data class ChatFailure(
    val message: String,
    val code: String? = null,
    val retryable: Boolean = true,
)

data class ChatApproval(
    val approvalId: String,
    val toolLabel: String,
    val message: String,
    val expiresAt: String,
    val runId: String,
    val lastEventId: String,
)

data class ChatInteraction(
    val sourceTurnId: String,
    val candidateId: String,
)

enum class ChatRole { USER, ASSISTANT }

data class ChatMessage(
    val id: String,
    val role: ChatRole,
    val content: String,
    val responseParts: List<ChatResponsePart> = emptyList(),
    val responseActions: List<ChatResponseAction> = emptyList(),
    val responseStatus: String? = null,
    val failure: ChatFailure? = null,
    val approval: ChatApproval? = null,
)

fun ChatHistoryMessage.toChatMessage(): ChatMessage? {
    val mappedRole = when (role) {
        "user" -> ChatRole.USER
        "assistant" -> ChatRole.ASSISTANT
        else -> return null
    }
    val agentResponse = metadata?.agentResponse
    val deliveryStatus = metadata?.deliveryStatus
    return ChatMessage(
        id = id,
        role = mappedRole,
        content = content,
        responseParts = agentResponse?.supportedParts.orEmpty(),
        responseActions = agentResponse?.supportedActions.orEmpty(),
        responseStatus = agentResponse?.resultStatus
            ?: deliveryStatus?.let { if (it == "completed") "ok" else it },
        failure = if (deliveryStatus == "failed") ChatFailure(content) else null,
    )
}

sealed interface ChatStreamEvent {
    data class Text(val delta: String) : ChatStreamEvent
    data class Parts(val value: List<ChatResponsePart>) : ChatStreamEvent
    data class Actions(val value: List<ChatResponseAction>) : ChatStreamEvent
    data class ResponseStatus(val value: String?) : ChatStreamEvent
    data class Cursor(val eventId: String) : ChatStreamEvent
    data class Failure(val value: ChatFailure) : ChatStreamEvent
    data class Approval(val value: ChatApproval) : ChatStreamEvent
    data class Metadata(val sessionId: String?) : ChatStreamEvent
    data class Stage(val label: String) : ChatStreamEvent
    data object Done : ChatStreamEvent
}
