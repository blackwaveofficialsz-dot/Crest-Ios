package com.blackwave.crest.feature.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.blackwave.crest.core.model.ChatResponseColumn
import com.blackwave.crest.core.model.ChatResponseMetric
import com.blackwave.crest.core.model.ChatResponsePart
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.text.NumberFormat

@Composable
internal fun StructuredPart(part: ChatResponsePart) {
    when (part.kind) {
        "summary" -> StructuredCard {
            if (!part.title.isNullOrEmpty()) Text(part.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            if (!part.message.isNullOrEmpty()) Text(part.message, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            part.metrics.orEmpty().chunked(2).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { metric ->
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(metric.label ?: metric.key, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(formatMetric(metric), fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                        }
                    }
                    if (row.size == 1) Column(Modifier.weight(1f)) {}
                }
            }
        }
        "insights" -> StructuredCard {
            if (!part.title.isNullOrEmpty()) Text(part.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            part.items.orEmpty().forEach { insight ->
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    Text(
                        when (insight.statementType) { "recommendation" -> "✦"; "hypothesis" -> "?"; else -> "✓" },
                        modifier = Modifier.width(18.dp),
                        color = if (insight.statementType == "recommendation") Color(0xFFFF9800) else MaterialTheme.colorScheme.secondary,
                        fontSize = 15.sp,
                    )
                    Text(insight.text, fontSize = 14.sp, lineHeight = 19.sp)
                }
            }
        }
        "notice" -> {
            val accent = when (part.severity) {
                "error" -> MaterialTheme.colorScheme.error
                "warning" -> Color(0xFFFF9800)
                else -> MaterialTheme.colorScheme.secondary
            }
            Row(
                Modifier.fillMaxWidth().background(accent.copy(alpha = .08f), RoundedCornerShape(14.dp))
                    .border(1.dp, accent.copy(alpha = .2f), RoundedCornerShape(14.dp)).padding(14.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(if (part.severity == "error") "!" else "ⓘ", color = accent, fontSize = 16.sp)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (!part.title.isNullOrEmpty()) Text(part.title, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    Text(part.message.orEmpty(), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        "clarification" -> StructuredCard {
            if (!part.title.isNullOrEmpty()) Text(part.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Text(part.message.orEmpty(), fontSize = 16.sp, lineHeight = 22.sp)
        }
        "table" -> {
            val columns = visibleColumns(part)
            val rows = part.previewRows.orEmpty().map { row ->
                columns.map { column -> formatTableValue(row[column.key], column) }
            }
            MarkdownTable(
                headers = columns.map { it.label },
                rows = rows,
                title = part.title,
                previewRowCount = 3,
                totalRowCount = part.rowCount,
                columnWidths = columns.map { column ->
                    if (column.dataType == "decimal" || column.dataType == "integer") 112
                    else {
                        val longest = maxOf(column.label.length, part.previewRows.orEmpty().maxOfOrNull { displayText(it[column.key]).length } ?: 0)
                        when { longest > 18 -> 220; longest > 10 || isTechnical(column) -> 180; else -> 144 }
                    }
                },
            )
        }
    }
}

@Composable
private fun StructuredCard(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp))
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(14.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) { content() }
}

internal fun visibleColumns(part: ChatResponsePart): List<ChatResponseColumn> = part.columns.orEmpty()
    .withIndex()
    .filter { (_, column) -> part.previewRows.orEmpty().any { row ->
        displayText(row[column.key]).trim().let { it.isNotEmpty() && it != "—" }
    } }
    .sortedWith(compareBy<IndexedValue<ChatResponseColumn>> { isTechnical(it.value) }.thenBy { it.index })
    .map { it.value }

private fun isTechnical(column: ChatResponseColumn): Boolean =
    '_' in column.label || column.label == column.key && column.label.all { it.code < 128 }

internal fun displayText(value: JsonElement?): String = when (value) {
    null, JsonNull -> "—"
    is JsonPrimitive -> if (value.isString) value.content else value.content
    is JsonArray -> value.joinToString(", ") { displayText(it) }
    is JsonObject -> value.keys.sorted().joinToString(", ") { "$it: ${displayText(value[it])}" }
}

internal fun formatTableValue(value: JsonElement?, column: ChatResponseColumn): String {
    val text = displayText(value)
    if (text == "—") return text
    if (column.key == "comparison_status") return when (text) {
        "comparable" -> "可比"
        "not_comparable" -> "不可比"
        else -> "未知"
    }
    if (column.dataType != "decimal" && column.dataType != "integer") return text
    val decimal = text.toBigDecimalOrNull() ?: return text
    val formatted = formatNumber(decimal)
    return when (column.unit?.lowercase()) {
        "cny" -> "¥$formatted"
        "ratio" -> "${formatNumber(decimal * BigDecimal(100))}%"
        "order" -> "${formatted}单"
        "store" -> "${formatted}家"
        "hour" -> "${formatted}小时"
        "period" -> "${formatted}期"
        "product" -> "${formatted}种"
        "item" -> "${formatted}件"
        "person" -> "${formatted}人"
        else -> formatted
    }
}

internal fun formatMetric(metric: ChatResponseMetric): String {
    val decimal = metric.value.toBigDecimalOrNull() ?: return metric.value
    val formatted = formatNumber(decimal)
    return when (metric.unit?.lowercase()) {
        "cny" -> "¥$formatted"
        "ratio" -> "${formatNumber(decimal * BigDecimal(100))}%"
        "order" -> "${formatted}单"
        "store" -> "${formatted}家"
        "hour" -> "${formatted}小时"
        "person" -> "${formatted}人"
        null -> formatted
        else -> "$formatted ${metric.unit}"
    }
}

private fun formatNumber(number: BigDecimal): String = NumberFormat.getNumberInstance().apply {
    maximumFractionDigits = 4
}.format(number)
