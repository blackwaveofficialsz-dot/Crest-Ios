package com.blackwave.crest.feature.home

import com.blackwave.crest.ui.localization.L
import com.blackwave.crest.ui.localization.AppLocalization
import com.blackwave.crest.ui.localization.LanguageMode
import androidx.compose.ui.platform.LocalContext

import android.graphics.BitmapFactory
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import com.blackwave.crest.ui.components.CrestAlertDialog as AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.ImeAction
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
    val orientation = androidx.compose.ui.platform.LocalConfiguration.current.orientation
    val scope = rememberCoroutineScope()
    var destination by rememberSaveable { mutableStateOf(HomeDestination.CHAT) }
    var showSettings by remember { mutableStateOf(false) }
    var showInitialPassword by rememberSaveable(user.userId, user.activeWorkspaceId) {
        mutableStateOf(user.tenantId == null && !user.hasPassword)
    }
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

    // Full-width drawer anchors change with chart rotation; never expose the drawer on return.
    LaunchedEffect(orientation) { drawerState.close() }

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
                if (destination == HomeDestination.CHAT) AppHeader(
                    title = when (destination) {
                        HomeDestination.CHAT -> if (controller.activeSessionId == null) L("新对话") else controller.activeTitle
                        HomeDestination.SEARCH -> L("搜索对话")
                        HomeDestination.ANALYTICS -> L("经营分析")
                    },
                    onMenu = { scope.launch { drawerState.open() } },
                    onNewChat = {
                        controller.newChat()
                        destination = HomeDestination.CHAT
                    },
                    onOpenSettings = { showSettings = true },
                )
                if (destination == HomeDestination.CHAT) HorizontalDivider(
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
                    HomeDestination.SEARCH -> SearchScreen(controller, onOpenSidebar = { scope.launch { drawerState.open() } }) {
                        controller.openSession(it)
                        destination = HomeDestination.CHAT
                    }
                    HomeDestination.ANALYTICS -> AnalyticsScreen(
                        session = session,
                        user = user,
                        onOpenSettings = { showSettings = true },
                        onOpenSidebar = { scope.launch { drawerState.open() } },
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
                        Text(L("已复制到剪贴板"), fontSize = 15.sp, fontWeight = FontWeight.Medium)
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
                accountNotice = L("密码设置成功")
            },
        )
    }

    accountNotice?.let { message ->
        AlertDialog(
            onDismissRequest = { accountNotice = null },
            confirmButton = { TextButton(onClick = { accountNotice = null }) { Text(L("好")) } },
            title = { Text(L("操作成功")) },
            text = { Text(message) },
        )
    }

    controller.operationError?.let { message ->
        AlertDialog(
            onDismissRequest = { controller.operationError = null },
            confirmButton = { TextButton(onClick = { controller.operationError = null }) { Text(L("好")) } },
            title = { Text(L("操作失败")) },
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
            CrestCircleButton(CrestIconKind.MENU, L("打开侧边栏"), onMenu)
            Spacer(Modifier.weight(1f))
            CrestCircleButton(CrestIconKind.EDIT, L("新对话"), onNewChat)
            CrestCircleButton(CrestIconKind.PERSON, L("账户"), onOpenSettings)
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
            .clip(CircleShape)
            .semantics { contentDescription = label }
            .clickable(role = Role.Button, onClick = onClick),
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
    val backdropBlur by animateDpAsState(
        targetValue = if (menuTarget != null) 12.dp else 0.dp,
        animationSpec = tween(180),
        label = "history backdrop blur",
    )

    ModalDrawerSheet(
        modifier = Modifier.fillMaxSize(),
        drawerShape = RoundedCornerShape(0.dp),
        drawerContainerColor = sidebarColor,
    ) {
        Column(Modifier.fillMaxSize().blur(backdropBlur).safeDrawingPadding()) {
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
                CrestCircleButton(CrestIconKind.CLOSE, L("关闭侧边栏"), onClose)
            }
            DrawerAction(CrestIconKind.EDIT, L("发起新对话")) {
                controller.newChat()
                onDestination(HomeDestination.CHAT)
            }
            DrawerAction(CrestIconKind.SEARCH, L("搜索对话内容")) { onDestination(HomeDestination.SEARCH) }
            if (showAnalytics) DrawerAction(CrestIconKind.ANALYTICS, L("经营分析")) { onDestination(HomeDestination.ANALYTICS) }
            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
                color = MaterialTheme.colorScheme.outline,
            )
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L("最近"), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
                            L("暂无对话记录"),
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
                Text(username.ifBlank { L("账户") }, modifier = Modifier.weight(1f), fontWeight = FontWeight.Medium, maxLines = 1)
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
                    delay(90)
                    renameDraft = item.title
                    renameTarget = item
                }
            },
            onDelete = {
                menuTarget = null
                scope.launch {
                    delay(90)
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
                ) { Text(L("保存"), color = MaterialTheme.colorScheme.secondary) }
            },
            dismissButton = { TextButton(onClick = { renameTarget = null }) { Text(L("取消"), color = MaterialTheme.colorScheme.secondary) } },
            title = { Text(L("重命名对话")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(L("输入新的对话名称"))
                    OutlinedTextField(
                        value = renameDraft,
                        onValueChange = { renameDraft = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text(L("对话名称")) },
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
                }) { Text(L("确认"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text(L("取消"), color = MaterialTheme.colorScheme.secondary) } },
            title = { Text(L("要删除对话吗？")) },
            text = { Text(L("这个对话将不再显示在此处，此操作还会从你的活动记录中删除相关的活动记录。")) },
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
                onClickLabel = L("打开对话"),
                onLongClickLabel = L("更多操作"),
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
    val dark = surface.luminance() < 0.5f
    val glass = surface.copy(alpha = if (dark) 0.92f else 0.88f)
    val glassEdge = BorderStroke(
        1.dp,
        Brush.verticalGradient(
            listOf(
                Color.White.copy(alpha = if (dark) 0.32f else 0.86f),
                MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
            ),
        ),
    )
    val visible = remember { MutableTransitionState(false) }
    var afterClose by remember { mutableStateOf<(() -> Unit)?>(null) }
    LaunchedEffect(Unit) { visible.targetState = true }
    LaunchedEffect(visible.isIdle, visible.currentState) {
        if (visible.isIdle && !visible.currentState) {
            afterClose?.invoke()
            afterClose = null
        }
    }
    fun closeThen(action: () -> Unit) {
        if (afterClose == null) {
            afterClose = action
            visible.targetState = false
        }
    }
    Dialog(onDismissRequest = { closeThen(onDismiss) }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        AnimatedVisibility(
            visibleState = visible,
            enter = fadeIn(tween(170)) + scaleIn(
                initialScale = 0.93f,
                animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMedium),
            ),
            exit = fadeOut(tween(120)) + scaleOut(targetScale = 0.97f, animationSpec = tween(120)),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Surface(
                    shape = RoundedCornerShape(24.dp),
                    color = glass,
                    border = glassEdge,
                    shadowElevation = 16.dp,
                ) {
                    SessionRowContent(item, selected)
                }
                Surface(
                    shape = RoundedCornerShape(22.dp),
                    color = glass,
                    border = glassEdge,
                    shadowElevation = 20.dp,
                ) {
                    Column {
                        HistoryMenuAction(if (item.isPinned) L("取消固定") else L("固定"), CrestIconKind.PIN) { closeThen(onPin) }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.65f))
                        HistoryMenuAction(L("重命名"), CrestIconKind.EDIT) { closeThen(onRename) }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.65f))
                        HistoryMenuAction(L("删除"), CrestIconKind.DELETE, destructive = true) { closeThen(onDelete) }
                    }
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
private fun SearchScreen(controller: ChatController, onOpenSidebar: () -> Unit, onOpen: (String) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val listState = rememberLazyListState()
    LaunchedEffect(Unit) { focus.requestFocus() }
    LaunchedEffect(listState.isScrollInProgress) { if (listState.isScrollInProgress) keyboard?.hide() }
    val results = remember(query, controller.sessions.toList()) {
        val keyword = query.trim()
        if (keyword.isEmpty()) controller.sessions.toList()
        else controller.sessions.filter { it.title.contains(keyword, ignoreCase = true) }
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CrestCircleButton(CrestIconKind.MENU, L("打开侧边栏")) { keyboard?.hide(); onOpenSidebar() }
            Row(Modifier.weight(1f).height(44.dp).background(MaterialTheme.colorScheme.surface, RoundedCornerShape(12.dp)).padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CrestIcon(CrestIconKind.SEARCH, Modifier.size(18.dp), MaterialTheme.colorScheme.onSurfaceVariant)
                BasicTextField(query, { query = it }, Modifier.weight(1f).focusRequester(focus).semantics { contentDescription = L("搜索对话内容") },
                    singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { keyboard?.hide() }),
                    decorationBox = { inner -> Box { if (query.isEmpty()) Text(L("搜索对话内容"), color = MaterialTheme.colorScheme.onSurfaceVariant); inner() } })
                if (query.isNotEmpty()) Box(Modifier.size(30.dp).clip(CircleShape)
                    .semantics { contentDescription = L("清除搜索内容") }.clickable(role = Role.Button) { query = ""; focus.requestFocus() }, contentAlignment = Alignment.Center) {
                    CrestIcon(CrestIconKind.CLOSE, Modifier.size(14.dp), MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outline)
        Text(L(if (query.trim().isEmpty()) "最近" else "搜索结果"), Modifier.padding(horizontal = 18.dp, vertical = 12.dp), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        when {
            controller.isLoadingHistory && controller.sessions.isEmpty() ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            controller.historyError != null && controller.sessions.isEmpty() ->
                ErrorState(controller.historyError!!, controller::loadHistory)
            results.isEmpty() ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(L("没有匹配的对话"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            else -> LazyColumn(state = listState, contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 8.dp, end = 8.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(results, key = { it.sessionId }) { item ->
                    val active = item.sessionId == controller.activeSessionId
                    Box(Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(25.dp))
                        .background(if (active) MaterialTheme.colorScheme.surface else Color.Transparent)
                        .semantics { selected = active }.clickable { keyboard?.hide(); onOpen(item.sessionId) }.padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
                        Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
    var showLanguageMenu by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val themeBackdropBlur by animateDpAsState(
        targetValue = if (showThemeMenu || showLanguageMenu) 2.dp else 0.dp,
        animationSpec = tween(180),
        label = "theme backdrop blur",
    )

    LaunchedEffect(Unit) {
        session.loadWorkspaces()
        runCatching { session.loadAccountProfile() }
            .onFailure { error = it.userMessage(L("个人资料加载失败")) }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = null,
        containerColor = MaterialTheme.colorScheme.background,
        scrimColor = Color.Black.copy(alpha = 0.45f),
        shape = RoundedCornerShape(topStart = 45.dp, topEnd = 45.dp),
        properties = ModalBottomSheetProperties(
            isAppearanceLightStatusBars = MaterialTheme.colorScheme.background.luminance() > .5f,
            isAppearanceLightNavigationBars = MaterialTheme.colorScheme.background.luminance() > .5f,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .blur(themeBackdropBlur)
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
                    L("设置"),
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
            SettingsSection(L("账户")) {
                SettingsRow(
                    icon = CrestIconKind.PERSON,
                    title = L("个人资料"),
                    value = user.displayName.ifBlank { L("未设置昵称") },
                    onClick = { showProfile = true },
                )
                SettingsDivider()
                SettingsRow(
                    icon = CrestIconKind.LOCK,
                    title = if (user.hasPassword) L("修改密码") else L("设置密码"),
                    onClick = { showPassword = true },
                )
            }
            SettingsSection(L("工作空间")) {
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
                        title = L("暂无可用工作空间"),
                    )
                    else -> session.workspaces.forEachIndexed { index, workspace ->
                        if (index > 0) SettingsDivider()
                        SettingsRow(
                            icon = if (workspace.workspaceId == user.activeWorkspaceId) CrestIconKind.PERSON else CrestIconKind.ANALYTICS,
                            title = workspace.name,
                            subtitle = if (workspace.workspaceId == user.activeWorkspaceId) {
                                if (user.workspaceType == "tenant") user.role else L("个人账号")
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
                                        error = failure.userMessage(L("工作空间切换失败"))
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
                    title = L("加入新团队"),
                    onClick = { showJoinTeam = true },
                )
            }
            SettingsSection(L("外观与语言")) {
                Box {
                    SettingsRow(
                        icon = when (theme.mode) {
                            ThemeMode.SYSTEM -> CrestIconKind.HALF_CIRCLE
                            ThemeMode.LIGHT -> CrestIconKind.THEME
                            ThemeMode.DARK -> CrestIconKind.MOON
                        },
                        title = L("外观"),
                        value = L(theme.mode.title),
                        onClick = { showThemeMenu = true },
                    )
                    DropdownMenu(
                        expanded = showThemeMenu,
                        onDismissRequest = { showThemeMenu = false },
                        modifier = Modifier.width(188.dp).border(
                            1.dp,
                            Brush.verticalGradient(
                                listOf(
                                    Color.White.copy(alpha = if (MaterialTheme.colorScheme.surface.luminance() < 0.5f) 0.28f else 0.85f),
                                    MaterialTheme.colorScheme.outline.copy(alpha = 0.55f),
                                ),
                            ),
                            RoundedCornerShape(20.dp),
                        ),
                        shape = RoundedCornerShape(20.dp),
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 0.dp,
                        shadowElevation = 0.dp,
                    ) {
                        ThemeMode.entries.forEach { mode ->
                            Row(
                                modifier = Modifier.fillMaxWidth().height(40.dp).clickable {
                                    showThemeMenu = false
                                    theme.updateMode(mode)
                                }.padding(horizontal = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Box(Modifier.width(18.dp), contentAlignment = Alignment.CenterStart) {
                                    if (theme.mode == mode) CrestIcon(
                                        CrestIconKind.CHECK,
                                        Modifier.size(14.dp),
                                        MaterialTheme.colorScheme.onSurface,
                                    )
                                }
                                CrestIcon(
                                    when (mode) {
                                        ThemeMode.SYSTEM -> CrestIconKind.HALF_CIRCLE
                                        ThemeMode.LIGHT -> CrestIconKind.THEME
                                        ThemeMode.DARK -> CrestIconKind.MOON
                                    },
                                    Modifier.size(18.dp),
                                    MaterialTheme.colorScheme.secondary,
                                )
                                Spacer(Modifier.width(10.dp))
                                Text(L(mode.title), fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
                            }
                        }
                    }
                }
                SettingsDivider()
                Box {
                    SettingsRow(icon = CrestIconKind.GLOBE, title = L("语言"), value = L(AppLocalization.mode.title), onClick = { showLanguageMenu = true })
                    DropdownMenu(
                        expanded = showLanguageMenu,
                        onDismissRequest = { showLanguageMenu = false },
                        modifier = Modifier.width(188.dp).border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(20.dp)),
                        shape = RoundedCornerShape(20.dp), containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 0.dp, shadowElevation = 0.dp,
                    ) {
                        LanguageMode.entries.forEach { language ->
                            Row(Modifier.fillMaxWidth().height(44.dp).clickable {
                                showLanguageMenu = false
                                AppLocalization.update(context, language)
                            }.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.width(28.dp)) {
                                    if (language == AppLocalization.mode) CrestIcon(CrestIconKind.CHECK, Modifier.size(14.dp))
                                }
                                Text(L(language.title), fontSize = 15.sp)
                            }
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
                    Text(L("退出登录"), color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Medium)
                }
            }
        }
    }

    if (showProfile) {
        ProfileDialog(
            initialDisplayName = user.displayName.ifBlank { user.username },
            avatarData = session.avatarData,
            onDismiss = { showProfile = false },
            onSave = { value -> session.updateDisplayName(value) },
            onAvatarUpload = { bytes -> session.updateAvatar(bytes) },
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
            onSuccess = { requiresRelogin ->
                showPassword = false
                if (requiresRelogin) { onDismiss(); session.signOut() }
                else notice = L("密码设置成功")
            },
        )
    }

    if (showJoinTeam) {
        JoinTeamDialog(
            onDismiss = { showJoinTeam = false },
            onSubmit = { session.acceptInvitation(it) },
            onSuccess = { showJoinTeam = false },
        )
    }

    error?.let { message ->
        AlertDialog(
            onDismissRequest = { error = null },
            confirmButton = { TextButton(onClick = { error = null }) { Text(L("好")) } },
            title = { Text(L("操作失败")) },
            text = { Text(message) },
        )
    }

    notice?.let { message ->
        AlertDialog(
            onDismissRequest = { notice = null },
            confirmButton = { TextButton(onClick = { notice = null }) { Text(L("好")) } },
            title = { Text(L("操作成功")) },
            text = { Text(message) },
        )
    }
}

@Composable
private fun PasswordDialog(
    hasPassword: Boolean,
    onDismiss: () -> Unit,
    onSubmit: suspend (String, String) -> Unit,
    onSuccess: (Boolean) -> Unit,
) {
    val changingPassword = remember { hasPassword }
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    var oldPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var isSubmitting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var succeeded by remember { mutableStateOf(false) }
    val valid = canSubmitPassword(changingPassword, oldPassword, newPassword, confirmation)

    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    Dialog(
        onDismissRequest = { if (!isSubmitting && !succeeded) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
          Surface(
            modifier = Modifier.fillMaxWidth().fillMaxHeight(0.97f),
            shape = RoundedCornerShape(topStart = 36.dp, topEnd = 36.dp),
            color = if (dark) Color(0xFF1C1C1E) else Color(0xFFF4F3F9),
          ) {
            Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    SettingsToolbarCircle(CrestIconKind.CLOSE, enabled = !isSubmitting && !succeeded, onClick = onDismiss)
                    Text(if (changingPassword) L("修改密码") else L("设置密码"), fontWeight = FontWeight.SemiBold)
                    SettingsToolbarCircle(
                        CrestIconKind.CHECK,
                        enabled = valid && !isSubmitting && !succeeded,
                        tint = MaterialTheme.colorScheme.secondary,
                    ) {
                        if (!isSubmitting && valid && !succeeded) {
                          isSubmitting = true
                          focusManager.clearFocus()
                          scope.launch {
                            try {
                                onSubmit(oldPassword, newPassword)
                                if (changingPassword) succeeded = true else onSuccess(false)
                            } catch (failure: Exception) {
                                if (failure is kotlinx.coroutines.CancellationException) throw failure
                                error = failure.userMessage(if (changingPassword) L("密码修改失败") else L("密码设置失败"))
                            } finally {
                                isSubmitting = false
                            }
                          }
                        }
                    }
                }
                if (isSubmitting) CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally).padding(top = 16.dp).size(20.dp), strokeWidth = 2.dp)
                if (changingPassword) {
                    SettingsFieldLabel(L("当前密码"))
                    Surface(shape = RoundedCornerShape(22.dp), color = MaterialTheme.colorScheme.surface) {
                        SettingsFormInput(oldPassword, { oldPassword = it }, L("输入当前密码"), password = true, enabled = !isSubmitting)
                    }
                }
                SettingsFieldLabel(L("新密码"))
                Surface(shape = RoundedCornerShape(22.dp), color = MaterialTheme.colorScheme.surface) {
                    Column {
                        SettingsFormInput(newPassword, { newPassword = it }, L("7 至 16 位新密码"), password = true, enabled = !isSubmitting)
                        HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outline.copy(alpha = 0.55f))
                        SettingsFormInput(confirmation, { confirmation = it }, L("再次输入新密码"), password = true, enabled = !isSubmitting)
                    }
                }
                passwordValidationMessage(newPassword, confirmation)?.let {
                    Text(L(it), modifier = Modifier.padding(start = 12.dp, top = 8.dp), color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                }
            }
          }
        }
    }
    error?.let { message -> AlertDialog(onDismissRequest = { error = null },
        title = { Text(L(if (changingPassword) "密码修改失败" else "密码设置失败")) }, text = { Text(message) },
        confirmButton = { TextButton(onClick = { error = null }) { Text(L("好")) } }) }
    if (succeeded) AlertDialog(onDismissRequest = {}, title = { Text(L("密码修改成功")) },
        text = { Text(L("为了保护账号安全，请使用新密码重新登录")) },
        confirmButton = { TextButton(onClick = { onSuccess(true) }) { Text(L("重新登录")) } })
}

@Composable
private fun JoinTeamDialog(
    onDismiss: () -> Unit,
    onSubmit: suspend (String) -> String,
    onSuccess: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var isSubmitting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var successMessage by remember { mutableStateOf<String?>(null) }
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val canJoin = code.trim().isNotEmpty() && !isSubmitting && successMessage == null
    val windowHeight = androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.height
    val sheetHeight = with(androidx.compose.ui.platform.LocalDensity.current) { (windowHeight / 2).toDp() }
    val submit: () -> Unit = {
        if (canJoin) {
            isSubmitting = true
            focusManager.clearFocus()
            scope.launch {
                try { successMessage = onSubmit(code.trim()).ifBlank { L("已加入团队") } }
                catch (failure: Exception) {
                    if (failure is kotlinx.coroutines.CancellationException) throw failure
                    error = failure.userMessage(L("加入团队失败"))
                } finally { isSubmitting = false }
            }
        }
    }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    Dialog(
        onDismissRequest = { if (!isSubmitting && successMessage == null) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(Modifier.fillMaxSize().imePadding(), contentAlignment = Alignment.BottomCenter) {
            Surface(
                modifier = Modifier.fillMaxWidth(0.96f).height(sheetHeight),
                shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp),
                color = MaterialTheme.colorScheme.background,
            ) {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
                    Box(Modifier.align(Alignment.CenterHorizontally).padding(top = 7.dp).size(36.dp, 5.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .3f), CircleShape))
                    Box(Modifier.fillMaxWidth().padding(top = 8.dp).height(44.dp), contentAlignment = Alignment.Center) {
                        TextButton(modifier = Modifier.align(Alignment.CenterStart).background(MaterialTheme.colorScheme.surface, CircleShape),
                            enabled = !isSubmitting && successMessage == null, onClick = onDismiss) { Text(L("取消")) }
                        Text(L("加入新团队"), fontWeight = FontWeight.SemiBold)
                    }
                    Text(L("邀请码"), Modifier.padding(top = 20.dp, bottom = 12.dp), fontWeight = FontWeight.SemiBold)
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                        color = MaterialTheme.colorScheme.surface,
                    ) {
                        SettingsFormInput(code, { code = it }, L("输入邮件中的邀请码"), modifier = Modifier.focusRequester(focusRequester), enabled = !isSubmitting, fieldHeight = 52.dp,
                            imeAction = ImeAction.Send, keyboardActions = KeyboardActions(onSend = { submit() }))
                    }
                    Text(
                        L("邀请码区分大小写，验证成功后即可加入对应工作空间。"),
                        modifier = Modifier.padding(top = 8.dp),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 20.dp).height(52.dp).clip(CircleShape)
                            .background(if (canJoin || isSubmitting) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))
                            .clickable(enabled = canJoin, role = Role.Button, onClick = submit),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (isSubmitting) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                        else {
                            val tint = if (canJoin) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                            CrestIcon(CrestIconKind.TEAM, Modifier.size(20.dp), tint)
                            Spacer(Modifier.width(8.dp))
                            Text(L("加入团队"), color = tint, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }
    }
    error?.let { message -> AlertDialog(onDismissRequest = { error = null }, title = { Text(L("加入团队失败")) }, text = { Text(message) },
        confirmButton = { TextButton(onClick = { error = null }) { Text(L("好")) } }) }
    successMessage?.let { message -> AlertDialog(onDismissRequest = onSuccess, title = { Text(L("已加入团队")) }, text = { Text(message) },
        confirmButton = { TextButton(onClick = onSuccess) { Text(L("好")) } }) }
}

@Composable
private fun SettingsToolbarCircle(
    icon: CrestIconKind,
    enabled: Boolean,
    tint: Color = MaterialTheme.colorScheme.onSurface,
    onClick: () -> Unit,
) {
    Surface(onClick = onClick, enabled = enabled, modifier = Modifier.size(40.dp).semantics { contentDescription = L(if (icon == CrestIconKind.CLOSE) "取消" else "完成") }, shape = CircleShape, color = MaterialTheme.colorScheme.surface) {
        Box(contentAlignment = Alignment.Center) {
            CrestIcon(icon, Modifier.size(18.dp), tint.copy(alpha = if (enabled) 1f else 0.35f))
        }
    }
}

@Composable
private fun SettingsFieldLabel(label: String) {
    Text(
        label,
        modifier = Modifier.padding(start = 12.dp, top = 24.dp, bottom = 10.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontSize = 14.sp,
    )
}

@Composable
private fun SettingsFormInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    password: Boolean = false,
    enabled: Boolean = true,
    imeAction: ImeAction = ImeAction.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    fieldHeight: androidx.compose.ui.unit.Dp = 48.dp,
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        enabled = enabled,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
            keyboardType = if (password) KeyboardType.Password else KeyboardType.Text, imeAction = imeAction),
        keyboardActions = keyboardActions,
        visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
        modifier = Modifier.fillMaxWidth().height(fieldHeight).padding(horizontal = 16.dp).then(modifier),
        decorationBox = { inner ->
            Box(contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                inner()
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
internal fun AccountAvatar(
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
        Button(onClick = onRetry) { Text(L("重试")) }
    }
}
