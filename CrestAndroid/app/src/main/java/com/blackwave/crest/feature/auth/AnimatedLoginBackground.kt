package com.blackwave.crest.feature.auth

import android.animation.ValueAnimator
import android.graphics.BlurMaskFilter
import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Color as AndroidColor
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.roundToInt
import kotlin.random.Random

@Composable
internal fun AnimatedLoginBackground() {
    val renderer = remember { LoginRibbonRenderer(Random.nextInt(1_000_000)) }
    val motionEnabled = remember { ValueAnimator.areAnimatorsEnabled() }
    var elapsed by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(motionEnabled) {
        if (motionEnabled) {
            var startedAt = 0L
            while (true) {
                withFrameNanos { frame ->
                    if (startedAt == 0L) startedAt = frame
                    elapsed = (frame - startedAt) / 1_000_000_000.0
                }
            }
        }
    }
    Canvas(Modifier.fillMaxSize()) {
        drawIntoCanvas { renderer.draw(it.nativeCanvas, size.width, size.height, elapsed) }
    }
}

// The geometry and light stops below follow AnimatedLoginBackground.swift.
// ponytail: render at 20% resolution; the broad blurs hide upscaling while full-size masks miss frame deadlines.
private class LoginRibbonRenderer(private val seed: Int) {
    private data class Sample(
        val x: Double, val y: Double, val nx: Double, val ny: Double,
        val width: Double, val bias: Double, val scatter: Double,
    )

    private val driftCache = DoubleArray(512)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val screen = PorterDuffXfermode(PorterDuff.Mode.SCREEN)
    private var bitmap: Bitmap? = null

    fun draw(canvas: AndroidCanvas, width: Float, height: Float, time: Double) {
        val renderWidth = (width * .2f).roundToInt().coerceAtLeast(1)
        val renderHeight = (height * .2f).roundToInt().coerceAtLeast(1)
        val buffer = bitmap?.takeIf { it.width == renderWidth && it.height == renderHeight }
            ?: Bitmap.createBitmap(renderWidth, renderHeight, Bitmap.Config.ARGB_8888).also { bitmap = it }
        drawScene(AndroidCanvas(buffer), renderWidth.toFloat(), renderHeight.toFloat(), time)
        canvas.drawBitmap(buffer, null, RectF(0f, 0f, width, height), bitmapPaint)
    }

    private fun drawScene(canvas: AndroidCanvas, width: Float, height: Float, time: Double) {
        canvas.drawColor(AndroidColor.BLACK)
        driftCache.fill(Double.NaN)
        for (index in 0..3) drawRibbon(canvas, width, height, time, index)
        paint.apply {
            shader = LinearGradient(
                0f, 0f, 0f, height,
                intArrayOf(black(.24), AndroidColor.TRANSPARENT, AndroidColor.TRANSPARENT, black(.66)),
                floatArrayOf(0f, .2f, .48f, 1f), Shader.TileMode.CLAMP,
            )
            maskFilter = null
            xfermode = null
            alpha = 255
        }
        canvas.drawRect(0f, 0f, width, height, paint)
    }

