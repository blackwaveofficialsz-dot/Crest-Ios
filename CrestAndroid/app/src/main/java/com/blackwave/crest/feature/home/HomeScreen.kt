package com.blackwave.crest.feature.home

import android.graphics.BitmapFactory
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.blackwave.crest.core.model.ChatSessionSummary
import com.blackwave.crest.core.session.SessionStore
import com.blackwave.crest.core.session.SessionUser
import com.blackwave.crest.core.session.userMessage
import com.blackwave.crest.feature.analytics.AnalyticsScreen
import com.blackwave.crest.feature.chat.ChatController
import com.blackwave.crest.feature.chat.ChatScreen
import com.blackwave.crest.ui.theme.ThemeController
import com.blackwave.crest.ui.theme.CrestRoundedFontFamily
import com.blackwave.crest.ui.theme.ThemeMode
import com.blackwave.crest.ui.components.CrestIcon
import com.blackwave.crest.ui.components.CrestIconKind
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class HomeDestination { CHAT, SEARCH, ANALYTICS }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    session: SessionStore,
    user: SessionUser,
    theme: ThemeController,
) {
    val controller = remember(user.userId, user.activeWorkspaceId) { ChatController(session) }
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    var destination by rememberSaveable { mutableStateOf(HomeDestination.CHAT) }
    var showSettings by remember { mutableStateOf(false) }
    var showInitialPassword by rememberSaveable(user.userId, user.activeWorkspaceId) {
        mutableStateOf(user.tenantId == null && !user.hasPassword)
    }
    var accountError by remember { mutableStateOf<String?>(null) }
    var accountNotice by remember { mutableStateOf<String?>(null) }
    var copyToastCount by remember { mutableStateOf(0) }
    var showCopyToast by remember { mutableStateOf(false) }

    LaunchedEffect(copyToastCount) {
        if (copyToastCount > 0) {
            showCopyToast = true
            delay(3000)
            showCopyToast = false
        }
    }

    DisposableEffect(controller) { onDispose(controller::close) }

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            CrestDrawer(
                controller = controller,
                showAnalytics = user.workspaceType == "tenant",
                username = user.displayName.ifBlank { user.username },
                avatarData = session.avatarData,
                onDestination = { target ->
                    destination = target
                    scope.launch { drawerState.close() }
                },
                onSettings = {
                    showSettings = true
                    scope.launch { drawerState.close() }
                },
                onClose = { scope.launch { drawerState.close() } },
            )
        },
    ) {
        Box(Modifier.fillMaxSize().safeDrawingPadding()) {
            Column(Modifier.fillMaxSize()) {
                AppHeader(
                    title = when (destination) {
                        HomeDestination.CHAT -> controller.activeTitle
                        HomeDestination.SEARCH -> "搜索对话"
                        HomeDestination.ANALYTICS -> "经营分析"
                    },
                    onMenu = { scope.launch { drawerState.open() } },
                    onNewChat = {
                        controller.newChat()
                        destination = HomeDestination.CHAT
                    },
                    onOpenSettings = { showSettings = true },
                )
                HorizontalDivider(
                    thickness = 0.5.dp,
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.75f),
                )
                when (destination) {
                    HomeDestination.CHAT -> ChatScreen(
                        controller,
                        isTenant = user.workspaceType == "tenant",
                        onCopy = { copyToastCount++ },
                        playbackAllowed = drawerState.isClosed && !showSettings,
                    )
                    HomeDestination.SEARCH -> SearchScreen(controller) {
                        controller.openSession(it)
                        destination = HomeDestination.CHAT
                    }
                    HomeDestination.ANALYTICS -> AnalyticsScreen(
                        session = session,
                        user = user,
                        onOpenSettings = { showSettings = true },
                    )
                }
            }
            AnimatedVisibility(
                visible = showCopyToast,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
                enter = slideInVertically(tween(280), initialOffsetY = { -it }) + fadeIn(tween(280)),
                exit = slideOutVertically(tween(200), targetOffsetY = { -it }) + fadeOut(tween(200)),
            ) {
                Surface(
                    modifier = Modifier.height(44.dp).semantics { liveRegion = LiveRegionMode.Polite },
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surface,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    shadowElevation = 12.dp,
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier.size(16.dp).background(MaterialTheme.colorScheme.onSurface, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            CrestIcon(CrestIconKind.CHECK, Modifier.size(11.dp), MaterialTheme.colorScheme.surface)
                        }
                        Spacer(Modifier.width(6.dp))
                        Text("已复制到剪贴板", fontSize = 15.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }

    if (showSettings) {
        SettingsSheet(
            session = session,
            user = user,
            theme = theme,
            onDismiss = { showSettings = false },
        )
    }

    if (showInitialPassword && !user.hasPassword && !showSettings) {
        PasswordDialog(
            hasPassword = false,
            onDismiss = { showInitialPassword = false },
            onSubmit = { _, newPassword -> session.setInitialPassword(newPassword) },
            onSuccess = {
                showInitialPassword = false
                accountNotice = "密码设置成功"
            },
            onError = { accountError = it },
        )
    }

    accountError?.let { message ->
        AlertDialog(
            onDismissRequest = { accountError = null },
            confirmButton = { TextButton(onClick = { accountError = null }) { Text("好") } },
            title = { Text("密码设置失败") },
            text = { Text(message) },
        )
    }

    accountNotice?.let { message ->
        AlertDialog(
            onDismissRequest = { accountNotice = null },
            confirmButton = { TextButton(onClick = { accountNotice = null }) { Text("好") } },
            title = { Text("操作成功") },
            text = { Text(message) },
        )
    }

    controller.operationError?.let { message ->
        AlertDialog(
            onDismissRequest = { controller.operationError = null },
            confirmButton = { TextButton(onClick = { controller.operationError = null }) { Text("好") } },
            title = { Text("操作失败") },
            text = { Text(message) },
        )
    }
}

@Composable
private fun AppHeader(
    title: String,
    onMenu: () -> Unit,
    onNewChat: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Box(modifier = Modifier.fillMaxWidth().height(56.dp)) {
        Text(
            title,
            modifier = Modifier.align(Alignment.Center).width(160.dp),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Row(
            modifier = Modifier.fillMaxSize().padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CrestCircleButton(CrestIconKind.MENU, "打开侧边栏", onMenu)
            Spacer(Modifier.weight(1f))
            CrestCircleButton(CrestIconKind.EDIT, "新对话", onNewChat)
            CrestCircleButton(CrestIconKind.PERSON, "账户", onOpenSettings)
        }
    }
}

@Composable
private fun CrestCircleButton(kind: CrestIconKind, label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .padding(3.dp)
            .shadow(
                elevation = 8.dp,
                shape = CircleShape,
                ambientColor = MaterialTheme.colorScheme.onBackground.copy(alpha = .06f),
                spotColor = MaterialTheme.colorScheme.onBackground.copy(alpha = .07f),
            )
            .background(MaterialTheme.colorScheme.surface.copy(alpha = .68f), CircleShape)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = .38f), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        CrestIcon(kind, Modifier.size(22.dp), MaterialTheme.colorScheme.onBackground)
    }
}

@Composable
private fun CrestDrawer(
    controller: ChatController,
    showAnalytics: Boolean,
    username: String,
    avatarData: ByteArray?,
    onDestination: (HomeDestination) -> Unit,
    onSettings: () -> Unit,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var menuTarget by remember { mutableStateOf<ChatSessionSummary?>(null) }
    var renameTarget by remember { mutableStateOf<ChatSessionSummary?>(null) }
    var renameDraft by remember { mutableStateOf("") }
    var deleteTarget by remember { mutableStateOf<ChatSessionSummary?>(null) }
    val sidebarColor = if (MaterialTheme.colorScheme.background == Color(0xFF212121)) {
        Color(0xFF171717)
    } else {
        Color(0xFFF9F9F9)
    }

    ModalDrawerSheet(
        modifier = Modifier.fillMaxSize(),
        drawerShape = RoundedCornerShape(0.dp),
        drawerContainerColor = sidebarColor,
    ) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 10.dp, bottom = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Crest",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = CrestRoundedFontFamily,
                )
                Spacer(Modifier.weight(1f))
                CrestCircleButton(CrestIconKind.CLOSE, "关闭侧边栏", onClose)
            }
            DrawerAction(CrestIconKind.EDIT, "发起新对话") {
                controller.newChat()
                onDestination(HomeDestination.CHAT)
            }
            DrawerAction(CrestIconKind.SEARCH, "搜索对话内容") { onDestination(HomeDestination.SEARCH) }
            if (showAnalytics) DrawerAction(CrestIconKind.ANALYTICS, "经营分析") { onDestination(HomeDestination.ANALYTICS) }
            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
                color = MaterialTheme.colorScheme.outline,
            )
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("最近", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.weight(1f))
                Box(
                    modifier = Modifier.size(44.dp).clickable(enabled = !controller.isLoadingHistory) { controller.loadHistory() },
                    contentAlignment = Alignment.Center,
                ) {
                    CrestIcon(CrestIconKind.REFRESH, Modifier.size(18.dp), MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when {
                    controller.isLoadingHistory && controller.sessions.isEmpty() ->
                        CircularProgressIndicator(Modifier.align(Alignment.Center).size(28.dp))
                    controller.historyError != null && controller.sessions.isEmpty() ->
                        ErrorState(controller.historyError!!, controller::loadHistory, Modifier.align(Alignment.Center))
                    controller.sessions.isEmpty() ->
                        Text(
                            "暂无对话记录",
                            modifier = Modifier.align(Alignment.Center),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    else -> LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        items(controller.sessions, key = { it.sessionId }) { item ->
                            SessionDrawerRow(
                                item = item,
                                selected = item.sessionId == controller.activeSessionId,
                                onOpen = {
                                    controller.openSession(item.sessionId)
                                    onDestination(HomeDestination.CHAT)
                                },
                                onMore = { menuTarget = item },
                            )
                        }
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onSettings)
                    .padding(start = 16.dp, end = 10.dp, top = 20.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                AccountAvatar(avatarData, username.take(1).uppercase(), 34.dp)
                Text(username.ifBlank { "账户" }, modifier = Modifier.weight(1f), fontWeight = FontWeight.Medium, maxLines = 1)
                Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                    CrestIcon(CrestIconKind.SETTINGS, Modifier.size(22.dp), MaterialTheme.colorScheme.onBackground)
                }
            }
        }
    }

    menuTarget?.let { item ->
        HistoryContextMenuDialog(
            item = item,
            selected = item.sessionId == controller.activeSessionId,
            onDismiss = { menuTarget = null },
            onPin = {
                menuTarget = null
                controller.togglePin(item)
            },
            onRename = {
                menuTarget = null
                scope.launch {
                    delay(180)
                    renameDraft = item.title
                    renameTarget = item
                }
            },
            onDelete = {
                menuTarget = null
                scope.launch {
                    delay(180)
                    deleteTarget = item
                }
            },
        )
    }

    renameTarget?.let { item ->
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            confirmButton = {
                TextButton(
                    enabled = renameDraft.trim().isNotEmpty() && renameDraft.trim() != item.title,
                    onClick = {
                        controller.rename(item, renameDraft)
                        renameTarget = null
                    },
                ) { Text("保存", color = MaterialTheme.colorScheme.secondary) }
            },
            dismissButton = { TextButton(onClick = { renameTarget = null }) { Text("取消", color = MaterialTheme.colorScheme.secondary) } },
            title = { Text("重命名对话") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("输入新的对话名称")
                    OutlinedTextField(
                        value = renameDraft,
                        onValueChange = { renameDraft = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("对话名称") },
                        singleLine = true,
                        shape = RoundedCornerShape(14.dp),
                    )
                }
            },
            shape = RoundedCornerShape(28.dp),
            containerColor = MaterialTheme.colorScheme.surface,
            tonalElevation = 0.dp,
        )
    }

    deleteTarget?.let { item ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            confirmButton = {
                TextButton(onClick = {
                    controller.delete(item)
                    deleteTarget = null
                }) { Text("确认", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text("取消", color = MaterialTheme.colorScheme.secondary) } },
            title = { Text("要删除对话吗？") },
            text = { Text("这个对话将不再显示在此处，此操作还会从你的活动记录中删除相关的活动记录。") },
            shape = RoundedCornerShape(28.dp),
            containerColor = MaterialTheme.colorScheme.surface,
            tonalElevation = 0.dp,
        )
    }
}

