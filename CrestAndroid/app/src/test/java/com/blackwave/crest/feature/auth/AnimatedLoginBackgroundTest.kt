package com.blackwave.crest.feature.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.ceil

class AnimatedLoginBackgroundTest {
    @Test
    fun driftIsDeterministicBoundedAndContinuousAtTargetChanges() {
        val seed = 123456
        for (channel in listOf(0, 107, 370)) {
            val duration = 9 + channel % 7 * 1.3
            val targetChange = (ceil(channel * .37) + 1 - channel * .37) * duration
            val before = ribbonDrift(seed, targetChange - .0001, channel)
            val after = ribbonDrift(seed, targetChange + .0001, channel)
            assertTrue(before in -1.0..1.0)
            assertTrue(after in -1.0..1.0)
            assertEquals(before, after, .001)
            assertEquals(before, ribbonDrift(seed, targetChange - .0001, channel), 0.0)
        }
    }
}
