package com.blackwave.crest.feature.chat

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PersistableBundle
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.blackwave.crest.core.model.ChatMessage
import com.blackwave.crest.core.model.ChatResponsePart
import com.blackwave.crest.core.model.ChatRole
import com.blackwave.crest.ui.components.CrestIcon
import com.blackwave.crest.ui.components.CrestIconKind
import com.blackwave.crest.ui.theme.CrestRoundedFontFamily
import kotlinx.coroutines.delay

@Composable
fun ChatScreen(
    controller: ChatController,
    isTenant: Boolean,
    onCopy: () -> Unit,
    playbackAllowed: Boolean = true,
) {
    var draft by rememberSaveable(controller.activeSessionId) { mutableStateOf("") }
    val listState = rememberLazyListState()
    val lastMessage = controller.messages.lastOrNull()

    LaunchedEffect(
        controller.messages.size,
        lastMessage?.content,
        lastMessage?.responseParts?.size,
        lastMessage?.responseActions?.size,
        controller.isStreaming,
        controller.streamStatus,
    ) {
        if (controller.messages.isNotEmpty()) listState.scrollToItem(controller.messages.size)
    }

    val sendDraft = {
        if (!controller.isStreaming && draft.isNotBlank()) {
            controller.send(draft)
            draft = ""
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                controller.isLoadingConversation -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                controller.conversationError != null -> ConversationError(
                    controller.conversationError!!,
                    onRetry = { controller.activeSessionId?.let(controller::openSession) },
                    modifier = Modifier.align(Alignment.Center),
                )
                controller.messages.isEmpty() -> EmptyConversation(Modifier.fillMaxSize())
                else -> LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    items(controller.messages, key = { it.id }) { message ->
                        MessageRow(
                            message = message,
                            isStreaming = controller.isStreaming && message == controller.messages.lastOrNull(),
                            canRetry = !controller.isStreaming,
                            streamStatus = controller.streamStatus,
                            onAction = controller::performAction,
                            onApproval = controller::decideApproval,
                            onRetry = controller::retryResponse,
                            onCopy = onCopy,
                            playbackAllowed = playbackAllowed,
                            finishedNormally = controller.completedMessageId == message.id,
                        )
                    }
                    item(key = "reply-bottom") { Spacer(Modifier.height(1.dp)) }
                }
            }
        }
        if (controller.messages.isEmpty() && !controller.isLoadingConversation && controller.conversationError == null) {
            SuggestionBar(
                suggestions = if (isTenant) {
                    listOf(
                        SuggestionItem("分析本月经营情况", CrestIconKind.LINE_UP),
                        SuggestionItem("找出最近的异常费用", CrestIconKind.ALERT_SEARCH),
                        SuggestionItem("生成一份经营摘要", CrestIconKind.DOCUMENT),
                    )
                } else {
                    listOf(
                        SuggestionItem("帮我设计一份菜单结构", CrestIconKind.MENU_CARD),
                        SuggestionItem("如何控制餐厅食材成本", CrestIconKind.CHART_PIE),
                        SuggestionItem("制定新店开业推广计划", CrestIconKind.MEGAPHONE),
                    )
                },
                onSelect = { draft = it.title },
            )
        }
        ChatComposer(
            draft = draft,
            onDraftChange = { draft = it },
            canSend = draft.isNotBlank(),
            isStreaming = controller.isStreaming,
            onSend = sendDraft,
            onStop = controller::stop,
        )
    }
}