@Composable
private fun DrawerAction(icon: CrestIconKind, label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().height(52.dp).clickable(onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CrestIcon(icon, Modifier.size(22.dp), MaterialTheme.colorScheme.onSurfaceVariant)
        Text(label, color = if (icon == CrestIconKind.EDIT) MaterialTheme.colorScheme.onBackground else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SessionDrawerRow(
    item: ChatSessionSummary,
    selected: Boolean,
    onOpen: () -> Unit,
    onMore: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) 0.985f else 1f, label = "history press")
    val rowColor = when {
        isPressed -> MaterialTheme.colorScheme.onBackground.copy(alpha = 0.065f)
        selected -> MaterialTheme.colorScheme.onBackground.copy(alpha = 0.03f)
        else -> Color.Transparent
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .scale(scale)
            .background(rowColor, RoundedCornerShape(24.dp))
            .combinedClickable(
                interactionSource = interactionSource,
                indication = null,
                onClickLabel = "打开对话",
                onLongClickLabel = "更多操作",
                onClick = onOpen,
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onMore()
                },
            ),
    ) {
        SessionRowContent(item, selected)
    }
}

@Composable
private fun SessionRowContent(item: ChatSessionSummary, selected: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            item.title,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
        )
        if (item.isPinned) CrestIcon(
            CrestIconKind.PIN,
            Modifier.size(14.dp),
            MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun HistoryContextMenuDialog(
    item: ChatSessionSummary,
    selected: Boolean,
    onDismiss: () -> Unit,
    onPin: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    val surface = MaterialTheme.colorScheme.surface
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Surface(
                shape = RoundedCornerShape(24.dp),
                color = surface,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.55f)),
                shadowElevation = 16.dp,
            ) {
                SessionRowContent(item, selected)
            }
            Surface(
                shape = RoundedCornerShape(22.dp),
                color = surface,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)),
                shadowElevation = 20.dp,
            ) {
                Column {
                    HistoryMenuAction(if (item.isPinned) "取消固定" else "固定", CrestIconKind.PIN, onClick = onPin)
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.65f))
                    HistoryMenuAction("重命名", CrestIconKind.EDIT, onClick = onRename)
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.65f))
                    HistoryMenuAction("删除", CrestIconKind.DELETE, destructive = true, onClick = onDelete)
                }
            }
        }
    }
}

