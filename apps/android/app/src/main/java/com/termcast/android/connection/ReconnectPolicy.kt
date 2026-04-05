package com.termcast.android.connection

class ReconnectPolicy {
    private var attempt = 0
    private val baseSec = 1L
    private val capSec = 60L

    fun nextDelayMs(): Long {
        val delaySec = minOf(baseSec shl attempt, capSec)
        attempt++
        return delaySec * 1000
    }

    fun reset() { attempt = 0 }
}