    private fun drawRibbon(canvas: AndroidCanvas, w: Float, h: Float, time: Double, index: Int) {
        val channel = index * 100
        val lane = doubleArrayOf(-.08, .62, 1.02, .28)[index]
        val direction = if (index % 2 == 0) 1.0 else -1.0
        val shortSide = min(w, h).toDouble()
        val width = shortSide * doubleArrayOf(.56, .38, .29, .19)[index] *
            (1 + drift(time, channel + 8) * .18)
        val p0x = w * (lane + drift(time, channel) * .44)
        val p0y = h * -.35
        val p1x = w * (lane + direction * .65 + drift(time, channel + 2) * .75)
        val p1y = h * (.18 + drift(time, channel + 3) * .16)
        val p2x = w * (1 - lane - direction * .65 + drift(time, channel + 4) * .75)
        val p2y = h * (.72 + drift(time, channel + 5) * .20)
        val p3x = w * (1 - lane + drift(time, channel + 1) * .55)
        val p3y = h * 1.35

        val samples = ArrayList<Sample>(81)
        for (step in 0..80) {
            val t = step / 80.0
            val u = 1 - t
            val along = t + time * .012
            val bend = variation(along * 4.3, time, channel + 12)
            val detail = variation(along * 10.7, time, channel + 25)
            val breadth = variation(along * 5.1, time, channel + 40)
            val bias = variation(along * 7.4, time, channel + 55)
            val scatter = variation(along * 3.8, time, channel + 70)
            val dx = 3 * u * u * (p1x - p0x) + 6 * u * t * (p2x - p1x) + 3 * t * t * (p3x - p2x)
            val dy = 3 * u * u * (p1y - p0y) + 6 * u * t * (p2y - p1y) + 3 * t * t * (p3y - p2y)
            val length = hypot(dx, dy).coerceAtLeast(1.0)
            val nx = dy / length
            val ny = -dx / length
            val displacement = shortSide * (bend * .23 + detail * .045)
            samples += Sample(
                u * u * u * p0x + 3 * u * u * t * p1x + 3 * u * t * t * p2x + t * t * t * p3x + nx * displacement,
                u * u * u * p0y + 3 * u * u * t * p1y + 3 * u * t * t * p2y + t * t * t * p3y + ny * displacement,
                nx, ny, width * (.16 + ((breadth + 1) * .5).pow(1.6) * 1.4), bias, scatter,
            )
        }

        fun contour(scale: Double, dispersion: Double, offset: Double = 0.0): Path = Path().apply {
            for (side in intArrayOf(1, -1)) {
                for (step in samples.indices) {
                    val sample = samples[if (side > 0) step else samples.lastIndex - step]
                    val spread = shortSide * dispersion
                    val radius = sample.width * scale * (.5 + side * sample.bias * .24) +
                        spread * (.65 + sample.scatter * side * .35)
                    val distance = side * radius + sample.width * offset + spread * sample.scatter
                    val x = (sample.x + sample.nx * distance).toFloat()
                    val y = (sample.y + sample.ny * distance).toFloat()
                    if (side > 0 && step == 0) moveTo(x, y) else lineTo(x, y)
                }
            }
            close()
        }

        val lightPosition = drift(time, channel + 6)
        val intensity = .72 + drift(time, channel + 7) * .16
        val startX = (w * (-.2 + lightPosition * .35)).toFloat()
        val startY = h * -.1f
        val endX = (w * (1.1 + lightPosition * .25)).toFloat()
        val endY = h * 1.05f
        val stops = floatArrayOf(0f, .18f, .35f, .48f, .65f, .83f, 1f)
        val surface = LinearGradient(
            startX, startY, endX, endY,
            intArrayOf(
                AndroidColor.TRANSPARENT, white(.12), white(intensity * .64), white(intensity),
                AndroidColor.argb(alpha(.88), 31, 31, 31), white(.22), AndroidColor.TRANSPARENT,
            ),
            stops, Shader.TileMode.CLAMP,
        )

        paint.apply {
            shader = surface
            maskFilter = BlurMaskFilter((shortSide * .14).toFloat(), BlurMaskFilter.Blur.NORMAL)
            xfermode = screen
            alpha = alpha(.62)
        }
        canvas.drawPath(contour(1.5, .20), paint)

        paint.apply {
            maskFilter = BlurMaskFilter((shortSide * if (index == 0) .045 else .028).toFloat(), BlurMaskFilter.Blur.NORMAL)
            xfermode = null
            alpha = 255
        }
        canvas.drawPath(contour(1.0, 0.0), paint)

        paint.apply {
            shader = LinearGradient(
                startX, startY, endX, endY,
                intArrayOf(AndroidColor.TRANSPARENT, white(intensity * .5), white(intensity * .72), AndroidColor.TRANSPARENT),
                floatArrayOf(.1f, .43f, .52f, .74f), Shader.TileMode.CLAMP,
            )
            maskFilter = BlurMaskFilter((shortSide * .035).toFloat(), BlurMaskFilter.Blur.NORMAL)
            xfermode = screen
        }
        canvas.drawPath(contour(.24, .025, -.20), paint)
    }

    private fun variation(position: Double, time: Double, channel: Int): Double {
        val step = floor(position).toInt()
        val fraction = position - floor(position)
        val eased = fraction * fraction * (3 - 2 * fraction)
        val from = drift(time, channel + step)
        return from + (drift(time, channel + step + 1) - from) * eased
    }

    private fun drift(time: Double, channel: Int): Double {
        if (channel in driftCache.indices && !driftCache[channel].isNaN()) return driftCache[channel]
        val result = ribbonDrift(seed, time, channel)
        if (channel in driftCache.indices) driftCache[channel] = result
        return result
    }

    private fun white(opacity: Double): Int = AndroidColor.argb(alpha(opacity), 255, 255, 255)
    private fun black(opacity: Double): Int = AndroidColor.argb(alpha(opacity), 0, 0, 0)
    private fun alpha(opacity: Double): Int = (opacity * 255).toInt().coerceIn(0, 255)
}

internal fun ribbonDrift(seed: Int, time: Double, channel: Int): Double {
    val position = time / (9 + channel % 7 * 1.3) + channel * .37
    val step = floor(position).toInt()
    val fraction = position - floor(position)
    val eased = fraction * fraction * fraction * (fraction * (fraction * 6 - 15) + 10)
    fun randomUnit(at: Int): Double {
        val value = sin((seed + at * 1013 + channel * 7919).toDouble() * 12.9898) * 43758.5453
        return value - floor(value)
    }
    val from = randomUnit(step)
    return (from + (randomUnit(step + 1) - from) * eased) * 2 - 1
}