@Composable
private fun EmptyConversation(modifier: Modifier = Modifier) {
    Box(modifier) {
        Column(
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .size(58.dp)
                    .shadow(
                        elevation = 24.dp,
                        shape = CircleShape,
                        ambientColor = MaterialTheme.colorScheme.onBackground.copy(alpha = .08f),
                        spotColor = MaterialTheme.colorScheme.onBackground.copy(alpha = .08f),
                    )
                    .background(MaterialTheme.colorScheme.surface, CircleShape)
                    .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "C",
                    fontSize = 25.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = CrestRoundedFontFamily,
                )
            }
            Text(
                "今天想一起处理什么？",
                modifier = Modifier.padding(top = 22.dp),
                fontSize = 28.sp,
                lineHeight = 34.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = CrestRoundedFontFamily,
                textAlign = TextAlign.Center,
            )
            Text(
                "从一个餐饮经营问题开始",
                modifier = Modifier.padding(top = 8.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 14.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

private data class SuggestionItem(val title: String, val icon: CrestIconKind)

@Composable
private fun SuggestionBar(suggestions: List<SuggestionItem>, onSelect: (SuggestionItem) -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 25.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        suggestions.forEach { suggestion ->
            Row(
                modifier = Modifier
                    .height(42.dp)
                    .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(21.dp))
                    .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(21.dp))
                    .clickable { onSelect(suggestion) }
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CrestIcon(
                    kind = suggestion.icon,
                    modifier = Modifier.size(20.dp),
                    color = MaterialTheme.colorScheme.onBackground,
                )
                Text(suggestion.title, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            }
        }
    }
}

@Composable
private fun ChatComposer(
    draft: String,
    onDraftChange: (String) -> Unit,
    canSend: Boolean,
    isStreaming: Boolean,
    onSend: () -> Unit,
    onStop: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .padding(start = 25.dp, end = 25.dp, bottom = 8.dp)
            .heightIn(min = 52.dp)
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(26.dp))
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(26.dp))
            .padding(start = 16.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        BasicTextField(
            value = draft,
            onValueChange = onDraftChange,
            modifier = Modifier.weight(1f).padding(vertical = 14.dp),
            textStyle = TextStyle(color = MaterialTheme.colorScheme.onBackground, fontSize = 16.sp),
            cursorBrush = Brush.verticalGradient(listOf(MaterialTheme.colorScheme.onBackground, MaterialTheme.colorScheme.onBackground)),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { onSend() }),
            maxLines = 5,
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (draft.isEmpty()) {
                        Text("给 Crest 发消息", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
                    }
                    inner()
                }
            },
        )
        Box(
            modifier = Modifier.size(44.dp).clickable(enabled = isStreaming || canSend) {
                if (isStreaming) onStop() else onSend()
            },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier.size(30.dp).background(
                    if (isStreaming || canSend) MaterialTheme.colorScheme.secondary
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .25f),
                    CircleShape,
                ),
                contentAlignment = Alignment.Center,
            ) {
                CrestIcon(
                    if (isStreaming) CrestIconKind.STOP else CrestIconKind.SEND,
                    Modifier.size(18.dp),
                    Color.White,
                )
            }
        }
    }
}

@Composable
private fun ConversationError(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(message, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
        Button(onClick = onRetry) { Text("重新加载") }
    }
}

@Composable
private fun MessageRow(
    message: ChatMessage,
    isStreaming: Boolean,
    canRetry: Boolean,
    streamStatus: String,
    onAction: (com.blackwave.crest.core.model.ChatResponseAction) -> Unit,
    onApproval: (String) -> Unit,
    onRetry: (ChatMessage) -> Unit,
    onCopy: () -> Unit,
    playbackAllowed: Boolean,
    finishedNormally: Boolean,
) {
    when (message.role) {
        ChatRole.USER -> Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f))
            Surface(
                modifier = Modifier.widthIn(max = 560.dp),
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surfaceVariant,
            ) {
                Text(message.content, modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
            }
        }
        ChatRole.ASSISTANT -> Column(
            modifier = Modifier.fillMaxWidth().widthIn(max = 680.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val (displayText, isPlaying) = rememberReplyText(
                message = message,
                isStreaming = isStreaming,
                playbackAllowed = playbackAllowed,
                finishedNormally = finishedNormally,
            )
            if (!isStreaming && message.failure == null && message.responseStatus != null && message.responseStatus != "ok") {
                Text(
                    responseStatusLabel(message.responseStatus),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            when {
                message.failure != null -> FailureCard(
                    message = message.failure.message,
                    retryable = message.failure.retryable,
                    enabled = canRetry,
                    onRetry = { onRetry(message) },
                )
                displayText.isNotEmpty() -> MarkdownMessage(displayText, isStreaming || isPlaying)
                isStreaming -> CrestWaveThinkingIndicator(streamStatus)
            }
            if (!isStreaming && !isPlaying) {
                message.responseParts.forEach { StructuredPart(it) }
                ResponseActionButtons(message.responseActions, onAction)
            }
            message.approval?.let { approval ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.large,
                    tonalElevation = 2.dp,
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(approval.toolLabel, fontWeight = FontWeight.SemiBold)
                        Text(approval.message, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            OutlinedButton(onClick = { onApproval("reject") }) { Text("拒绝") }
                            Button(onClick = { onApproval("approve") }) { Text("确认执行") }
                        }
                    }
                }
            }
            if (message.failure == null && message.content.isNotBlank() && !isStreaming && !isPlaying) {
                AssistantMessageActions(
                    content = message.content,
                    canRetry = canRetry,
                    onCopy = onCopy,
                    onRetry = { onRetry(message) },
                )
            }
        }
    }
}

