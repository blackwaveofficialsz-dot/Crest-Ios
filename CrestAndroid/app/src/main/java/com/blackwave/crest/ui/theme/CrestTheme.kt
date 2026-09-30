package com.blackwave.crest.ui.theme

import android.app.Activity
import android.content.Context
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material3.Typography
import androidx.core.content.edit
import androidx.core.view.WindowCompat
import com.blackwave.crest.R

val CrestRoundedFontFamily = FontFamily(
    Font(R.font.rubik_regular, weight = FontWeight.Normal),
    Font(R.font.rubik_bold, weight = FontWeight.Bold),
)

enum class ThemeMode(val title: String) {
    SYSTEM("跟随系统"),
    LIGHT("浅色"),
    DARK("深色"),
}

class ThemeController(context: Context) {
    private val preferences = context.getSharedPreferences("crest_preferences", Context.MODE_PRIVATE)
    var mode by mutableStateOf(
        runCatching { ThemeMode.valueOf(preferences.getString("theme", ThemeMode.DARK.name)!!) }
            .getOrDefault(ThemeMode.DARK),
    )
        private set

    fun updateMode(value: ThemeMode) {
        mode = value
        preferences.edit { putString("theme", value.name) }
    }
}

private val LightColors = lightColorScheme(
    primary = Color(0xFF0D0D0D),
    onPrimary = Color.White,
    secondary = Color(0xFF0285FF),
    onSecondary = Color.White,
    background = Color.White,
    onBackground = Color(0xFF0D0D0D),
    surface = Color(0xFFFAFAFA),
    onSurface = Color(0xFF0D0D0D),
    surfaceVariant = Color(0xFFF3F3F3),
    onSurfaceVariant = Color(0xFF5D5D5D),
    outline = Color(0xFFE5E5E5),
    error = Color(0xFFBA1A1A),
)

private val DarkColors = darkColorScheme(
    primary = Color.White,
    onPrimary = Color(0xFF0D0D0D),
    secondary = Color(0xFF0A84FF),
    onSecondary = Color.White,
    background = Color(0xFF212121),
    onBackground = Color(0xFFECECEC),
    surface = Color(0xFF2F2F2F),
    onSurface = Color(0xFFECECEC),
    surfaceVariant = Color(0xFF303030),
    onSurfaceVariant = Color(0xFFB4B4B4),
    outline = Color(0xFF424242),
    error = Color(0xFFFFB4AB),
)

private val CrestTypography = Typography().run {
    copy(
        displayLarge = displayLarge.copy(fontFamily = FontFamily.SansSerif),
        headlineLarge = headlineLarge.copy(fontFamily = FontFamily.SansSerif),
        titleLarge = titleLarge.copy(fontFamily = FontFamily.SansSerif),
        bodyLarge = bodyLarge.copy(fontFamily = FontFamily.SansSerif),
        bodyMedium = bodyMedium.copy(fontFamily = FontFamily.SansSerif),
        labelLarge = labelLarge.copy(fontFamily = FontFamily.SansSerif),
    )
}

@Composable
fun CrestTheme(mode: ThemeMode, content: @Composable () -> Unit) {
    val dark = when (mode) {
        ThemeMode.DARK -> true
        ThemeMode.LIGHT -> false
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
    }
    val view = LocalView.current
    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        window.statusBarColor = AndroidColor.TRANSPARENT
        window.navigationBarColor = if (dark) 0xFF212121.toInt() else AndroidColor.WHITE
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        }
    }
    MaterialTheme(
        colorScheme = if (dark) DarkColors else LightColors,
        typography = CrestTypography,
        content = content,
    )
}
