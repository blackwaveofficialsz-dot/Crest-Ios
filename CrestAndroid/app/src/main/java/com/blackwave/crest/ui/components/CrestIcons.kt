package com.blackwave.crest.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
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
    MEGAPHONE, LINE_UP, ALERT_SEARCH, DOCUMENT, COPY, CHECK, SHARE, DELETE, MOON, HALF_CIRCLE, IMAGE, CALENDAR, EXPAND, GLOBE,
    LIGHTBULB, QUESTION_CIRCLE, CHECK_CIRCLE, INFO_FILLED, ERROR_FILLED,
    GRID_GROUP, CLIPBOARD, TAKEOUT, PEOPLE, BELL_BADGE, WARNING_TRIANGLE, ARROW_UP_RIGHT, ARROW_DOWN_RIGHT,
    YEN_CIRCLE, PACKAGE, CART, CLOCK, CALENDAR_CLOCK, GAUGE,
}

@Composable
fun CrestIcon(
    kind: CrestIconKind,
    modifier: Modifier,
    color: Color = Color.Unspecified,
) {
    val tint = if (color == Color.Unspecified) LocalContentColor.current else color
    val cutout = MaterialTheme.colorScheme.surface
    Canvas(modifier) {
        val stroke = 1.7.dp.toPx()
        val roundStroke = Stroke(width = stroke, cap = StrokeCap.Round)
        val w = size.width
        val h = size.height
        fun line(x1: Float, y1: Float, x2: Float, y2: Float, width: Float = stroke) {
            drawLine(tint, Offset(w * x1, h * y1), Offset(w * x2, h * y2), width, StrokeCap.Round)
        }

        when (kind) {
            CrestIconKind.YEN_CIRCLE -> {
                drawCircle(tint, w * .4f, Offset(w * .5f, h * .5f), style = roundStroke)
                line(.35f, .29f, .5f, .47f); line(.65f, .29f, .5f, .47f)
                line(.34f, .48f, .66f, .48f); line(.34f, .61f, .66f, .61f); line(.5f, .47f, .5f, .75f)
            }
            CrestIconKind.PACKAGE -> {
                drawPath(Path().apply {
                    moveTo(w * .5f, h * .1f); lineTo(w * .88f, h * .29f); lineTo(w * .88f, h * .73f)
                    lineTo(w * .5f, h * .92f); lineTo(w * .12f, h * .73f); lineTo(w * .12f, h * .29f); close()
                }, tint, style = roundStroke)
                line(.12f, .29f, .5f, .48f); line(.88f, .29f, .5f, .48f); line(.5f, .48f, .5f, .92f)
                line(.31f, .19f, .69f, .38f)
            }
            CrestIconKind.CART -> {
                line(.08f, .16f, .22f, .16f); line(.22f, .16f, .35f, .69f); line(.35f, .69f, .84f, .69f)
                drawPath(Path().apply {
                    moveTo(w * .25f, h * .28f); lineTo(w * .91f, h * .28f)
                    lineTo(w * .83f, h * .54f); lineTo(w * .32f, h * .54f)
                }, tint, style = roundStroke)
                listOf(.4f, .77f).forEach { x -> drawCircle(tint, w * .055f, Offset(w * x, h * .85f), style = roundStroke) }
            }
            CrestIconKind.CLOCK -> {
                drawCircle(tint, w * .4f, Offset(w * .5f, h * .5f), style = roundStroke)
                line(.5f, .26f, .5f, .52f); line(.5f, .52f, .68f, .52f)
            }
            CrestIconKind.GAUGE -> {
                drawCircle(tint, w * .4f, Offset(w * .5f, h * .5f), style = roundStroke)
                listOf(.22f to .47f, .3f to .28f, .5f to .21f, .7f to .28f, .78f to .47f).forEach { (x, y) ->
                    drawCircle(tint, w * .025f, Offset(w * x, h * y))
                }
                line(.5f, .65f, .68f, .38f); line(.38f, .72f, .62f, .72f)
            }
            CrestIconKind.GRID_GROUP -> {
                drawRoundRect(tint, Offset(w * .12f, h * .16f), Size(w * .3f, h * .68f), CornerRadius(w * .04f), style = roundStroke)
                listOf(.16f, .55f).forEach { y ->
                    drawRoundRect(tint, Offset(w * .54f, h * y), Size(w * .34f, h * .29f), CornerRadius(w * .04f), style = roundStroke)
                }
            }
            CrestIconKind.CLIPBOARD -> {
                drawRoundRect(tint, Offset(w * .22f, h * .2f), Size(w * .56f, h * .69f), CornerRadius(w * .05f), style = roundStroke)
                drawRoundRect(tint, Offset(w * .38f, h * .1f), Size(w * .24f, h * .18f), CornerRadius(w * .04f), style = roundStroke)
                listOf(.43f, .59f, .75f).forEach { y ->
                    drawCircle(tint, w * .025f, Offset(w * .34f, h * y))
                    line(.45f, y, .65f, y)
                }
            }
            CrestIconKind.TAKEOUT -> {
                drawPath(Path().apply {
                    moveTo(w * .1f, h * .32f); lineTo(w * .53f, h * .32f)
                    lineTo(w * .49f, h * .86f); lineTo(w * .14f, h * .86f); close()
                }, tint, style = roundStroke)
                drawArc(tint, 180f, 180f, false, Offset(w * .23f, h * .12f), Size(w * .18f, h * .38f), style = roundStroke)
                drawPath(Path().apply {
                    moveTo(w * .63f, h * .47f); lineTo(w * .91f, h * .47f)
                    lineTo(w * .87f, h * .86f); lineTo(w * .67f, h * .86f); close()
                }, tint, style = roundStroke)
                line(.60f, .45f, .94f, .45f)
                line(.76f, .45f, .8f, .15f); line(.8f, .15f, .92f, .1f)
            }
            CrestIconKind.PEOPLE -> {
                listOf(.3f, .73f).forEach { x ->
                    drawCircle(tint, w * .13f, Offset(w * x, h * .28f), style = roundStroke)
                    drawPath(Path().apply {
                        moveTo(w * (x - .2f), h * .82f)
                        cubicTo(w * (x - .18f), h * .46f, w * (x + .18f), h * .46f, w * (x + .2f), h * .82f)
                        close()
                    }, tint, style = roundStroke)
                }
            }
            CrestIconKind.BELL_BADGE -> {
                drawPath(Path().apply {
                    moveTo(w * .18f, h * .72f)
                    cubicTo(w * .29f, h * .6f, w * .26f, h * .5f, w * .27f, h * .36f)
                    cubicTo(w * .27f, h * .08f, w * .7f, h * .08f, w * .7f, h * .36f)
                    cubicTo(w * .71f, h * .52f, w * .69f, h * .6f, w * .8f, h * .72f)
                    close()
                }, tint, style = roundStroke)
                drawArc(tint, 0f, 180f, false, Offset(w * .39f, h * .72f), Size(w * .2f, h * .19f), style = roundStroke)
                drawCircle(cutout, w * .16f, Offset(w * .78f, h * .2f))
                drawCircle(tint, w * .105f, Offset(w * .78f, h * .2f))
            }
            CrestIconKind.WARNING_TRIANGLE -> {
                drawPath(Path().apply {
                    moveTo(w * .5f, h * .12f); lineTo(w * .91f, h * .84f)
                    lineTo(w * .09f, h * .84f); close()
                }, tint, style = roundStroke)
                line(.5f, .36f, .5f, .56f)
                drawCircle(tint, w * .025f, Offset(w * .5f, h * .7f))
            }
            CrestIconKind.ARROW_UP_RIGHT, CrestIconKind.ARROW_DOWN_RIGHT -> {
                val up = kind == CrestIconKind.ARROW_UP_RIGHT
                val endY = if (up) .22f else .78f
                line(.22f, if (up) .78f else .22f, .78f, endY)
                line(.34f, endY, .78f, endY)
                line(.78f, endY, .78f, if (up) .66f else .34f)
            }
            CrestIconKind.LIGHTBULB -> {
                val bulb = Path().apply {
                    moveTo(w * .38f, h * .67f)
                    cubicTo(w * .38f, h * .52f, w * .22f, h * .52f, w * .22f, h * .34f)
                    cubicTo(w * .22f, h * .04f, w * .78f, h * .04f, w * .78f, h * .34f)
                    cubicTo(w * .78f, h * .52f, w * .62f, h * .52f, w * .62f, h * .67f)
                    close()
                }
                drawPath(bulb, tint, style = roundStroke)
                line(.39f, .79f, .61f, .79f)
                line(.44f, .89f, .56f, .89f)
            }
            CrestIconKind.QUESTION_CIRCLE, CrestIconKind.CHECK_CIRCLE -> {
                drawCircle(tint, w * .4f, center, style = roundStroke)
                if (kind == CrestIconKind.CHECK_CIRCLE) {
                    line(.29f, .5f, .44f, .65f)
                    line(.44f, .65f, .72f, .36f)
                } else {
                    val question = Path().apply {
                        moveTo(w * .36f, h * .35f)
                        cubicTo(w * .36f, h * .19f, w * .66f, h * .2f, w * .65f, h * .37f)
                        cubicTo(w * .65f, h * .49f, w * .5f, h * .47f, w * .5f, h * .59f)
                    }
                    drawPath(question, tint, style = roundStroke)
                    drawCircle(tint, w * .04f, Offset(w * .5f, h * .72f))
                }
            }
            CrestIconKind.INFO_FILLED, CrestIconKind.ERROR_FILLED -> {
                if (kind == CrestIconKind.INFO_FILLED) drawCircle(tint, w * .43f, center)
                else drawPath(Path().apply {
                    repeat(8) { index ->
                        val angle = PI / 8 + index * PI / 4
                        val x = w * (.5f + .46f * cos(angle).toFloat())
                        val y = h * (.5f + .46f * sin(angle).toFloat())
                        if (index == 0) moveTo(x, y) else lineTo(x, y)
                    }
                    close()
                }, tint)
                val info = kind == CrestIconKind.INFO_FILLED
                drawLine(cutout, Offset(w * .5f, h * if (info) .46f else .28f), Offset(w * .5f, h * if (info) .72f else .55f), stroke, StrokeCap.Round)
                drawCircle(cutout, w * .045f, Offset(w * .5f, h * if (info) .29f else .71f))
            }
            CrestIconKind.CALENDAR, CrestIconKind.CALENDAR_CLOCK -> {
                drawRoundRect(tint, Offset(w * .15f, h * .21f), Size(w * .7f, h * .66f), CornerRadius(w * .09f), style = roundStroke)
                line(.15f, .40f, .85f, .40f)
                line(.32f, .12f, .32f, .29f)
                line(.68f, .12f, .68f, .29f)
                listOf(.34f, .65f).forEach { x -> listOf(.55f, .72f).forEach { y -> drawCircle(tint, w * .025f, Offset(w * x, h * y)) } }
                if (kind == CrestIconKind.CALENDAR_CLOCK) {
                    drawCircle(cutout, w * .23f, Offset(w * .77f, h * .77f))
                    drawCircle(tint, w * .22f, Offset(w * .77f, h * .77f), style = roundStroke)
                    line(.77f, .63f, .77f, .77f); line(.77f, .77f, .87f, .77f)
                }
            }
            CrestIconKind.EXPAND -> {
                line(.18f, .42f, .18f, .18f); line(.18f, .18f, .42f, .18f)
                line(.58f, .82f, .82f, .82f); line(.82f, .82f, .82f, .58f)
                line(.2f, .2f, .43f, .43f); line(.57f, .57f, .8f, .8f)
            }
            CrestIconKind.GLOBE -> {
                drawCircle(tint, w * .37f, Offset(w * .5f, h * .5f), style = roundStroke)
                drawOval(tint, Offset(w * .33f, h * .13f), Size(w * .34f, h * .74f), style = roundStroke)
                line(.14f, .5f, .86f, .5f)
            }
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
            CrestIconKind.IMAGE -> {
                drawRoundRect(tint, Offset(w * .11f, h * .17f), Size(w * .78f, h * .66f), CornerRadius(w * .08f), style = roundStroke)
                drawCircle(tint, w * .07f, Offset(w * .68f, h * .38f))
                line(.17f, .74f, .38f, .49f)
                line(.38f, .49f, .53f, .65f)
                line(.53f, .65f, .67f, .53f)
                line(.67f, .53f, .84f, .72f)
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
