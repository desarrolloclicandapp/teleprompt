package com.viraltia.teleprompt.domain

import org.junit.Assert.*
import org.junit.Test

class ReaderMotionTest {
    @Test fun exactlyThirtyDistinctLevelsReachBothEnds() {
        val values = (1..30).map(ReaderMotion::speed)
        assertEquals(30, values.toSet().size)
        assertEquals(200, values.first()); assertEquals(3000, values.last())
        assertTrue(values.zipWithNext().all { (a, b) -> b > a })
        assertEquals(200, ReaderMotion.speed(-5)); assertEquals(3000, ReaderMotion.speed(90))
    }
    @Test fun distanceIsIndependentOfRefreshRate() {
        val distance = listOf(60, 90, 120).map { hz ->
            (1..hz).sumOf { ReaderMotion.distance(1200, 1.0, 1.0 / hz) }
        }
        distance.forEach { assertEquals(144.0, it, 0.00001) }
    }
    @Test fun invalidOrInterruptedFramesDoNotCauseGiantJumps() {
        assertEquals(0.0, ReaderMotion.distance(200, 1.0, Double.NaN), 0.0)
        assertEquals(0.0, ReaderMotion.distance(200, 1.0, -1.0), 0.0)
        assertEquals(0.0, ReaderMotion.distance(200, Double.POSITIVE_INFINITY, .016), 0.0)
        assertEquals(2.0, ReaderMotion.distance(200, 1.0, 20.0), 0.00001)
    }
    @Test fun landscapeWidthAndHeightAreIndependent() {
        val initial = PanelGeometry(300f, 220f, 10f, 10f)
        val wide = initial.copy(width = 700f).constrain(840f, 390f)
        assertEquals(700f, wide.width, .001f)
        assertEquals(220f, wide.height, .001f)
        val tall = initial.copy(height = 350f).constrain(840f, 390f)
        assertEquals(300f, tall.width, .001f)
        assertEquals(350f, tall.height, .001f)
    }
    @Test fun panelAlwaysStaysInsideTheViewportEvenInSmallWindows() {
        for ((width, height) in listOf(840f to 390f, 390f to 840f, 150f to 120f)) {
            val result = PanelGeometry(1200f, 900f, -100f, 1000f).constrain(width, height)
            assertTrue(result.x >= 0 && result.y >= 0)
            assertTrue(result.x + result.width <= width)
            assertTrue(result.y + result.height <= height)
        }
    }
}
