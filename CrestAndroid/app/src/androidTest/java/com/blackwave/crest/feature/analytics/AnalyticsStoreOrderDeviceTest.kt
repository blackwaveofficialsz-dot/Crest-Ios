package com.blackwave.crest.feature.analytics

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.blackwave.crest.core.model.AnalyticsStoreNode
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

/** Exercise Android's ICU, including Han characters missing from desktop JDK collation tables. */
@RunWith(AndroidJUnit4::class)
class AnalyticsStoreOrderDeviceTest {
    @Test fun chineseNamesUsePinyinOrderAndKeepDistinctStoreKeys() {
        val nodes = stores("三桥店", "凤八店", "北大街", "翡丽店")
        val options = analyticsStoreOptions(nodes + nodes.first(), Locale.SIMPLIFIED_CHINESE)
        assertEquals(listOf("北大街", "翡丽店", "凤八店", "三桥店"), options.map { it.second })
        assertEquals(listOf("s2", "s3", "s1", "s0"), options.map { it.first })
    }

    @Test fun numberedNamesUseNaturalOrder() {
        val options = analyticsStoreOptions(stores("Store 12", "Store 2", "Store 1"), Locale.ENGLISH)
        assertEquals(listOf("Store 1", "Store 2", "Store 12"), options.map { it.second })
    }

    private fun stores(vararg names: String) = names.mapIndexed { index, name ->
        AnalyticsStoreNode("shop", "shop", name, "s$index")
    }
}
