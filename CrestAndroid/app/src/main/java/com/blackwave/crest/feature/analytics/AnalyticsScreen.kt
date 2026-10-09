package com.blackwave.crest.feature.analytics

import com.blackwave.crest.ui.localization.L
import com.blackwave.crest.ui.localization.AppLocalization

import android.app.DatePickerDialog
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.blackwave.crest.core.session.SessionStore
import com.blackwave.crest.core.model.AnalyticsStoreNode
import com.blackwave.crest.R
import com.blackwave.crest.core.session.SessionUser
import com.blackwave.crest.core.session.userMessage
import com.blackwave.crest.core.network.ApiException
import com.blackwave.crest.ui.components.CrestIcon
import com.blackwave.crest.ui.components.CrestDialogSystemBars
import com.blackwave.crest.ui.components.CrestIconKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnalyticsScreen(session: SessionStore, user: SessionUser, onOpenSettings: () -> Unit, onOpenSidebar: () -> Unit) {
    var module by remember { mutableStateOf(AnalyticsModule.DASHBOARD) }
    var preset by remember { mutableStateOf<AnalyticsPeriod?>(AnalyticsPeriod.CURRENT_MONTH) }
    var range by remember { mutableStateOf(AnalyticsPeriod.CURRENT_MONTH.range()) }
    var stores by remember(user.activeWorkspaceId) { mutableStateOf(emptySet<String>()) }
    var storeNodes by remember(user.activeWorkspaceId) { mutableStateOf(emptyList<AnalyticsStoreNode>()) }
    val options = remember(storeNodes, AppLocalization.locale) { analyticsStoreOptions(storeNodes, AppLocalization.locale) }
    var storeError by remember(user.activeWorkspaceId) { mutableStateOf<String?>(null) }
    var data by remember(user.activeWorkspaceId, range, stores, module) { mutableStateOf(AnalyticsData()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember(user.activeWorkspaceId, range, stores, module) { mutableStateOf<String?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    var lastRefresh by remember { mutableIntStateOf(0) }
    var filter by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<AnalyticsDetail?>(null) }
    var exportBytes by remember { mutableStateOf<ByteArray?>(null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val storeSummary = if (stores.isEmpty()) L("全部门店") else if (stores.size == 1) options.firstOrNull { it.first in stores }?.second ?: L("%lld 家门店", 1) else L("%lld 家门店", stores.size)
    val hasData = when (module) {
        AnalyticsModule.DASHBOARD, AnalyticsModule.ORDERS -> data.overview != null
        AnalyticsModule.PRODUCTS -> data.products != null
        AnalyticsModule.LABOR -> data.labor != null
        AnalyticsModule.ALERTS -> data.alerts != null
    }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        val bytes = exportBytes
        exportBytes = null
        if (uri != null && bytes != null) scope.launch {
            try {
                withContext(Dispatchers.IO) { requireNotNull(context.contentResolver.openOutputStream(uri)).use { it.write(bytes) } }
            } catch (failure: Exception) { error = failure.userMessage(L("导出失败")) }
        }
    }
    LaunchedEffect(user.activeWorkspaceId, user.tenantId) {
        if (user.tenantId == null) return@LaunchedEffect
        try {
            storeNodes = session.authenticated { session.api.analyticsStoreScope(it) }.nodes
        } catch (cancel: CancellationException) { throw cancel }
        catch (failure: Exception) { storeError = failure.userMessage(L("门店范围加载失败")) }
    }
    LaunchedEffect(user.activeWorkspaceId, range, stores, module, refresh) {
        if (user.tenantId == null) return@LaunchedEffect
        loading = true
        error = null
        val keys = stores.sorted()
        val from = range.from.toString()
        val to = range.to.toString()
        val trendEnd = LocalDate.now(ZoneId.of("Asia/Shanghai")).minusDays(1)
        val trendStart = trendEnd.minusDays(29).toString()
        val forceRefresh = refresh != lastRefresh
        lastRefresh = refresh
        val cacheGeneration = session.analyticsCache.generation()
        val cacheScope = listOf(user.userId, user.activeWorkspaceId, module.name, from, to, keys.joinToString(","), trendEnd.toString()).joinToString("\u0000")
        if (forceRefresh) session.analyticsCache.remove(cacheScope)
        val cached = if (forceRefresh) null else session.analyticsCache.read(cacheScope)
        val fresh = cached?.isFresh() == true
        if (fresh) {
            data = cached.value
            if (keys.size > 1 || module !in listOf(AnalyticsModule.DASHBOARD, AnalyticsModule.ORDERS, AnalyticsModule.PRODUCTS)) {
                loading = false
                return@LaunchedEffect
            }
        }
        try {
            when (module) {
                AnalyticsModule.DASHBOARD, AnalyticsModule.ORDERS -> {
                    if (!fresh) data = data.copy(overview = session.authenticated { session.api.analyticsOverview(from, to, forceRefresh, it, keys) })
                    data = data.copy(revenue = session.loadRevenueTrend(user, trendStart, trendEnd.toString(), keys, forceRefresh))
                }
                AnalyticsModule.PRODUCTS -> {
                    if (!fresh) data = data.copy(products = session.authenticated { session.api.analyticsProducts(from, to, keys, it) })
                    val productKey = if (fresh && data.productTrend != null) data.productTrend?.productKey else
                        session.authenticated { session.api.analyticsProducts(trendStart, trendEnd.toString(), keys, it) }.items.firstOrNull()?.productKey
                    data = data.copy(productTrend = productKey?.let { product ->
                        session.loadProductTrend(user, product, trendStart, trendEnd.toString(), keys, forceRefresh)
                    })
                }
                AnalyticsModule.LABOR -> {
                    data = data.copy(labor = session.authenticated { session.api.analyticsLabor(from, to, keys, it) })
                    data = data.copy(laborTrend = session.authenticated { session.api.analyticsLabor(trendStart, trendEnd.toString(), keys, it) })
                }
                AnalyticsModule.ALERTS -> data = data.copy(alerts = session.authenticated { session.api.analyticsAlerts(to, it) }.alerts.filter { stores.isEmpty() || it.shopKey in stores })
            }
            session.analyticsCache.write(cacheScope, data, cacheGeneration, if (fresh) cached.savedAt else System.currentTimeMillis())
        } catch (cancel: CancellationException) { throw cancel }
        catch (failure: Exception) {
            if (failure is ApiException && failure.statusCode in listOf(401, 403)) {
                session.analyticsCache.clear()
                data = AnalyticsData()
                detail = null
            } else if (cached != null) data = cached.value
            error = failure.userMessage(L("经营分析加载失败"))
        }
        finally { loading = false }
    }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 10.dp)) {
            AnalyticsIcon(CrestIconKind.MENU, L("打开侧边栏"), onOpenSidebar, Modifier.align(Alignment.CenterStart))
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(L("经营分析"), fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                Text(L(module.title), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (user.tenantId != null) Row(Modifier.align(Alignment.CenterEnd)) {
                AnalyticsIcon(CrestIconKind.SHARE, L("导出当前经营分析"), {
                    exportBytes = analyticsCsv(data.exportRows(module, range, storeSummary))
                    exporter.launch("Crest-${module.title}-${range.from}-${range.to}.csv")
                }, enabled = hasData && !loading)
                AnalyticsIcon(CrestIconKind.REFRESH, L("刷新经营分析"), { refresh++ }, enabled = !loading)
            }
        }
        Surface(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), shape = RoundedCornerShape(8.dp), border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
            Row(Modifier.padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                AnalyticsModule.entries.forEach { item ->
                    Surface(onClick = { module = item }, modifier = Modifier.weight(1f), shape = RoundedCornerShape(6.dp),
                        color = if (item == module) MaterialTheme.colorScheme.secondary else Color.Transparent,
                        contentColor = if (item == module) Color.White else MaterialTheme.colorScheme.onSurfaceVariant) {
                        Column(Modifier.height(46.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                            CrestIcon(when (item) {
                                AnalyticsModule.DASHBOARD -> CrestIconKind.GRID_GROUP
                                AnalyticsModule.ORDERS -> CrestIconKind.CLIPBOARD
                                AnalyticsModule.PRODUCTS -> CrestIconKind.TAKEOUT
                                AnalyticsModule.LABOR -> CrestIconKind.PEOPLE
                                AnalyticsModule.ALERTS -> CrestIconKind.BELL_BADGE
                            }, Modifier.size(14.dp))
                            Text(L(item.title), fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }
        }
        if (user.tenantId == null) {
            Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(L("切换到团队工作空间"), style = MaterialTheme.typography.titleLarge)
                Text(L("经营分析仅在团队工作空间中展示。请在账户设置中切换团队或加入新团队。"))
                Button(onClick = onOpenSettings) { Text(L("打开账户设置")) }
            }
        } else PullToRefreshBox(isRefreshing = loading && hasData, onRefresh = { refresh++ }, modifier = Modifier.weight(1f)) {
            LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                item {
                    Surface(onClick = { filter = true }, shape = RoundedCornerShape(8.dp), border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
                        Row(Modifier.fillMaxWidth().padding(10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.size(34.dp).background(MaterialTheme.colorScheme.secondary.copy(alpha = .1f), RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
                                CrestIcon(CrestIconKind.CALENDAR, Modifier.size(18.dp), MaterialTheme.colorScheme.secondary)
                            }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                val dateFormat = DateTimeFormatter.ofPattern(if (AppLocalization.locale.language == "zh") "M月d日" else "MMM d", AppLocalization.locale)
                                Text(L("%@ 至 %@", range.from.format(dateFormat), range.to.format(dateFormat)), fontSize = 14.sp, lineHeight = 19.sp)
                                Text(L("%@ · 按日统计", storeSummary), fontSize = 12.sp, lineHeight = 16.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Box(Modifier.height(26.dp).background(MaterialTheme.colorScheme.secondary.copy(alpha = .1f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                                Text(L(preset?.title ?: "自定义"), fontSize = 12.sp, lineHeight = 16.sp, color = MaterialTheme.colorScheme.secondary)
                            }
                            CrestIcon(CrestIconKind.CHEVRON_RIGHT, Modifier.size(12.dp))
                        }
                    }
                }
                if (loading && !hasData) item { Box(Modifier.fillMaxWidth().height(280.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                else if (error != null && !hasData) item {
                    AnalyticsSection(L("暂时无法加载")) {
                        Text(error!!, color = MaterialTheme.colorScheme.error)
                        TextButton(onClick = { refresh++ }) { Text(L("重新加载")) }
                    }
                } else {
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.width(3.dp).height(36.dp).background(MaterialTheme.colorScheme.secondary, RoundedCornerShape(2.dp)))
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(L(module.heading), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                                Text(when (module) {
                                    AnalyticsModule.PRODUCTS -> L("按商品销售额排名，共 %lld 项", data.products?.total ?: 0)
                                    AnalyticsModule.ALERTS -> L(module.subtitle) + " ${range.to}"
                                    else -> L(module.subtitle)
                                }, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    item { AnalyticsContent(module, data, range) { detail = it } }
                    if (error != null) item { Text(error!!, color = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }
    if (filter) AnalyticsFilter(range, preset, stores, options, storeError, { filter = false }) { selectedRange, selectedPreset, selectedStores ->
        range = selectedRange; preset = selectedPreset; stores = selectedStores; filter = false
    }
    detail?.let { value -> AnalyticsSheet(value.title, { detail = null }) {
        Column {
            Text(value.subtitle, Modifier.padding(start = 12.dp, end = 12.dp, bottom = 10.dp), fontSize = 13.sp, lineHeight = 18.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val rowBackground = if (MaterialTheme.colorScheme.background.luminance() < .5f) Color(0xFF2C2C2E) else Color.White
            Column(Modifier.fillMaxWidth().background(rowBackground, RoundedCornerShape(20.dp)).padding(horizontal = 12.dp)) {
                value.rows.forEachIndexed { index, (label, text) ->
                    if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = .6f), thickness = .5.dp)
                    Row(Modifier.fillMaxWidth().padding(vertical = 13.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text(L(label), Modifier.weight(1f).alignByBaseline(), fontSize = 16.sp, lineHeight = 22.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(text, Modifier.weight(1f).alignByBaseline(), fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End)
                    }
                }
            }
        }
    } }
}

@Composable
internal fun AnalyticsSection(title: String, subtitle: String? = null, action: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(8.dp), border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (title.isNotEmpty()) Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.width(3.dp).height(if (subtitle == null) 18.dp else 34.dp)
                    .background(MaterialTheme.colorScheme.secondary.copy(alpha = .75f), RoundedCornerShape(2.dp)))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    subtitle?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                action?.invoke()
            }
            content()
        }
    }
}

@Composable
internal fun AnalyticsLink(title: String, subtitle: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        CrestIcon(CrestIconKind.CHEVRON_RIGHT, Modifier.size(12.dp), MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun AnalyticsIcon(icon: CrestIconKind, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, tint: Color = Color.Unspecified) {
    IconButton(onClick, modifier.size(44.dp).padding(3.dp)
        .background(MaterialTheme.colorScheme.surface.copy(alpha = .68f), CircleShape)
        .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = .38f), CircleShape)
        .semantics { contentDescription = label }, enabled = enabled) { CrestIcon(icon, Modifier.size(18.dp), if (enabled) tint else Color.Unspecified) }
}

@Composable
internal fun AnalyticsSheet(title: String, onDismiss: () -> Unit, grouped: Boolean = false, action: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val formBackground = if (!grouped) MaterialTheme.colorScheme.background else if (MaterialTheme.colorScheme.background.luminance() < .5f) Color(0xFF1C1C1E) else Color(0xFFF4F3F9)
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        CrestDialogSystemBars(formBackground)
        Box(Modifier.fillMaxSize().statusBarsPadding(), contentAlignment = Alignment.BottomCenter) {
            Surface(Modifier.fillMaxWidth().fillMaxHeight(.97f), shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp), color = formBackground) {
                Column(Modifier.navigationBarsPadding()) {
                    Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        AnalyticsIcon(CrestIconKind.CLOSE, L("关闭"), onDismiss)
                        Text(title, Modifier.weight(1f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                        if (action != null) action() else Spacer(Modifier.size(44.dp))
                    }
                    LazyColumn(contentPadding = PaddingValues(16.dp)) { item { Column(verticalArrangement = Arrangement.spacedBy(18.dp), content = content) } }
                }
            }
        }
    }
}

@Composable
private fun AnalyticsFilter(initial: AnalyticsRange, preset: AnalyticsPeriod?, selected: Set<String>, options: List<Pair<String, String>>, error: String?, onDismiss: () -> Unit, onApply: (AnalyticsRange, AnalyticsPeriod?, Set<String>) -> Unit) {
    var range by remember { mutableStateOf(initial) }
    var draftPreset by remember { mutableStateOf(preset) }
    var stores by remember { mutableStateOf(selected) }
    val context = LocalContext.current
    val dark = MaterialTheme.colorScheme.background.luminance() < .5f
    val configuration = LocalConfiguration.current
    fun pickDate(start: Boolean) {
        val date = if (start) range.from else range.to
        val themed = ContextThemeWrapper(context, if (dark) R.style.Theme_Crest_DatePicker_Dark else R.style.Theme_Crest_DatePicker_Light).apply {
            applyOverrideConfiguration(Configuration(configuration).apply { setLocale(AppLocalization.locale) })
        }
        DatePickerDialog(themed, { _, year, month, day ->
            val result = LocalDate.of(year, month + 1, day)
            range = if (start) range.copy(from = result) else range.copy(to = result)
            draftPreset = null
        }, date.year, date.monthValue - 1, date.dayOfMonth).apply {
            datePicker.maxDate = LocalDate.now(ZoneId.of("Asia/Shanghai")).minusDays(1).atTime(23, 59).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        }.show()
    }
    AnalyticsSheet(L("筛选"), onDismiss, grouped = true, action = {
        AnalyticsIcon(CrestIconKind.CHECK, L("应用筛选"), { onApply(range, draftPreset, stores) }, enabled = range.from <= range.to, tint = MaterialTheme.colorScheme.secondary)
    }) {
        AnalyticsFilterGroup(L("快捷日期")) { AnalyticsPeriod.entries.forEachIndexed { index, item ->
            if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outline, thickness = .5.dp)
            FilterRow(L(item.title), item == draftPreset) { draftPreset = item; range = item.range() }
        } }
        AnalyticsFilterGroup(L("自定义日期")) {
            listOf(true, false).forEach { start ->
                if (!start) HorizontalDivider(color = MaterialTheme.colorScheme.outline, thickness = .5.dp)
                Row(Modifier.fillMaxWidth().clickable { pickDate(start) }.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L(if (start) "开始日期" else "结束日期"), Modifier.weight(1f), fontSize = 16.sp, lineHeight = 22.sp)
                    Text((if (start) range.from else range.to).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(AppLocalization.locale)),
                        Modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha = .07f), RoundedCornerShape(20.dp)).padding(horizontal = 12.dp, vertical = 5.dp), fontSize = 14.sp, lineHeight = 20.sp)
                }
            }
            if (range.from > range.to) Text(L("结束日期不能早于开始日期"), color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
        }
        AnalyticsFilterGroup(L("门店")) {
            FilterRow(L("全部门店"), stores.isEmpty()) { stores = emptySet() }
            options.forEach { (key, label) ->
                HorizontalDivider(color = MaterialTheme.colorScheme.outline, thickness = .5.dp)
                FilterRow(label, key in stores) { stores = if (key in stores) stores - key else stores + key }
            }
            if (options.isEmpty()) Text(error ?: L("暂未读取到可选门店"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun AnalyticsFilterGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, Modifier.padding(horizontal = 6.dp), fontSize = 13.sp, lineHeight = 18.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp), content = content)
        }
    }
}

@Composable
private fun FilterRow(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().semantics { this.selected = selected }.clickable(onClick = onClick).padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), fontSize = 16.sp, lineHeight = 22.sp)
        if (selected) CrestIcon(CrestIconKind.CHECK, Modifier.size(18.dp), MaterialTheme.colorScheme.secondary)
    }
}
