// apps/android/app/src/test/java/com/termcast/android/SecurityTest.kt
package com.termcast.android

import com.termcast.android.auth.PairingCredentials
import com.termcast.android.models.parseWSMessage
import com.termcast.android.terminal.InputHandler
import org.junit.Assert.*
import org.junit.Test

class SecurityTest {

    // MARK: - PairingCredentials hex parsing

    @Test fun `PairingCredentials fromHex rejects odd-length input`() {
        try {
            PairingCredentials.fromHex("abc")
            fail("Expected IllegalStateException for odd-length hex")
        } catch (e: IllegalStateException) {
            // expected — check(hex.length % 2 == 0)
        }
    }

    @Test fun `PairingCredentials fromHex rejects non-hex characters`() {
        try {
            PairingCredentials.fromHex("GG")
            fail("Expected exception for non-hex input")
        } catch (e: Exception) {
            // expected — NumberFormatException from toInt(16)
        }
    }

    @Test fun `PairingCredentials fromHex is case-insensitive`() {
        val lower = PairingCredentials.fromHex("abcd")
        val upper = PairingCredentials.fromHex("ABCD")
        assertArrayEquals(lower, upper)
    }

    @Test fun `PairingCredentials equals uses content equality`() {
        val a = PairingCredentials("host", byteArrayOf(1, 2, 3))
        val b = PairingCredentials("host", byteArrayOf(1, 2, 3))
        assertEquals(a, b)
    }

    // MARK: - InputHandler

    @Test fun `InputHandler encode preserves null bytes`() {
        val data = InputHandler.encode("cmd\u0000arg")
        val expected = "cmd\u0000arg".toByteArray(Charsets.UTF_8)
        assertArrayEquals(expected, data)
    }

    @Test fun `InputHandler encodeCtrl rejects non-alpha throws`() {
        try {
            InputHandler.encodeCtrl('1')
            fail("Expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // expected
        }
    }

    @Test fun `InputHandler very large string does not OOM`() {
        val large = "A".repeat(1_000_000)
        val bytes = InputHandler.encode(large)
        assertEquals(1_000_000, bytes.size)
    }

    // MARK: - WSMessage parsing

    @Test fun `parseWSMessage ignores __proto__ injection attempt`() {
        val json = """{"type":"ping","__proto__":{"isAdmin":true},"constructor":"hijack"}"""
        val msg = parseWSMessage(json)
        assertNotNull(msg)
        assertEquals("ping", msg!!.type)
    }

    @Test fun `parseWSMessage handles large sessions array without OOM`() {
        val sessions = (1..100).joinToString(",") { i ->
            val paddedId = i.toString().padStart(4, '0')
            """{"id":"550e8400-e29b-41d4-a716-44665544$paddedId","pid":1,"tty":"/t","shell":"zsh","term_app":"T","out_pipe":"/p","is_active":true,"cols":80,"rows":24}"""
        }
        val raw = """{"type":"sessions","sessions":[$sessions]}"""
        val msg = parseWSMessage(raw)
        assertNotNull("Should parse without crashing", msg)
        assertEquals(100, msg!!.sessions?.size)
    }

    @Test fun `parseWSMessage returns null for deeply malformed JSON`() {
        assertNull(parseWSMessage("{{{{{{{"))
        assertNull(parseWSMessage(""))
    }
}