@Composable
private fun HistoryMenuAction(
    title: String,
    icon: CrestIconKind,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    Row(
        modifier = Modifier.fillMaxWidth().height(54.dp).clickable(onClick = onClick).padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f), fontSize = 16.sp, color = color)
        CrestIcon(icon, Modifier.size(19.dp), color)
    }
}

@Composable
private fun SearchScreen(controller: ChatController, onOpen: (String) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val results = remember(query, controller.sessions.toList()) {
        val keyword = query.trim()
        if (keyword.isEmpty()) controller.sessions.toList()
        else controller.sessions.filter { it.title.contains(keyword, ignoreCase = true) }
    }
    Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("输入对话名称") },
            singleLine = true,
        )
        when {
            controller.isLoadingHistory && controller.sessions.isEmpty() ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            controller.historyError != null && controller.sessions.isEmpty() ->
                ErrorState(controller.historyError!!, controller::loadHistory)
            results.isEmpty() ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("没有匹配的对话", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(results, key = { it.sessionId }) { item ->
                    Surface(
                        modifier = Modifier.fillMaxWidth().clickable { onOpen(item.sessionId) },
                        shape = MaterialTheme.shapes.large,
                        tonalElevation = 1.dp,
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Text(item.title, fontWeight = FontWeight.Medium)
                            Text(
                                if (item.isPinned) "已置顶" else item.updatedAt,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSheet(
    session: SessionStore,
    user: SessionUser,
    theme: ThemeController,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var switchingId by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var showProfile by remember { mutableStateOf(false) }
    var showPassword by remember { mutableStateOf(false) }
    var showJoinTeam by remember { mutableStateOf(false) }
    var showThemeMenu by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        session.loadWorkspaces()
        runCatching { session.loadAccountProfile() }
            .onFailure { error = it.userMessage("个人资料加载失败") }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = null,
        containerColor = MaterialTheme.colorScheme.background,
        scrimColor = Color.Black.copy(alpha = 0.45f),
        shape = RoundedCornerShape(topStart = 45.dp, topEnd = 45.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = 18.dp, bottom = 26.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "设置",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Surface(
                    onClick = onDismiss,
                    modifier = Modifier.size(44.dp),
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.secondary,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        CrestIcon(
                            kind = CrestIconKind.CLOSE,
                            modifier = Modifier.size(17.dp),
                            color = MaterialTheme.colorScheme.onSecondary,
                        )
                    }
                }
            }
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AccountAvatar(
                    data = session.avatarData,
                    initials = user.displayName.ifBlank { user.username }.take(1).uppercase(),
                    size = 82.dp,
                )
                Text(
                    user.displayName.ifBlank { user.username },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            SettingsSection("账户") {
                SettingsRow(
                    icon = CrestIconKind.PERSON,
                    title = "个人资料",
                    value = user.displayName.ifBlank { "未设置昵称" },
                    onClick = { showProfile = true },
                )
                SettingsDivider()
                SettingsRow(
                    icon = CrestIconKind.LOCK,
                    title = if (user.hasPassword) "修改密码" else "设置密码",
                    onClick = { showPassword = true },
                )
            }
            SettingsSection("工作空间") {
                when {
                    session.isLoadingWorkspaces && session.workspaces.isEmpty() -> Box(
                        modifier = Modifier.fillMaxWidth().height(58.dp),
                        contentAlignment = Alignment.Center,
                    ) { CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp) }
                    session.workspaceError != null && session.workspaces.isEmpty() -> {
                        SettingsRow(
                            icon = CrestIconKind.REFRESH,
                            title = session.workspaceError!!,
                            onClick = { scope.launch { session.loadWorkspaces() } },
                        )
                    }
                    session.workspaces.isEmpty() -> SettingsRow(
                        icon = CrestIconKind.TEAM,
                        title = "暂无可用工作空间",
                    )
                    else -> session.workspaces.forEachIndexed { index, workspace ->
                        if (index > 0) SettingsDivider()
                        SettingsRow(
                            icon = if (workspace.workspaceId == user.activeWorkspaceId) CrestIconKind.PERSON else CrestIconKind.ANALYTICS,
                            title = workspace.name,
                            subtitle = if (workspace.workspaceId == user.activeWorkspaceId) {
                                if (user.workspaceType == "tenant") user.role else "个人账号"
                            } else null,
                            selected = workspace.workspaceId == user.activeWorkspaceId,
                            loading = switchingId == workspace.workspaceId,
                            onClick = if (workspace.workspaceId == user.activeWorkspaceId || switchingId != null) null else ({
                                switchingId = workspace.workspaceId
                                scope.launch {
                                    try {
                                        session.switchWorkspace(workspace.workspaceId)
                                        onDismiss()
                                    } catch (failure: Exception) {
                                        error = failure.userMessage("工作空间切换失败")
                                    } finally {
                                        switchingId = null
                                    }
                                }
                            }),
                        )
                    }
                }
                SettingsDivider()
                SettingsRow(
                    icon = CrestIconKind.TEAM,
                    title = "加入新团队",
                    onClick = { showJoinTeam = true },
                )
            }
            SettingsSection("主题") {
                Box {
                    SettingsRow(
                        icon = when (theme.mode) {
                            ThemeMode.SYSTEM -> CrestIconKind.HALF_CIRCLE
                            ThemeMode.LIGHT -> CrestIconKind.THEME
                            ThemeMode.DARK -> CrestIconKind.MOON
                        },
                        title = "外观",
                        value = theme.mode.title,
                        onClick = { showThemeMenu = true },
                    )
                    DropdownMenu(
                        expanded = showThemeMenu,
                        onDismissRequest = { showThemeMenu = false },
                        shape = RoundedCornerShape(20.dp),
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 0.dp,
                        shadowElevation = 18.dp,
                    ) {
                        ThemeMode.entries.forEach { mode ->
                            DropdownMenuItem(
                                text = { Text(mode.title, color = MaterialTheme.colorScheme.onSurface) },
                                leadingIcon = {
                                    CrestIcon(
                                        when (mode) {
                                            ThemeMode.SYSTEM -> CrestIconKind.HALF_CIRCLE
                                            ThemeMode.LIGHT -> CrestIconKind.THEME
                                            ThemeMode.DARK -> CrestIconKind.MOON
                                        },
                                        Modifier.size(19.dp),
                                        MaterialTheme.colorScheme.onSurface,
                                    )
                                },
                                trailingIcon = if (theme.mode == mode) ({
                                    CrestIcon(CrestIconKind.CHECK, Modifier.size(18.dp), MaterialTheme.colorScheme.secondary)
                                }) else null,
                                onClick = {
                                    showThemeMenu = false
                                    theme.updateMode(mode)
                                },
                            )
                        }
                    }
                }
            }
            Surface(
                onClick = { onDismiss(); session.signOut() },
                modifier = Modifier.fillMaxWidth().height(54.dp),
                shape = RoundedCornerShape(22.dp),
                color = MaterialTheme.colorScheme.error.copy(alpha = 0.06f),
            ) {
                Row(
                    modifier = Modifier.fillMaxSize(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CrestIcon(CrestIconKind.EXIT, Modifier.size(20.dp), MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(8.dp))
                    Text("退出登录", color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Medium)
                }
            }
        }
    }

    if (showProfile) {
        DisplayNameDialog(
            initialValue = user.displayName.ifBlank { user.username },
            onDismiss = { showProfile = false },
            onSave = { value -> session.updateDisplayName(value) },
            onError = { error = it },
        )
    }

    if (showPassword) {
        PasswordDialog(
            hasPassword = user.hasPassword,
            onDismiss = { showPassword = false },
            onSubmit = { oldPassword, newPassword ->
                if (user.hasPassword) session.changePassword(oldPassword, newPassword)
                else session.setInitialPassword(newPassword)
            },
            onSuccess = {
                showPassword = false
                notice = if (user.hasPassword) "密码修改成功" else "密码设置成功"
            },
            onError = { error = it },
        )
    }

    if (showJoinTeam) {
        JoinTeamDialog(
            onDismiss = { showJoinTeam = false },
            onSubmit = { session.acceptInvitation(it) },
            onSuccess = { message ->
                showJoinTeam = false
                notice = message.ifBlank { "已加入团队" }
            },
            onError = { error = it },
        )
    }

    error?.let { message ->
        AlertDialog(
            onDismissRequest = { error = null },
            confirmButton = { TextButton(onClick = { error = null }) { Text("好") } },
            title = { Text("操作失败") },
            text = { Text(message) },
        )
    }

    notice?.let { message ->
        AlertDialog(
            onDismissRequest = { notice = null },
            confirmButton = { TextButton(onClick = { notice = null }) { Text("好") } },
            title = { Text("操作成功") },
            text = { Text(message) },
        )
    }
}

@Composable
private fun DisplayNameDialog(
    initialValue: String,
    onDismiss: () -> Unit,
    onSave: suspend (String) -> Unit,
    onError: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var value by remember(initialValue) { mutableStateOf(initialValue) }
    var isSubmitting by remember { mutableStateOf(false) }
    val normalized = value.trim()

    AlertDialog(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        confirmButton = {
            TextButton(
                enabled = normalized.length in 1..30 && !isSubmitting,
                onClick = {
                    scope.launch {
                        isSubmitting = true
                        try {
                            onSave(normalized)
                            onDismiss()
                        } catch (failure: Exception) {
                            onError(failure.userMessage("昵称修改失败"))
                        } finally {
                            isSubmitting = false
                        }
                    }
                },
            ) { Text(if (isSubmitting) "保存中…" else "保存") }
        },
        dismissButton = { TextButton(enabled = !isSubmitting, onClick = onDismiss) { Text("取消") } },
        title = { Text("个人资料") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = value,
                    onValueChange = { if (it.length <= 30) value = it },
                    label = { Text("昵称") },
                    supportingText = { Text("1 至 30 个字符") },
                    singleLine = true,
                )
            }
        },
    )
}

@Composable
private fun PasswordDialog(
    hasPassword: Boolean,
    onDismiss: () -> Unit,
    onSubmit: suspend (String, String) -> Unit,
    onSuccess: () -> Unit,
    onError: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var oldPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var isSubmitting by remember { mutableStateOf(false) }
    val valid = (!hasPassword || oldPassword.isNotEmpty()) &&
        newPassword.length in 7..16 && newPassword == confirmation

    AlertDialog(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        confirmButton = {
            TextButton(
                enabled = valid && !isSubmitting,
                onClick = {
                    scope.launch {
                        isSubmitting = true
                        try {
                            onSubmit(oldPassword, newPassword)
                            onSuccess()
                        } catch (failure: Exception) {
                            onError(failure.userMessage(if (hasPassword) "密码修改失败" else "密码设置失败"))
                        } finally {
                            isSubmitting = false
                        }
                    }
                },
            ) { Text(if (isSubmitting) "提交中…" else "完成") }
        },
        dismissButton = { TextButton(enabled = !isSubmitting, onClick = onDismiss) { Text("取消") } },
        title = { Text(if (hasPassword) "修改密码" else "设置密码") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (hasPassword) {
                    OutlinedTextField(
                        value = oldPassword,
                        onValueChange = { oldPassword = it },
                        label = { Text("当前密码") },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                    )
                }
                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { if (it.length <= 16) newPassword = it },
                    label = { Text("新密码（7 至 16 位）") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                )
                OutlinedTextField(
                    value = confirmation,
                    onValueChange = { if (it.length <= 16) confirmation = it },
                    label = { Text("再次输入新密码") },
                    isError = confirmation.isNotEmpty() && confirmation != newPassword,
                    supportingText = {
                        if (confirmation.isNotEmpty() && confirmation != newPassword) Text("两次输入的密码不一致")
                    },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                )
            }
        },
    )
}

