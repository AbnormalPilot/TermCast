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
}
