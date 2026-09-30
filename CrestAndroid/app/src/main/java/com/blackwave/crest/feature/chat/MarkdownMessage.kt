package com.blackwave.crest.feature.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.blackwave.crest.ui.components.CrestIcon
import com.blackwave.crest.ui.components.CrestIconKind
import kotlinx.coroutines.delay

@Composable
internal fun MarkdownMessage(content: String, isStreaming: Boolean) {
    val blocks = remember(content) { MarkdownBlockParser.parse(content) }
    val body: @Composable () -> Unit = {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        blocks.forEach { block ->
            when (block) {
                is MarkdownBlock.Paragraph -> InlineMarkdown(block.text)
                is MarkdownBlock.Heading -> InlineMarkdown(
                    block.text,
                    modifier = Modifier.padding(top = when (block.level) { 1 -> 10.dp; 2 -> 8.dp; else -> 6.dp }),
                    fontSize = when (block.level) { 1 -> 20.sp; 2 -> 18.sp; else -> 17.sp },
                    fontWeight = FontWeight.SemiBold,
                )
                is MarkdownBlock.UnorderedList -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    block.items.forEach { item -> MarkdownListRow("•", item) }
                }
                is MarkdownBlock.OrderedList -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    block.items.forEachIndexed { index, item -> MarkdownListRow("${block.start + index}.", item) }
                }
                is MarkdownBlock.Quote -> Row(Modifier.height(IntrinsicSize.Min).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                    Box(Modifier.width(3.dp).fillMaxHeight().background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .55f), RoundedCornerShape(2.dp)))
                    InlineMarkdown(block.text, modifier = Modifier.weight(1f), muted = true)
                }
                is MarkdownBlock.Code -> MarkdownCodeBlock(block.language, block.content)
                is MarkdownBlock.Table -> if (isStreaming) StreamingMarkdownTable(block) else MarkdownTable(block.headers, block.rows)
                MarkdownBlock.Divider -> HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            }
        }
        }
    }
    if (isStreaming) body() else SelectionContainer { body() }
}

