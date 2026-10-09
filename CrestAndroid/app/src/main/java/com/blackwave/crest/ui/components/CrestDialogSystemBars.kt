package com.blackwave.crest.ui.components

import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat

/** Dialogs own a separate window; the Activity theme cannot color their system bars. */
@Composable
internal fun CrestDialogSystemBars(background: Color) {
    val view = LocalView.current
    SideEffect {
        val window = (view.parent as? DialogWindowProvider)?.window ?: return@SideEffect
        val light = background.luminance() >= .5f
        @Suppress("DEPRECATION")
        window.navigationBarColor = background.toArgb()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) window.isNavigationBarContrastEnforced = false
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = light
            isAppearanceLightNavigationBars = light
        }
    }
}
