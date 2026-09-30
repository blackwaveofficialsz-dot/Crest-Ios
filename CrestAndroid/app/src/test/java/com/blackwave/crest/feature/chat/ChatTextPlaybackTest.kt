package com.blackwave.crest.feature.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatTextPlaybackTest {
    @Test fun defaultIsOffAndAppendsWithoutResettingProgress() {
        assertFalse(ChatFeatureFlags.lightweightTypewriter)
        val playback = ChatTextPlayback("reply")
        playback.receive("你好，世界", animated = true)
        assertEquals("", playback.visibleText)
        playback.resume(10.0)
        playback.advance(10.032)
        val prefix = playback.visibleText
        assertTrue(prefix.isNotEmpty())
        playback.receive("你好，世界！", animated = true)
        assertEquals(prefix, playback.visibleText)
        playback.finish(10.032)
        playback.advance(20.033)
        assertEquals("你好，世界！", playback.visibleText)
        assertFalse(playback.hasPendingText)
    }

    @Test fun complexMarkdownAndReducedMotionRevealImmediately() {
        for (content in listOf("```sql\nselect 1\n```", "| 名称 | 数值 |", "长".repeat(20_001))) {
            val playback = ChatTextPlayback("reply")
            playback.receive(content, animated = true)
            assertEquals(content, playback.visibleText)
            assertFalse(playback.hasPendingText)
        }
        val playback = ChatTextPlayback("reply")
        playback.receive("第一段", animated = false)
        playback.receive("第一段第二段", animated = true)
        assertEquals("第一段第二段", playback.visibleText)
    }

    @Test fun revealsWholeEmojiClustersAndDoesNotRestartAfterStop() {
        val content = "👨‍👩‍👧‍👦🇨🇳👍🏽e\u0301中文"
        val playback = ChatTextPlayback("reply")
        playback.receive(content, animated = true)
        playback.resume(0.0)
        playback.advance(0.032)
        assertEquals("👨‍👩‍👧‍👦🇨🇳👍🏽", playback.visibleText)
        playback.revealAll()
        playback.receive(content + "后续", animated = true)
        assertEquals(content + "后续", playback.visibleText)
    }

    @Test fun replacementBypassesAnimation() {
        val playback = ChatTextPlayback("reply")
        playback.receive("服务器原文", animated = true)
        playback.receive("服务器修正全文", animated = true)
        assertEquals("服务器修正全文", playback.visibleText)
        assertFalse(playback.hasPendingText)
    }
}
