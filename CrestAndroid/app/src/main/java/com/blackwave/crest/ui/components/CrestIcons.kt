package com.blackwave.crest.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

enum class CrestIconKind {
    MENU, EDIT, PERSON, SEND, STOP, CLOSE, SEARCH, REFRESH, SETTINGS, ANALYTICS,
    CHEVRON_RIGHT, LOCK, TEAM, THEME, EXIT, PIN, MORE, MENU_CARD, CHART_PIE,
    MEGAPHONE, LINE_UP, ALERT_SEARCH, DOCUMENT, COPY, CHECK, SHARE, DELETE, MOON, HALF_CIRCLE,
}

@Composable
fun CrestIcon(
    kind: CrestIconKind,
    modifier: Modifier,
    color: Color = Color.Unspecified,
) {
    Canvas(modifier) {
        val tint = if (color == Color.Unspecified) Color.Black else color
        val stroke = 1.7.dp.toPx()
        val roundStroke = Stroke(width = stroke, cap = StrokeCap.Round)
        val w = size.width
        val h = size.height
        fun line(x1: Float, y1: Float, x2: Float, y2: Float, width: Float = stroke) {
            drawLine(tint, Offset(w * x1, h * y1), Offset(w * x2, h * y2), width, StrokeCap.Round)
        }

        when (kind) {
            CrestIconKind.MENU -> {
                line(.18f, .28f, .82f, .28f)
                line(.18f, .50f, .82f, .50f)
                line(.18f, .72f, .82f, .72f)
            }
            CrestIconKind.EDIT -> {
                drawRoundRect(tint, Offset(w * .18f, h * .28f), Size(w * .53f, h * .54f), CornerRadius(w * .05f), style = roundStroke)
                line(.42f, .63f, .79f, .26f, stroke * 1.15f)
                line(.72f, .21f, .84f, .33f, stroke * 1.15f)
            }
            CrestIconKind.PERSON -> {
                drawCircle(tint, w * .17f, Offset(w * .50f, h * .34f), style = roundStroke)
                val body = Path().apply {
                    moveTo(w * .22f, h * .82f)
                    cubicTo(w * .26f, h * .57f, w * .74f, h * .57f, w * .78f, h * .82f)
                }
                drawPath(body, tint, style = roundStroke)
            }
            CrestIconKind.SEND -> {
                line(.50f, .78f, .50f, .22f, stroke * 1.15f)
                line(.50f, .22f, .29f, .43f, stroke * 1.15f)
                line(.50f, .22f, .71f, .43f, stroke * 1.15f)
            }
            CrestIconKind.STOP -> drawRoundRect(tint, Offset(w * .31f, h * .31f), Size(w * .38f, h * .38f), CornerRadius(w * .05f))
            CrestIconKind.CLOSE -> { line(.25f, .25f, .75f, .75f); line(.75f, .25f, .25f, .75f) }
            CrestIconKind.SEARCH -> {
                drawCircle(tint, w * .26f, Offset(w * .43f, h * .43f), style = roundStroke)
                line(.62f, .62f, .82f, .82f)
            }
            CrestIconKind.REFRESH -> {
                drawArc(tint, -50f, 280f, false, Offset(w * .19f, h * .19f), Size(w * .62f, h * .62f), style = roundStroke)
                line(.72f, .16f, .82f, .33f)
                line(.82f, .33f, .63f, .33f)
            }
            CrestIconKind.SETTINGS -> {
                drawCircle(tint, w * .13f, center, style = roundStroke)
                drawCircle(tint, w * .31f, center, style = roundStroke)
                repeat(8) { index ->
                    val angle = index * PI / 4
                    line(
                        (.5 + cos(angle) * .31).toFloat(), (.5 + sin(angle) * .31).toFloat(),
                        (.5 + cos(angle) * .42).toFloat(), (.5 + sin(angle) * .42).toFloat(),
                    )
                }
            }
            CrestIconKind.ANALYTICS -> {
                line(.18f, .82f, .18f, .22f)
                line(.18f, .82f, .84f, .82f)
                val graph = Path().apply {
                    moveTo(w * .25f, h * .69f)
                    lineTo(w * .42f, h * .49f)
                    lineTo(w * .57f, h * .59f)
                    lineTo(w * .78f, h * .29f)
                }
                drawPath(graph, tint, style = roundStroke)
            }
            CrestIconKind.CHEVRON_RIGHT -> { line(.39f, .24f, .64f, .50f); line(.64f, .50f, .39f, .76f) }
            CrestIconKind.LOCK -> {
                drawRoundRect(tint, Offset(w * .22f, h * .43f), Size(w * .56f, h * .42f), CornerRadius(w * .08f), style = roundStroke)
                drawArc(tint, 180f, 180f, false, Offset(w * .31f, h * .16f), Size(w * .38f, h * .46f), style = roundStroke)
            }
            CrestIconKind.TEAM -> {
                drawCircle(tint, w * .13f, Offset(w * .40f, h * .38f), style = roundStroke)
                drawArc(tint, 190f, 160f, false, Offset(w * .13f, h * .43f), Size(w * .54f, h * .48f), style = roundStroke)
                line(.70f, .47f, .70f, .77f)
                line(.55f, .62f, .85f, .62f)
            }
            CrestIconKind.THEME -> {
                drawCircle(tint, w * .18f, center, style = roundStroke)
                repeat(8) { index ->
                    val angle = index * PI / 4
                    line(
                        (.5 + cos(angle) * .31).toFloat(), (.5 + sin(angle) * .31).toFloat(),
                        (.5 + cos(angle) * .42).toFloat(), (.5 + sin(angle) * .42).toFloat(),
                    )
                }
            }
            CrestIconKind.MOON -> {
                val crescent = Path().apply {
                    moveTo(w * .65f, h * .14f)
                    cubicTo(w * .34f, h * .18f, w * .17f, h * .49f, w * .31f, h * .72f)
                    cubicTo(w * .45f, h * .95f, w * .79f, h * .86f, w * .87f, h * .57f)
                    cubicTo(w * .66f, h * .72f, w * .41f, h * .52f, w * .65f, h * .14f)
                    close()
                }
                drawPath(crescent, tint, style = roundStroke)
            }
            CrestIconKind.HALF_CIRCLE -> {
                drawCircle(tint, w * .34f, center, style = roundStroke)
                drawArc(tint, 90f, 180f, false, Offset(w * .16f, h * .16f), Size(w * .68f, h * .68f), style = Stroke(width = w * .30f))
            }
            CrestIconKind.DELETE -> {
                drawRoundRect(tint, Offset(w * .28f, h * .32f), Size(w * .44f, h * .52f), CornerRadius(w * .045f), style = roundStroke)
                line(.20f, .25f, .80f, .25f)
                line(.41f, .16f, .59f, .16f)
                line(.43f, .42f, .43f, .73f)
                line(.57f, .42f, .57f, .73f)
            }
            CrestIconKind.EXIT -> {
                drawRoundRect(tint, Offset(w * .16f, h * .18f), Size(w * .43f, h * .64f), CornerRadius(w * .05f), style = roundStroke)
                line(.42f, .50f, .86f, .50f)
                line(.71f, .35f, .86f, .50f)
                line(.86f, .50f, .71f, .65f)
            }
            CrestIconKind.PIN -> {
                line(.37f, .20f, .79f, .62f)
                line(.60f, .22f, .77f, .39f)
                line(.27f, .53f, .47f, .73f)
                line(.27f, .73f, .73f, .27f)
                line(.20f, .80f, .35f, .65f)
            }
            CrestIconKind.MORE -> {
                drawCircle(tint, w * .055f, Offset(w * .25f, h * .50f))
                drawCircle(tint, w * .055f, Offset(w * .50f, h * .50f))
                drawCircle(tint, w * .055f, Offset(w * .75f, h * .50f))
            }
            CrestIconKind.MENU_CARD -> {
                drawRoundRect(tint, Offset(w * .20f, h * .13f), Size(w * .60f, h * .74f), CornerRadius(w * .06f), style = roundStroke)
                drawCircle(tint, w * .035f, Offset(w * .32f, h * .34f))
                drawCircle(tint, w * .035f, Offset(w * .32f, h * .52f))
                drawCircle(tint, w * .035f, Offset(w * .32f, h * .70f))
                line(.43f, .34f, .69f, .34f)
                line(.43f, .52f, .69f, .52f)
                line(.43f, .70f, .61f, .70f)
            }
            CrestIconKind.CHART_PIE -> {
                drawCircle(tint, w * .32f, center, style = roundStroke)
                line(.50f, .50f, .50f, .18f)
                line(.50f, .50f, .79f, .62f)
            }
            CrestIconKind.MEGAPHONE -> {
                val horn = Path().apply {
                    moveTo(w * .24f, h * .43f)
                    lineTo(w * .66f, h * .20f)
                    lineTo(w * .66f, h * .80f)
                    lineTo(w * .24f, h * .57f)
                    close()
                }
                drawPath(horn, tint, style = roundStroke)
                line(.24f, .43f, .14f, .43f)
                line(.14f, .43f, .14f, .57f)
                line(.14f, .57f, .24f, .57f)
                line(.34f, .60f, .43f, .85f)
                drawArc(tint, -58f, 116f, false, Offset(w * .58f, h * .29f), Size(w * .34f, h * .42f), style = roundStroke)
            }
            CrestIconKind.LINE_UP -> {
                line(.14f, .82f, .14f, .18f)
                line(.14f, .82f, .86f, .82f)
                val graph = Path().apply {
                    moveTo(w * .22f, h * .67f)
                    lineTo(w * .41f, h * .46f)
                    lineTo(w * .56f, h * .56f)
                    lineTo(w * .80f, h * .27f)
                }
                drawPath(graph, tint, style = roundStroke)
                line(.67f, .27f, .80f, .27f)
                line(.80f, .27f, .80f, .40f)
            }
            CrestIconKind.ALERT_SEARCH -> {
                drawCircle(tint, w * .25f, Offset(w * .42f, h * .43f), style = roundStroke)
                line(.60f, .61f, .81f, .82f)
                line(.42f, .28f, .42f, .48f)
                drawCircle(tint, w * .025f, Offset(w * .42f, h * .59f))
            }
            CrestIconKind.DOCUMENT -> {
                val document = Path().apply {
                    moveTo(w * .24f, h * .12f)
                    lineTo(w * .61f, h * .12f)
                    lineTo(w * .79f, h * .30f)
                    lineTo(w * .79f, h * .88f)
                    lineTo(w * .24f, h * .88f)
                    close()
                }
                drawPath(document, tint, style = roundStroke)
                line(.61f, .12f, .61f, .30f)
                line(.61f, .30f, .79f, .30f)
                line(.35f, .49f, .68f, .49f)
                line(.35f, .64f, .68f, .64f)
                line(.35f, .78f, .58f, .78f)
            }
            CrestIconKind.COPY -> {
                drawRoundRect(tint, Offset(w * .33f, h * .25f), Size(w * .48f, h * .57f), CornerRadius(w * .06f), style = roundStroke)
                line(.22f, .64f, .22f, .18f)
                line(.22f, .18f, .65f, .18f)
            }
            CrestIconKind.CHECK -> {
                line(.18f, .51f, .40f, .72f, stroke * 1.2f)
                line(.40f, .72f, .83f, .25f, stroke * 1.2f)
            }
            CrestIconKind.SHARE -> {
                line(.50f, .15f, .50f, .62f)
                line(.34f, .31f, .50f, .15f)
                line(.50f, .15f, .66f, .31f)
                line(.22f, .48f, .22f, .84f)
                line(.22f, .84f, .78f, .84f)
                line(.78f, .84f, .78f, .48f)
            }
        }
    }
}
