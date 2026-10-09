package com.blackwave.crest.ui.localization

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import java.util.Locale

enum class LanguageMode(val title: String) {
    SYSTEM("跟随系统"), CHINESE("简体中文"), ENGLISH("English"),
}

/** Mirrors iOS's explicit UI-key translation. Backend/user text is never translated. */
object AppLocalization {
    var mode by mutableStateOf(LanguageMode.SYSTEM)
        private set
    var systemLocale by mutableStateOf(Locale.ROOT)
    val locale: Locale get() = when (mode) {
        LanguageMode.SYSTEM -> systemLocale
        LanguageMode.CHINESE -> Locale.SIMPLIFIED_CHINESE
        LanguageMode.ENGLISH -> Locale.ENGLISH
    }

    fun initialize(context: Context) {
        systemLocale = context.resources.configuration.locales[0]
        val saved = context.getSharedPreferences("crest_preferences", Context.MODE_PRIVATE).getString("language", LanguageMode.SYSTEM.name)
        mode = runCatching { LanguageMode.valueOf(saved!!) }.getOrDefault(LanguageMode.SYSTEM)
    }

    fun update(context: Context, value: LanguageMode) {
        mode = value
        context.getSharedPreferences("crest_preferences", Context.MODE_PRIVATE).edit { putString("language", value.name) }
    }
}

fun L(key: String, vararg arguments: Any): String {
    val text = if (AppLocalization.locale.language == "zh") key else englishUiStrings[key] ?: key
    return if (arguments.isEmpty()) text else String.format(AppLocalization.locale, text.replace("%@", "%s").replace("%lld", "%d"), *arguments)
}