@Composable
private fun JoinTeamDialog(
    onDismiss: () -> Unit,
    onSubmit: suspend (String) -> String,
    onSuccess: (String) -> Unit,
    onError: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var isSubmitting by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        confirmButton = {
            TextButton(
                enabled = code.trim().isNotEmpty() && !isSubmitting,
                onClick = {
                    scope.launch {
                        isSubmitting = true
                        try {
                            onSuccess(onSubmit(code.trim()))
                        } catch (failure: Exception) {
                            onError(failure.userMessage("加入团队失败"))
                        } finally {
                            isSubmitting = false
                        }
                    }
                },
            ) { Text(if (isSubmitting) "加入中…" else "加入") }
        },
        dismissButton = { TextButton(enabled = !isSubmitting, onClick = onDismiss) { Text("取消") } },
        title = { Text("加入新团队") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("输入邀请邮件中的邀请码，邀请码区分大小写。")
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it },
                    label = { Text("邀请码") },
                    singleLine = true,
                )
            }
        },
    )
}

@Composable
private fun SettingsSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text(
            title,
            modifier = Modifier.padding(start = 2.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(22.dp),
            color = MaterialTheme.colorScheme.surfaceVariant,
        ) {
            Column { content() }
        }
    }
}

@Composable
private fun SettingsRow(
    icon: CrestIconKind,
    title: String,
    subtitle: String? = null,
    value: String? = null,
    selected: Boolean = false,
    loading: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val actionModifier = if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier
    Row(
        modifier = actionModifier
            .fillMaxWidth()
            .height(if (subtitle == null) 52.dp else 62.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CrestIcon(
            kind = icon,
            modifier = Modifier.size(20.dp),
            color = if (selected) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                color = if (selected) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            subtitle?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }
        value?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.width(7.dp))
        }
        when {
            loading -> CircularProgressIndicator(Modifier.size(17.dp), strokeWidth = 2.dp)
            selected -> Surface(
                modifier = Modifier.size(18.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.70f),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text("✓", color = MaterialTheme.colorScheme.onSecondary, style = MaterialTheme.typography.labelSmall)
                }
            }
            onClick != null -> CrestIcon(
                CrestIconKind.CHEVRON_RIGHT,
                Modifier.size(15.dp),
                MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SettingsDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(start = 48.dp, end = 16.dp),
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.45f),
    )
}

@Composable
private fun AccountAvatar(
    data: ByteArray?,
    initials: String,
    size: androidx.compose.ui.unit.Dp,
) {
    val image = remember(data) {
        data?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }?.asImageBitmap()
    }
    if (image != null) {
        Image(
            bitmap = image,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(size).clip(CircleShape),
        )
    } else {
        Box(
            modifier = Modifier.size(size).background(MaterialTheme.colorScheme.secondary, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                initials,
                color = MaterialTheme.colorScheme.onSecondary,
                fontSize = (size.value * .39f).sp,
                fontWeight = FontWeight.Medium,
                fontFamily = CrestRoundedFontFamily,
            )
        }
    }
}

@Composable
private fun ErrorState(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(message, color = MaterialTheme.colorScheme.error)
        Button(onClick = onRetry) { Text("重试") }
    }
}
