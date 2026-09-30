package com.blackwave.crest.feature.chat

import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

internal object ChatFeatureFlags {
    // 与 iOS 一致：联调前保留实现，Debug / Release 默认均不启用。
    const val lightweightTypewriter = false
}

/** 只控制展示进度；消息原文始终保存在 ChatController.messages 中。 */
internal class ChatTextPlayback(val messageId: String) {
    private val graphemePattern = Regex("\\X")
    var visibleText: String = ""
        private set

    private var receivedText = ""
    private var characters = emptyList<String>()
    private var visibleCount = 0
    private var bypassAnimation = false
    private var lastTick = 0.0
    private var finishDeadline: Double? = null

    val hasPendingText: Boolean get() = visibleCount < characters.size

    fun receive(text: String, animated: Boolean) {
        val isAppend = text.startsWith(receivedText)
        receivedText = text
        if (!animated || bypassAnimation || !isAppend || text.length > 20_000 ||
            "```" in text || "~~~" in text || '|' in text
        ) {
            revealAll()
            return
        }
        // \X matches a complete Unicode grapheme, including joined emoji and combining marks.
        characters = graphemePattern.findAll(text).map { it.value }.toList()
        visibleCount = min(visibleCount, characters.size)
        visibleText = characters.take(visibleCount).joinToString("")
    }

    fun resume(at: Double) {
        lastTick = at
    }

    fun advance(at: Double) {
        if (!hasPendingText) return
        if (finishDeadline?.let { at >= it } == true) {
            revealAll()
            return
        }
        val elapsed = max(0.0, at - lastTick)
        if (elapsed < 0.016) return
        lastTick = at
        val remaining = characters.size - visibleCount
        val catchUpDuration = finishDeadline?.let { max(0.032, it - at) } ?: 5.0
        val speed = max(80.0, remaining / catchUpDuration)
        val step = min(remaining, max(1, ceil(speed * min(elapsed, 0.1)).toInt()))
        visibleText += characters.subList(visibleCount, visibleCount + step).joinToString("")
        visibleCount += step
    }

    fun finish(at: Double) {
        finishDeadline = at + 10.0
    }

    /** 失败、停止或减少动态效果后，本条回复不再重启动画。 */
    fun revealAll() {
        visibleText = receivedText
        characters = emptyList()
        visibleCount = 0
        bypassAnimation = true
        finishDeadline = null
    }
}
