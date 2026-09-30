package com.blackwave.crest.core.network

import com.blackwave.crest.core.model.ChatStreamEvent
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatEventParserTest {
    private val parser = ChatEventParser(
        json = Json { ignoreUnknownKeys = true; explicitNulls = false },
        threadId = "thread-1",
        runId = "run-1",
    )

    @Test
    fun parsesAssistantTextStream() {
        parser.parse(event("RUN_STARTED", sequence = 0))
        parser.parse(event(
            type = "TEXT_MESSAGE_START",
            sequence = 1,
            extra = "\"messageId\":\"message-1\",\"role\":\"assistant\"",
        ))

        val result = parser.parse(event(
            type = "TEXT_MESSAGE_CONTENT",
            sequence = 2,
            extra = "\"messageId\":\"message-1\",\"delta\":\"你好\"",
        ))

        assertEquals(listOf(ChatStreamEvent.Text("你好")), result.events)
        assertFalseTerminal(result)
    }

    @Test
    fun duplicateEventIsIgnored() {
        val raw = event("RUN_STARTED", sequence = 0)
        parser.parse(raw)

        val duplicate = parser.parse(raw)

        assertTrue(duplicate.events.isEmpty())
    }

    @Test(expected = ApiException::class)
    fun rejectsEventFromAnotherThread() {
        parser.parse(event("RUN_STARTED", sequence = 0, threadId = "thread-2"))
    }

    private fun assertFalseTerminal(result: ParsedChatEvent) {
        assertTrue(!result.isTerminal)
    }

    private fun event(
        type: String,
        sequence: Int,
        threadId: String = "thread-1",
        extra: String? = null,
    ): String = buildString {
        append("{\"type\":\"")
        append(type)
        append("\",\"eventId\":\"run-1:")
        append(sequence)
        append(":0\",\"sequence\":")
        append(sequence)
        append(",\"runId\":\"run-1\",\"threadId\":\"")
        append(threadId)
        append('"')
        if (extra != null) {
            append(',')
            append(extra)
        }
        append('}')
    }
}
