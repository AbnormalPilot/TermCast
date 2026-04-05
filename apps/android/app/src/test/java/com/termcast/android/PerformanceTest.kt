// apps/android/app/src/test/java/com/termcast/android/PerformanceTest.kt
package com.termcast.android

import com.termcast.android.models.*
import com.termcast.android.terminal.InputHandler
import org.junit.Assert.*
import org.junit.Test
import kotlin.system.measureTimeMillis

class PerformanceTest {

    @Test fun `parseWSMessage 10000 ping messages completes in under 2 seconds`() {
        val json = """{"type":"ping"}"""
        val elapsed = measureTimeMillis {
            repeat(10_000) { parseWSMessage(json) }
        }
        assertTrue("10k JSON parses should complete < 2000ms, took ${elapsed}ms", elapsed < 2_000)
    }

    @Test fun `parseWSMessage sessions with 50 items completes in under 1000ms for 1000 calls`() {
        val sessionTemplate = """{"id":"550e8400-e29b-41d4-a716-%s","pid":%d,"tty":"/t","shell":"zsh","term_app":"T","out_pipe":"/p","is_active":true,"cols":80,"rows":24}"""
        val sessions = (1..50).joinToString(",") { i ->
            sessionTemplate.format(i.toString().padStart(12, '0'), i)
        }
        val json = """{"type":"sessions","sessions":[$sessions]}"""

        val elapsed = measureTimeMillis {
            repeat(1_000) { parseWSMessage(json) }
        }
        assertTrue("1k large-sessions parses should complete < 1000ms, took ${elapsed}ms", elapsed < 1_000)
    }

    @Test fun `InputHandler encode 1MB string completes in under 1000ms`() {
        val large = "A".repeat(1_000_000)
        val elapsed = measureTimeMillis {
            InputHandler.encode(large)
        }
        assertTrue("1MB encode should complete < 1000ms, took ${elapsed}ms", elapsed < 1_000)
    }

    @Test fun `AttachMessage toJson 10000 times completes under 500ms`() {
        val msg = AttachMessage(sessionId = "550e8400-e29b-41d4-a716-446655440000")
        val elapsed = measureTimeMillis {
            repeat(10_000) { msg.toJson() }
        }
        assertTrue("10k serializations should complete < 500ms, took ${elapsed}ms", elapsed < 500)
    }

    @Test fun `InputMessage toJson 1KB payload 1000 times under 500ms`() {
        // Use java.util.Base64 — no android.util.Base64 in JVM unit tests
        val b64 = java.util.Base64.getEncoder().encodeToString(ByteArray(1024) { it.toByte() })
        val msg = InputMessage(sessionId = "abc", data = b64)
        val elapsed = measureTimeMillis {
            repeat(1_000) { msg.toJson() }
        }
        assertTrue("1k 1KB message serializations should complete < 500ms, took ${elapsed}ms", elapsed < 500)
    }
}
