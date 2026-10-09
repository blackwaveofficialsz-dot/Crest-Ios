package com.blackwave.crest.ui.localization

import org.junit.Assert.*
import org.junit.Test
import java.util.Locale

class AppLocalizationTest {
    @Test fun chineseAndEnglishFormatsMatchIosPlaceholders() {
        val previous = AppLocalization.systemLocale
        try {
            AppLocalization.systemLocale = Locale.ENGLISH
            assertEquals("3 stores", L("%lld 家门店", 3))
            assertEquals("Actual 12 · Planned 10", L("实际 %@ · 计划 %@", "12", "10"))
            assertEquals("Showing 2 / 30 rows", L("当前展示 %lld / %lld 行", 2, 30))
            AppLocalization.systemLocale = Locale.SIMPLIFIED_CHINESE
            assertEquals("3 家门店", L("%lld 家门店", 3))
            assertEquals("实际 12 · 计划 10", L("实际 %@ · 计划 %@", "12", "10"))
        } finally { AppLocalization.systemLocale = previous }
    }

    @Test fun unknownStringsArePreserved() {
        assertEquals("用户自己命名的门店", L("用户自己命名的门店"))
        assertEquals("100%", L("100%"))
    }
}
