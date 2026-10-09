package com.blackwave.crest.feature.chat

import com.blackwave.crest.core.model.ChatAgentResponse
import com.blackwave.crest.core.model.ChatHistoryMessage
import com.blackwave.crest.core.model.ChatResponseAction
import com.blackwave.crest.core.model.ChatResponseActionParameters
import com.blackwave.crest.core.model.ChatResponseColumn
import com.blackwave.crest.core.model.ChatResponseMetric
import com.blackwave.crest.core.model.ChatResponsePart
import com.blackwave.crest.core.model.supportedActions
import com.blackwave.crest.core.model.supportedParts
import com.blackwave.crest.core.model.toChatMessage
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.Before
import org.junit.After
import com.blackwave.crest.ui.localization.AppLocalization
import java.util.Locale

class ChatReplyRenderingTest {
    private lateinit var previousLocale: Locale
    @Before fun useChineseUi() {
        previousLocale = AppLocalization.systemLocale
        AppLocalization.systemLocale = Locale.SIMPLIFIED_CHINESE
    }
    @After fun restoreLocale() { AppLocalization.systemLocale = previousLocale }

    @Test fun structuredStatusFollowsEnglishUiWithoutTranslatingUserContent() {
        AppLocalization.systemLocale = Locale.ENGLISH
        assertEquals("Comparable", formatTableValue(JsonPrimitive("comparable"), ChatResponseColumn("comparison_status", "状态")))
        assertEquals("自定义门店", formatTableValue(JsonPrimitive("自定义门店"), ChatResponseColumn("name", "名称")))
    }

    @Test fun markdownMatchesIosBlockOrderAndStreamingTail() {
        val blocks = MarkdownBlockParser.parse("# 标题\n\n**摘要**\n- 第一项\n- 第二项\n> 提示\n\n```sql\nselect 1\n```\n| 名称 | 数值 |\n| --- | --- |\n| A | 1 |")
        assertEquals(6, blocks.size)
        assertEquals(MarkdownBlock.Heading(1, "标题"), blocks[0])
        assertEquals(MarkdownBlock.UnorderedList(listOf("第一项", "第二项")), blocks[2])
        assertEquals(MarkdownBlock.Code("sql", "select 1"), blocks[4])
        assertEquals(MarkdownBlock.Table(listOf("名称", "数值"), listOf(listOf("A", "1"))), blocks[5])
        assertEquals(MarkdownBlock.Code("kotlin", "val x ="), MarkdownBlockParser.parse("```kotlin\nval x =").single())
    }

    @Test fun inlineMarkdownFormatsEmphasisAndSafeLinks() {
        val rendered = parseInlineMarkdown("A **bold** [site](https://example.com) [unsafe](javascript:alert)", Color.Blue)
        assertEquals("A bold site [unsafe](javascript:alert)", rendered.text)
        assertTrue(rendered.spanStyles.isNotEmpty())
        assertEquals(1, rendered.getLinkAnnotations(0, rendered.length).size)
    }

    @Test fun aguiFiltersPartsAndActionsLikeIos() {
        val response = ChatAgentResponse(
            version = 1,
            sourceTurnId = "turn-1",
            parts = listOf(
                ChatResponsePart(kind = "summary", message = "有效"),
                ChatResponsePart(kind = "notice", message = "无级别"),
                ChatResponsePart(kind = "table", columns = emptyList()),
                ChatResponsePart(kind = "clarification", message = "请选择"),
            ),
            actions = listOf(
                ChatResponseAction("a", "clarify", "确定", "turn-1", ChatResponseActionParameters("choice", "选择第一项")),
                ChatResponseAction("b", "clarify", "无候选", "turn-1", ChatResponseActionParameters(null, "选择")),
                ChatResponseAction("c", "prompt", "错误轮次", "turn-2", ChatResponseActionParameters(message = "继续")),
            ),
        )
        assertEquals(listOf("summary", "clarification"), response.supportedParts.map { it.kind })
        assertEquals(listOf("a"), response.supportedActions.map { it.actionId })
    }

    @Test fun tableKeepsAllRelevantColumnsAndFormatsValues() {
        val columns = listOf(
            ChatResponseColumn("id", "internal_id"),
            ChatResponseColumn("name", "名称"),
            ChatResponseColumn("ratio", "占比", "decimal", "ratio"),
            ChatResponseColumn("empty", "空列"),
            ChatResponseColumn("status", "状态"),
        )
        val part = ChatResponsePart(kind = "table", columns = columns, previewRows = listOf(mapOf(
            "id" to JsonPrimitive("42"), "name" to JsonPrimitive("门店"),
            "ratio" to JsonPrimitive("0.125"), "status" to JsonPrimitive("comparable"),
        )))
        assertEquals(listOf("name", "ratio", "status", "id"), visibleColumns(part).map { it.key })
        assertEquals("12.5%", formatTableValue(JsonPrimitive("0.125"), columns[2]))
        assertEquals("可比", formatTableValue(JsonPrimitive("comparable"), ChatResponseColumn("comparison_status", "状态")))
        assertEquals("¥1,234.5", formatMetric(ChatResponseMetric("sales", value = "1234.5", unit = "cny")))
    }

    @Test fun malformedHistoricalAguiDoesNotHideMessage() {
        val json = Json { ignoreUnknownKeys = true }
        val message = json.decodeFromString<ChatHistoryMessage>("""{
            "id":"m", "role":"assistant", "content":"正文", "created_at":"2026-01-01",
            "metadata":{"agent_response":{"version":"broken"},"delivery_status":"completed"}
        }""")
        assertEquals("正文", message.toChatMessage()?.content)
        assertTrue(message.toChatMessage()?.responseParts.isNullOrEmpty())
    }
}