@Composable
private fun MarkdownListRow(marker: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(marker, modifier = Modifier.width(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        InlineMarkdown(text, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun InlineMarkdown(
    text: String,
    modifier: Modifier = Modifier,
    fontSize: androidx.compose.ui.unit.TextUnit = 16.sp,
    fontWeight: FontWeight? = null,
    muted: Boolean = false,
) {
    val tint = MaterialTheme.colorScheme.secondary
    val annotated = remember(text, tint) { parseInlineMarkdown(text, tint) }
    Text(
        annotated,
        modifier = modifier,
        color = if (muted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onBackground,
        fontSize = fontSize,
        fontWeight = fontWeight,
        lineHeight = fontSize * 1.36f,
    )
}

/** Only the inline syntax accepted by iOS AttributedString is interpreted here. */
internal fun parseInlineMarkdown(source: String, linkColor: androidx.compose.ui.graphics.Color): AnnotatedString = buildAnnotatedString {
    fun appendRange(start: Int, end: Int) {
        var index = start
        while (index < end) {
            if (source[index] == '\\' && index + 1 < end) {
                append(source[index + 1]); index += 2; continue
            }
            if (source[index] == '[') {
                val close = source.indexOf("](", index + 1).takeIf { it in (index + 1) until end }
                val urlEnd = close?.let { source.indexOf(')', it + 2).takeIf { finish -> finish < end } }
                if (close != null && urlEnd != null) {
                    val url = source.substring(close + 2, urlEnd)
                    if (listOf("https://", "http://", "mailto:", "tel:").any { url.startsWith(it, ignoreCase = true) }) {
                        withLink(LinkAnnotation.Url(url, TextLinkStyles(style = SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)))) {
                            appendRange(index + 1, close)
                        }
                        index = urlEnd + 1; continue
                    }
                }
            }
            val marker = listOf("**", "__", "~~", "`", "*", "_").firstOrNull { source.startsWith(it, index) }
            if (marker != null) {
                val close = source.indexOf(marker, index + marker.length).takeIf { it >= 0 && it + marker.length <= end }
                if (close != null && close > index + marker.length) {
                    val style = when (marker) {
                        "**", "__" -> SpanStyle(fontWeight = FontWeight.Bold)
                        "~~" -> SpanStyle(textDecoration = TextDecoration.LineThrough)
                        "`" -> SpanStyle(fontFamily = FontFamily.Monospace, background = androidx.compose.ui.graphics.Color.Gray.copy(alpha = .16f))
                        else -> SpanStyle(fontStyle = FontStyle.Italic)
                    }
                    withStyle(style) {
                        if (marker == "`") append(source.substring(index + 1, close))
                        else appendRange(index + marker.length, close)
                    }
                    index = close + marker.length; continue
                }
            }
            append(source[index]); index++
        }
    }
    appendRange(0, source.length)
}

@Composable
private fun MarkdownCodeBlock(language: String?, code: String) {
    val context = LocalContext.current
    var copied by remember(code) { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(1400)
            copied = false
        }
    }
    Column(
        Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface, RoundedCornerShape(8.dp))
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp)),
    ) {
        Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(language?.ifEmpty { "代码" } ?: "代码", modifier = Modifier.weight(1f), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Box(
                Modifier.size(32.dp).semantics { contentDescription = if (copied) "已复制" else "复制代码" }.clickable {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                        .setPrimaryClip(ClipData.newPlainText("code", code))
                    copied = true
                },
                contentAlignment = Alignment.Center,
            ) {
                CrestIcon(
                    if (copied) CrestIconKind.CHECK else CrestIconKind.COPY,
                    Modifier.size(16.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
        Text(
            code.ifEmpty { " " },
            modifier = Modifier.horizontalScroll(rememberScrollState()).padding(12.dp),
            fontFamily = FontFamily.Monospace,
            fontSize = 14.sp,
            lineHeight = 17.sp,
            softWrap = false,
        )
    }
}

@Composable
private fun StreamingMarkdownTable(block: MarkdownBlock.Table) {
    val source = (listOf(block.headers) + block.rows).joinToString("\n") { "| ${it.joinToString(" | ")} |" }
    Box(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface, RoundedCornerShape(8.dp))
        .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp))) {
        Text(source, Modifier.horizontalScroll(rememberScrollState()).padding(12.dp), fontFamily = FontFamily.Monospace, fontSize = 14.sp, softWrap = false)
    }
}

@Composable
internal fun MarkdownTable(
    headers: List<String>,
    rows: List<List<String>>,
    title: String? = null,
    previewRowCount: Int = 10,
    totalRowCount: Int? = null,
    columnWidths: List<Int>? = null,
) {
    var expanded by remember(headers, rows) { mutableStateOf(false) }
    val count = maxOf(headers.size, rows.maxOfOrNull { it.size } ?: 0)
    val shown = if (expanded) rows else rows.take(previewRowCount)
    val reported = maxOf(totalRowCount ?: rows.size, rows.size)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!title.isNullOrEmpty()) Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Column(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).background(MaterialTheme.colorScheme.background, RoundedCornerShape(8.dp))) {
            (listOf(headers) + shown).forEachIndexed { rowIndex, row ->
                Row {
                    repeat(count) { column ->
                        Text(
                            row.getOrElse(column) { "" },
                            modifier = Modifier.width((columnWidths?.getOrNull(column) ?: if (column == 0) 168 else 144).dp)
                                .background(if (rowIndex == 0) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.background)
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            fontSize = 15.sp,
                            lineHeight = 19.sp,
                            fontWeight = if (rowIndex == 0) FontWeight.SemiBold else FontWeight.Normal,
                            maxLines = 3,
                        )
                    }
                }
                if (rowIndex < shown.size) HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            }
        }
        if (totalRowCount != null) Text("当前展示 ${shown.size} / $reported 行", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (rows.size > previewRowCount) TextButton(onClick = { expanded = !expanded }) {
            Text(if (expanded) "收起" else if (reported > rows.size) "展开已返回的 ${rows.size} 行" else "展开全部（${rows.size} 行）")
        }
    }
}
