package com.termcast.android

import com.termcast.android.connection.ReconnectPolicy
import org.junit.Assert.*
import org.junit.Test

class ReconnectPolicyTest {
    @Test fun firstDelayIsOneSecond() {
        assertEquals(1_000L, ReconnectPolicy().nextDelayMs())
    }
    @Test fun doublesEachTime() {
        val p = ReconnectPolicy()
        assertEquals(1_000L, p.nextDelayMs())
        assertEquals(2_000L, p.nextDelayMs())
        assertEquals(4_000L, p.nextDelayMs())
    }
    @Test fun capsAt60Seconds() {
        val p = ReconnectPolicy()
        repeat(20) { p.nextDelayMs() }
        assertTrue(p.nextDelayMs() <= 60_000L)
    }
    @Test fun resetRestarts() {
        val p = ReconnectPolicy()
        p.nextDelayMs(); p.nextDelayMs()
        p.reset()
        assertEquals(1_000L, p.nextDelayMs())
    }

    // MC/DC: nextDelayMs() cap boundary

    @Test fun `MC-DC - attempt 5 produces 32s (below cap)`() {
        val p = ReconnectPolicy()
        repeat(5) { p.nextDelayMs() }
        assertEquals(32_000L, p.nextDelayMs())
    }

    @Test fun `MC-DC - attempt 6 produces 60s (cap reached)`() {
        val p = ReconnectPolicy()
        repeat(6) { p.nextDelayMs() }
        assertEquals(60_000L, p.nextDelayMs())
    }

    @Test fun `delay sequence doubles for attempts 0-5`() {
        val p = ReconnectPolicy()
        val expected = listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 32_000L)
        val actual = (0..5).map { p.nextDelayMs() }
        assertEquals(expected, actual)
    }

    @Test fun `reset returns to initial sequence`() {
        val p = ReconnectPolicy()
        p.nextDelayMs(); p.nextDelayMs(); p.nextDelayMs()
        p.reset()
        val after = (0..2).map { p.nextDelayMs() }
        assertEquals(listOf(1_000L, 2_000L, 4_000L), after)
    }
}