@Composable
private fun rememberReplyText(
    message: ChatMessage,
    isStreaming: Boolean,
    playbackAllowed: Boolean,
    finishedNormally: Boolean,
): Pair<String, Boolean> {
    if (!ChatFeatureFlags.lightweightTypewriter) return message.content to false

    val context = LocalContext.current
    val touchExploration = remember(context) {
        context.getSystemService(AccessibilityManager::class.java)?.isTouchExplorationEnabled == true
    }
    val reduceMotion = Settings.Global.getFloat(
        context.contentResolver,
        Settings.Global.ANIMATOR_DURATION_SCALE,
        1f,
    ) == 0f
    val animated = playbackAllowed && !touchExploration && !reduceMotion
    val playback = remember(message.id) { ChatTextPlayback(message.id) }
    var wasStreaming by remember(message.id) { mutableStateOf(isStreaming) }
    var displayText by remember(message.id) { mutableStateOf(if (isStreaming) "" else message.content) }
    var isPlaying by remember(message.id) { mutableStateOf(false) }

    LaunchedEffect(message.id, message.content, isStreaming, animated, finishedNormally, message.failure) {
        if (!isStreaming && !wasStreaming && message.content.isEmpty()) return@LaunchedEffect
        if (isStreaming) wasStreaming = true
        val canAnimate = animated && wasStreaming && message.failure == null
        playback.receive(message.content, animated = canAnimate)
        if (!isStreaming && wasStreaming) {
            if (finishedNormally && canAnimate) playback.finish(SystemClock.uptimeMillis() / 1000.0)
            else playback.revealAll()
        }
        displayText = playback.visibleText
        isPlaying = playback.hasPendingText
        if (playback.hasPendingText) {
            playback.resume(SystemClock.uptimeMillis() / 1000.0)
            while (playback.hasPendingText) {
                delay(32)
                playback.advance(SystemClock.uptimeMillis() / 1000.0)
                displayText = playback.visibleText
                isPlaying = playback.hasPendingText
            }
        }
    }
    return displayText to isPlaying
}

@Composable
private fun FailureCard(
    message: String,
    retryable: Boolean,
    enabled: Boolean,
    onRetry: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.error.copy(alpha = 0.08f),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("处理失败", fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.error)
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (retryable) {
                OutlinedButton(enabled = enabled, onClick = onRetry) { Text("重新提问") }
            }
        }
    }
}

@Composable
private fun AssistantMessageActions(
    content: String,
    canRetry: Boolean,
    onCopy: () -> Unit,
    onRetry: () -> Unit,
) {
    val context = LocalContext.current
    var copied by remember(content) { mutableStateOf(false) }
    var copyCount by remember(content) { mutableStateOf(0) }
    LaunchedEffect(copyCount) {
        if (copyCount > 0) {
            delay(3000)
            copied = false
        }
    }
    Row {
        Box(Modifier.size(48.dp).semantics { contentDescription = if (copied) "已复制" else "复制回复" }.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
        ) {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("Crest 回复", content)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                clip.description.extras = PersistableBundle().apply {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
            }
            clipboard.setPrimaryClip(clip)
            copied = true
            copyCount++
            onCopy()
        }, contentAlignment = Alignment.Center) {
            Crossfade(targetState = copied, animationSpec = tween(if (copied) 150 else 180), label = "复制状态") { isCopied ->
                CrestIcon(
                    if (isCopied) CrestIconKind.CHECK else CrestIconKind.COPY,
                    Modifier.size(17.dp),
                    if (isCopied) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Box(Modifier.size(48.dp).semantics { contentDescription = "分享回复" }.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
        ) {
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, content)
            }
            context.startActivity(Intent.createChooser(share, null))
        }, contentAlignment = Alignment.Center) {
            CrestIcon(CrestIconKind.SHARE, Modifier.size(17.dp), MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Box(Modifier.size(48.dp).semantics { contentDescription = "重试回复" }.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            enabled = canRetry,
            onClick = onRetry,
        ),
            contentAlignment = Alignment.Center) {
            CrestIcon(
                CrestIconKind.REFRESH,
                Modifier.size(17.dp),
                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (canRetry) 1f else .38f),
            )
        }
    }
}

@Composable
private fun ResponseActionButtons(
    actions: List<com.blackwave.crest.core.model.ChatResponseAction>,
    onAction: (com.blackwave.crest.core.model.ChatResponseAction) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        actions.forEach { action ->
            Row(
                Modifier.fillMaxWidth()
                    .background(MaterialTheme.colorScheme.secondary.copy(alpha = .08f), RoundedCornerShape(12.dp))
                    .border(1.dp, MaterialTheme.colorScheme.secondary.copy(alpha = .2f), RoundedCornerShape(12.dp))
                    .clickable { onAction(action) }
                    .padding(horizontal = 14.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(action.label, Modifier.weight(1f), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.secondary, maxLines = 2)
                CrestIcon(CrestIconKind.CHEVRON_RIGHT, Modifier.size(16.dp), MaterialTheme.colorScheme.secondary)
            }
        }
    }
}

private fun responseStatusLabel(status: String?): String = when (status) {
    "partial" -> "结果不完整"
    "empty" -> "暂无数据"
    "unavailable" -> "数据暂不可用"
    "failed" -> "分析失败"
    else -> "结果状态未知"
}
