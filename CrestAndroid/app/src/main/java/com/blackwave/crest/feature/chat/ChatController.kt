package com.blackwave.crest.feature.chat

import com.blackwave.crest.ui.localization.L

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.blackwave.crest.core.model.ChatInteraction
import com.blackwave.crest.core.model.ChatMessage
import com.blackwave.crest.core.model.ChatResponseAction
import com.blackwave.crest.core.model.ChatRole
import com.blackwave.crest.core.model.ChatSessionSummary
import com.blackwave.crest.core.model.ChatStreamEvent
import com.blackwave.crest.core.model.toChatMessage
import com.blackwave.crest.core.session.SessionStore
import com.blackwave.crest.core.session.userMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

private data class PendingRun(
    val message: String,
    val sessionId: String,
    val runId: String,
    val userMessageId: String,
    val interaction: ChatInteraction?,
    val assistantMessageId: String,
    var lastEventId: String? = null,
)

class ChatController(private val session: SessionStore) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var streamJob: Job? = null
    private var conversationJob: Job? = null
    private var conversationGeneration = 0
    private var pendingRun: PendingRun? = null
    private var streamFlushJob: Job? = null
    private var pendingStreamMessageId: String? = null
    private val pendingStreamText = StringBuilder()

    val sessions = mutableStateListOf<ChatSessionSummary>()
    val messages = mutableStateListOf<ChatMessage>()

    var activeSessionId by mutableStateOf<String?>(null)
        private set
    var activeTitle by mutableStateOf(L("新对话"))
        private set
    var isLoadingHistory by mutableStateOf(false)
        private set
    var historyError by mutableStateOf<String?>(null)
        private set
    var isLoadingConversation by mutableStateOf(false)
        private set
    var conversationError by mutableStateOf<String?>(null)
        private set
    var isStreaming by mutableStateOf(false)
        private set
    var streamStatus by mutableStateOf(L("正在连接"))
        private set
    var activeRunId by mutableStateOf<String?>(null)
        private set
    var completedMessageId by mutableStateOf<String?>(null)
        private set
    var operationError by mutableStateOf<String?>(null)

    init {
        loadHistory()
    }

    fun close() {
        scope.cancel()
    }

    fun loadHistory() {
        scope.launch { loadHistoryNow() }
    }

    fun newChat() {
        conversationGeneration++
        conversationJob?.cancel()
        isLoadingConversation = false
        streamJob?.cancel()
        discardPendingStreamText()
        activeSessionId = null
        activeTitle = L("新对话")
        messages.clear()
        conversationError = null
        pendingRun = null
        isStreaming = false
        activeRunId = null
        completedMessageId = null
    }

    fun openSession(sessionId: String) {
        if (sessionId == activeSessionId && messages.isNotEmpty()) return
        val generation = ++conversationGeneration
        streamJob?.cancel()
        conversationJob?.cancel()
        discardPendingStreamText()
        pendingRun = null
        isStreaming = false
        activeRunId = null
        completedMessageId = null
        conversationJob = scope.launch {
            isLoadingConversation = true
            conversationError = null
            try {
                val detail = session.authenticated { session.api.chatSessionDetail(sessionId, it) }
                if (generation != conversationGeneration) return@launch
                activeSessionId = detail.sessionId
                activeTitle = detail.title
                messages.clear()
                messages.addAll(detail.messages.mapNotNull { it.toChatMessage() })
            } catch (cancel: CancellationException) { throw cancel
            } catch (error: Exception) {
                if (generation == conversationGeneration) conversationError = error.userMessage(L("对话加载失败"))
            } finally {
                if (generation == conversationGeneration) isLoadingConversation = false
            }
        }
    }

    fun send(text: String, interaction: ChatInteraction? = null) {
        val content = text.trim()
        if (content.isEmpty() || isStreaming || isLoadingConversation) return

        val sessionId = activeSessionId ?: UUID.randomUUID().toString().also { activeSessionId = it }
        val userMessageId = UUID.randomUUID().toString()
        val assistantMessageId = UUID.randomUUID().toString()
        val runId = UUID.randomUUID().toString()
        messages += ChatMessage(userMessageId, ChatRole.USER, content)
        messages += ChatMessage(assistantMessageId, ChatRole.ASSISTANT, "")
        conversationError = null
        startRun(PendingRun(content, sessionId, runId, userMessageId, interaction, assistantMessageId))
    }

    fun performAction(action: ChatResponseAction) {
        val message = action.params?.message?.trim().orEmpty()
        if (message.isEmpty()) return
        val interaction = if (action.kind == "clarify") {
            val sourceTurnId = action.sourceTurnId ?: return
            val candidateId = action.params?.candidateId ?: return
            ChatInteraction(sourceTurnId, candidateId)
        } else null
        send(message, interaction)
    }

    fun retryResponse(assistantMessage: ChatMessage) {
        if (isStreaming) return
        val assistantIndex = messages.indexOfFirst { it.id == assistantMessage.id }
        if (assistantIndex <= 0) return
        val userMessage = messages
            .subList(0, assistantIndex)
            .lastOrNull { it.role == ChatRole.USER }
            ?: return
        send(userMessage.content)
    }

    fun decideApproval(decision: String) {
        val run = pendingRun ?: return
        val approval = messages.firstOrNull { it.id == run.assistantMessageId }?.approval ?: return
        if (approval.runId != run.runId || isStreaming) return
        run.lastEventId = approval.lastEventId
        updateMessage(run.assistantMessageId) { it.copy(approval = null, failure = null) }

        streamJob = scope.launch {
            isStreaming = true
            completedMessageId = null
            streamStatus = if (decision == "approve") L("正在执行已确认操作") else L("正在取消操作")
            activeRunId = run.runId
            try {
                session.authenticated { token ->
                    session.api.decideAgentRun(run.runId, decision, token)
                    session.api.streamChat(
                        message = run.message,
                        sessionId = run.sessionId,
                        runId = run.runId,
                        userMessageId = run.userMessageId,
                        afterEventId = run.lastEventId,
                        interaction = run.interaction,
                        accessToken = token,
                    ) { event -> withContext(Dispatchers.Main.immediate) { applyEvent(run, event) } }
                }
                flushPendingStreamText()
                completedMessageId = run.assistantMessageId
                finishRun(run.assistantMessageId)
                loadHistoryNow()
            } catch (_: CancellationException) {
                return@launch
            } catch (error: Exception) {
                applyFailure(run.assistantMessageId, error.userMessage(L("操作继续失败")))
            } finally {
                finishRun(run.assistantMessageId)
            }
        }
    }

    fun stop() {
        val runId = activeRunId ?: return
        streamJob?.cancel()
        flushPendingStreamText()
        isStreaming = false
        activeRunId = null
        streamStatus = L("已停止")
        scope.launch {
            runCatching { session.authenticated { session.api.cancelAgentRun(runId, it) } }
                .onFailure { operationError = it.userMessage(L("停止回复失败")) }
        }
    }

    fun togglePin(item: ChatSessionSummary) {
        scope.launch {
            try {
                val updated = session.authenticated {
                    session.api.updateChatSession(item.sessionId, isPinned = !item.isPinned, accessToken = it)
                }
                val index = sessions.indexOfFirst { it.sessionId == updated.sessionId }
                if (index >= 0) sessions[index] = updated
                sortSessions()
            } catch (error: Exception) {
                operationError = error.userMessage(L("置顶设置失败"))
            }
        }
    }

    fun rename(item: ChatSessionSummary, title: String) {
        val normalized = title.trim()
        if (normalized.isEmpty() || normalized == item.title) return
        scope.launch {
            try {
                val updated = session.authenticated {
                    session.api.updateChatSession(item.sessionId, title = normalized, accessToken = it)
                }
                val index = sessions.indexOfFirst { it.sessionId == updated.sessionId }
                if (index >= 0) sessions[index] = updated
                if (activeSessionId == updated.sessionId) activeTitle = updated.title
                sortSessions()
            } catch (error: Exception) {
                operationError = error.userMessage(L("对话重命名失败"))
            }
        }
    }

    fun delete(item: ChatSessionSummary) {
        scope.launch {
            try {
                session.authenticated { session.api.deleteChatSession(item.sessionId, it) }
                sessions.removeAll { it.sessionId == item.sessionId }
                if (activeSessionId == item.sessionId) newChat()
            } catch (error: Exception) {
                operationError = error.userMessage(L("对话删除失败"))
            }
        }
    }

    private fun startRun(run: PendingRun) {
        pendingRun = run
        streamJob?.cancel()
        discardPendingStreamText()
        streamJob = scope.launch {
            isStreaming = true
            completedMessageId = null
            streamStatus = L("正在连接")
            activeRunId = run.runId
            try {
                session.authenticated { token ->
                    session.api.streamChat(
                        message = run.message,
                        sessionId = run.sessionId,
                        runId = run.runId,
                        userMessageId = run.userMessageId,
                        interaction = run.interaction,
                        accessToken = token,
                    ) { event -> withContext(Dispatchers.Main.immediate) { applyEvent(run, event) } }
                }
                flushPendingStreamText()
                completedMessageId = run.assistantMessageId
                finishRun(run.assistantMessageId)
                loadHistoryNow()
            } catch (_: CancellationException) {
                return@launch
            } catch (error: Exception) {
                applyFailure(run.assistantMessageId, error.userMessage(L("消息发送失败")))
            } finally {
                finishRun(run.assistantMessageId)
            }
        }
    }

    private fun applyEvent(run: PendingRun, event: ChatStreamEvent) {
        when (event) {
            is ChatStreamEvent.Text -> queueStreamText(run.assistantMessageId, event.delta)
            is ChatStreamEvent.Parts -> updateMessage(run.assistantMessageId) { it.copy(responseParts = event.value) }
            is ChatStreamEvent.Actions -> updateMessage(run.assistantMessageId) { it.copy(responseActions = event.value) }
            is ChatStreamEvent.ResponseStatus -> updateMessage(run.assistantMessageId) { it.copy(responseStatus = event.value) }
            is ChatStreamEvent.Cursor -> {
                run.lastEventId = event.eventId
                pendingRun = run
            }
            is ChatStreamEvent.Failure -> updateMessage(run.assistantMessageId) { it.copy(failure = event.value) }
            is ChatStreamEvent.Approval -> updateMessage(run.assistantMessageId) { it.copy(approval = event.value) }
            is ChatStreamEvent.Stage -> streamStatus = event.label
            is ChatStreamEvent.Metadata -> Unit
            ChatStreamEvent.Done -> Unit
        }
    }

    private fun applyFailure(messageId: String, message: String) {
        flushPendingStreamText()
        updateMessage(messageId) {
            it.copy(failure = com.blackwave.crest.core.model.ChatFailure(message))
        }
    }

    private fun finishRun(messageId: String) {
        if (pendingRun?.assistantMessageId != messageId) return
        flushPendingStreamText()
        isStreaming = false
        activeRunId = null
        if (messages.firstOrNull { it.id == messageId }?.approval == null) pendingRun = null
    }

    private fun queueStreamText(messageId: String, delta: String) {
        if (pendingStreamMessageId != null && pendingStreamMessageId != messageId) {
            flushPendingStreamText()
        }
        pendingStreamMessageId = messageId
        pendingStreamText.append(delta)
        if (streamFlushJob == null) {
            streamFlushJob = scope.launch {
                delay(50)
                flushPendingStreamText()
            }
        }
    }

    private fun flushPendingStreamText() {
        val text = pendingStreamText.toString()
        val messageId = pendingStreamMessageId
        streamFlushJob?.cancel()
        streamFlushJob = null
        pendingStreamText.clear()
        pendingStreamMessageId = null
        if (messageId != null && text.isNotEmpty()) {
            updateMessage(messageId) { it.copy(content = it.content + text) }
        }
    }

    private fun discardPendingStreamText() {
        streamFlushJob?.cancel()
        streamFlushJob = null
        pendingStreamText.clear()
        pendingStreamMessageId = null
    }

    private suspend fun loadHistoryNow() {
        isLoadingHistory = true
        historyError = null
        try {
            val loaded = session.authenticated { session.api.listChatSessions(it) }
            sessions.clear()
            sessions.addAll(loaded)
            sortSessions()
            activeSessionId?.let { id ->
                sessions.firstOrNull { it.sessionId == id }?.let { activeTitle = it.title }
            }
        } catch (error: Exception) {
            historyError = error.userMessage(L("对话历史加载失败"))
        } finally {
            isLoadingHistory = false
        }
    }

    private fun updateMessage(id: String, transform: (ChatMessage) -> ChatMessage) {
        val index = messages.indexOfFirst { it.id == id }
        if (index >= 0) messages[index] = transform(messages[index])
    }

    private fun sortSessions() {
        val sorted = sessions.sortedWith(compareByDescending<ChatSessionSummary> { it.isPinned }.thenByDescending { it.updatedAt })
        sessions.clear()
        sessions.addAll(sorted)
    }
}
