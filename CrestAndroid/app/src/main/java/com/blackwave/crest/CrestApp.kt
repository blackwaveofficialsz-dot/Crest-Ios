package com.blackwave.crest

import com.blackwave.crest.ui.localization.L

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalConfiguration
import com.blackwave.crest.ui.localization.AppLocalization
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.blackwave.crest.core.session.SessionState
import com.blackwave.crest.core.session.SessionStore
import com.blackwave.crest.feature.auth.AuthScreen
import com.blackwave.crest.feature.home.HomeScreen
import com.blackwave.crest.ui.theme.CrestTheme
import com.blackwave.crest.ui.theme.ThemeController
import kotlinx.coroutines.launch
import java.util.Locale

@Composable
fun CrestApp() {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val appLocale = AppLocalization.locale
    SideEffect {
        AppLocalization.systemLocale = configuration.locales[0]
        // Native date picker headers use the process locale, not only their Context locale.
        if (Locale.getDefault() != appLocale) Locale.setDefault(appLocale)
    }
    val session = remember { SessionStore(context) }
    val theme = remember { ThemeController(context) }
    val scope = rememberCoroutineScope()

    CrestTheme(theme.mode) {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            when (val state = session.state) {
                SessionState.Restoring -> Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                    CenteredProgress(L("正在恢复登录状态"))
                }
                SessionState.SignedOut -> AuthScreen(session)
                is SessionState.SignedIn -> HomeScreen(session, state.user, theme)
                is SessionState.RestoreError -> Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                    RestoreError(
                        message = state.message,
                        onRetry = { scope.launch { session.restore() } },
                    )
                }
            }
        }
    }

    LaunchedEffect(session) { session.restore() }
}

@Composable
private fun CenteredProgress(label: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            CircularProgressIndicator()
            Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun RestoreError(message: String, onRetry: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(L("无法恢复登录"), style = MaterialTheme.typography.titleLarge)
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onRetry) { Text(L("重试")) }
        }
    }
}
