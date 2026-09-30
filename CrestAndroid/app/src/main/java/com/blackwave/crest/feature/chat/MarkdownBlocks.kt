package com.blackwave.crest.feature.chat

internal sealed interface MarkdownBlock {
    data class Paragraph(val text: String) : MarkdownBlock
    data class Heading(val level: Int, val text: String) : MarkdownBlock
    data class UnorderedList(val items: List<String>) : MarkdownBlock
    data class OrderedList(val start: Int, val items: List<String>) : MarkdownBlock
    data class Quote(val text: String) : MarkdownBlock
    data class Code(val language: String?, val content: String) : MarkdownBlock
    data class Table(val headers: List<String>, val rows: List<List<String>>) : MarkdownBlock
    data object Divider : MarkdownBlock
}

/** Mirrors the block grammar used by the iOS chat view, including incomplete stream tails. */
internal object MarkdownBlockParser {
    fun parse(source: String): List<MarkdownBlock> {
        val lines = source.replace("\r\n", "\n").split('\n')
        val blocks = mutableListOf<MarkdownBlock>()
        val paragraph = mutableListOf<String>()
        fun flush() {
            if (paragraph.isNotEmpty()) {
                blocks += MarkdownBlock.Paragraph(paragraph.joinToString("\n"))
                paragraph.clear()
            }
        }
        var index = 0
        while (index < lines.size) {
            val line = lines[index]
            val trimmed = line.trim(' ', '\t')
            when {
                trimmed.isEmpty() -> { flush(); index++ }
                trimmed.startsWith("```") -> {
                    flush()
                    val language = trimmed.drop(3).trim().ifEmpty { null }
                    val code = mutableListOf<String>()
                    index++
                    while (index < lines.size && !lines[index].trim().startsWith("```")) code += lines[index++]
                    if (index < lines.size) index++
                    blocks += MarkdownBlock.Code(language, code.joinToString("\n"))
                }
                index + 1 < lines.size && tableCells(line) != null &&
                    isTableSeparator(lines[index + 1], tableCells(line)!!.size) -> {
                    flush()
                    val headers = tableCells(line)!!
                    val rows = mutableListOf<List<String>>()
                    index += 2
                    while (index < lines.size) {
                        val row = tableCells(lines[index]) ?: break
                        rows += row
                        index++
                    }
                    blocks += MarkdownBlock.Table(headers, rows)
                }
                heading(trimmed) != null -> {
                    flush()
                    val (level, text) = heading(trimmed)!!
                    blocks += MarkdownBlock.Heading(level, text)
                    index++
                }
                isDivider(trimmed) -> { flush(); blocks += MarkdownBlock.Divider; index++ }
                unorderedItem(trimmed) != null -> {
                    flush()
                    val items = mutableListOf<String>()
                    while (index < lines.size) {
                        val item = unorderedItem(lines[index].trim()) ?: break
                        items += item
                        index++
                    }
                    blocks += MarkdownBlock.UnorderedList(items)
                }
                orderedItem(trimmed) != null -> {
                    flush()
                    val first = orderedItem(trimmed)!!
                    val items = mutableListOf(first.second)
                    index++
                    while (index < lines.size) {
                        val item = orderedItem(lines[index].trim()) ?: break
                        items += item.second
                        index++
                    }
                    blocks += MarkdownBlock.OrderedList(first.first, items)
                }
                quoteText(trimmed) != null -> {
                    flush()
                    val quote = mutableListOf<String>()
                    while (index < lines.size) {
                        val text = quoteText(lines[index].trim()) ?: break
                        quote += text
                        index++
                    }
                    blocks += MarkdownBlock.Quote(quote.joinToString("\n"))
                }
                else -> { paragraph += trimmed; index++ }
            }
        }
        flush()
        return blocks
    }

    private fun heading(line: String): Pair<Int, String>? {
        val count = line.takeWhile { it == '#' }.length
        if (count !in 1..6 || line.getOrNull(count)?.isWhitespace() != true) return null
        return count to line.drop(count).trim()
    }

    private fun unorderedItem(line: String): String? =
        if (line.startsWith("- ") || line.startsWith("* ") || line.startsWith("+ ")) line.drop(2).trim() else null

    private fun orderedItem(line: String): Pair<Int, String>? {
        val dot = line.indexOf('.')
        if (dot < 1 || line.getOrNull(dot + 1)?.isWhitespace() != true) return null
        return (line.substring(0, dot).toIntOrNull() ?: return null) to line.drop(dot + 1).trim()
    }

    private fun quoteText(line: String): String? = if (line.startsWith('>')) line.drop(1).trim() else null

    private fun isDivider(line: String): Boolean {
        val compact = line.filterNot { it.isWhitespace() }
        return compact.length >= 3 && compact[0] in "-_*" && compact.all { it == compact[0] }
    }

    private fun tableCells(line: String): List<String>? {
        if ('|' !in line) return null
        val value = line.trim().removePrefix("|").removeSuffix("|")
        return value.split('|').map(String::trim).takeIf { it.size >= 2 }
    }

    private fun isTableSeparator(line: String, columns: Int): Boolean =
        tableCells(line)?.takeIf { it.size == columns }?.all { cell ->
            val markers = cell.trim(' ', ':')
            markers.length >= 3 && markers.all { it == '-' }
        } == true
}
