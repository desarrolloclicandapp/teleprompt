package com.viraltia.teleprompt.domain

import kotlin.math.roundToInt

object ReaderMotion {
    fun speed(level: Int): Int = (200 + (level.coerceIn(1, 30) - 1) * 2800.0 / 29).roundToInt()

    fun distance(speed: Int, fontScale: Double, seconds: Double): Double {
        if (!seconds.isFinite() || seconds <= 0 || !fontScale.isFinite()) return 0.0
        return speed.coerceIn(200, 3000) * 0.12 * fontScale * seconds.coerceAtMost(1.0 / 12)
    }
}

data class PanelGeometry(val width: Float, val height: Float, val x: Float, val y: Float) {
    fun constrain(canvasWidth: Float, canvasHeight: Float): PanelGeometry {
        val margin = 8f
        val maxWidth = (canvasWidth - margin * 2).coerceAtLeast(1f)
        val maxHeight = (canvasHeight - margin * 2).coerceAtLeast(1f)
        val w = width.coerceIn(minOf(180f, maxWidth), maxWidth)
        val h = height.coerceIn(minOf(180f, maxHeight), maxHeight)
        return copy(width = w, height = h,
            x = x.coerceIn(margin, (canvasWidth - w - margin).coerceAtLeast(margin)),
            y = y.coerceIn(margin, (canvasHeight - h - margin).coerceAtLeast(margin)))
    }
}
