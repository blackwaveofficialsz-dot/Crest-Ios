package com.blackwave.crest.feature.chat

import android.animation.ValueAnimator
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.sin

@Composable
internal fun CrestWaveThinkingIndicator(label: String) {
    val transition = rememberInfiniteTransition(label = "Crest 思考波形")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1800, easing = LinearEasing), RepeatMode.Restart),
        label = "波形相位",
    )
    val phase = if (ValueAnimator.areAnimatorsEnabled()) progress * 2 * PI else 0.22 * 2 * PI
    Canvas(Modifier.size(48.dp, 24.dp).semantics { contentDescription = label.ifEmpty { "正在生成回复" } }) {
        fun wave(offset: Float): Path = Path().apply {
            var x = 0f
            while (x <= size.width) {
                val normalized = x / size.width
                val edgeTaper = .42 + sin(normalized * PI) * .58
                val y = size.height / 2 + offset * edgeTaper.toFloat() +
                    sin(normalized * 2.25 * PI + phase).toFloat() * 4.2.dp.toPx()
                if (x == 0f) moveTo(x, y) else lineTo(x, y)
                x += 1f
            }
        }
        drawPath(wave(0f), Color.White.copy(alpha = .96f), style = Stroke(width = 9.dp.toPx(), cap = StrokeCap.Round))
        repeat(3) { index ->
            drawPath(wave((index - 1) * 2.5.dp.toPx()), Color.Black.copy(alpha = .86f), style = Stroke(width = .85.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}
