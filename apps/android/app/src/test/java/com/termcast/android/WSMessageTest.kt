package com.termcast.android

import com.termcast.android.models.*
import org.junit.Assert.*
import org.junit.Test

class WSMessageTest {
    @Test fun `parseWSMessage returns null for empty string`() {
        assertNull(parseWSMessage(""))
    }

    @Test fun `parseWSMessage returns null for malformed JSON`() {
        assertNull(parseWSMessage("{not: valid}"))
    }

    @Test fun `parseWSMessage parses unknown type as envelope`() {
        val msg = parseWSMessage("""{"type":"future_unknown_type"}""")
        assertNotNull(msg)
        assertEquals("future_unknown_type", msg!!.type)
    }

    @Test fun `AttachMessage serializes with session_id snake_case`() {
        val msg = AttachMessage(sessionId = "abc-123")
        val out = msg.toJson()
        assertTrue("Expected session_id in JSON", out.contains("session_id"))
        assertFalse("Should not contain sessionId camelCase", out.contains("\"sessionId\""))
    }

    @Test fun `InputMessage serializes data field`() {
        val msg = InputMessage(sessionId = "abc", data = "aGVsbG8=")
        val out = msg.toJson()
        assertTrue(out.contains("aGVsbG8="))
    }

    @Test fun `ResizeMessage serializes cols and rows`() {
        val msg = ResizeMessage(sessionId = "abc", cols = 120, rows = 40)
        val out = msg.toJson()
        assertTrue(out.contains("120"))
        assertTrue(out.contains("40"))
    }

    @Test fun `PongMessage serializes type as pong`() {
        val msg = PongMessage()
        val out = msg.toJson()
        assertTrue(out.contains("\"pong\""))
    }

    @Test fun `parseWSMessage decodes sessions array`() {
        val raw = """{"type":"sessions","sessions":[
            {"id":"550e8400-e29b-41d4-a716-446655440000","pid":1,
             "tty":"/dev/ttys001","shell":"bash","term_app":"Terminal",
             "out_pipe":"/tmp/1.out","is_active":true,"cols":80,"rows":24}
        ]}"""
        val msg = parseWSMessage(raw)
        assertNotNull(msg)
        assertEquals(1, msg!!.sessions?.size)
        assertEquals("bash", msg.sessions?.first()?.shell)
    }

    @Test fun `parseWSMessage decodes session_id field`() {
        val raw = """{"type":"session_closed","session_id":"abc-123"}"""
        val msg = parseWSMessage(raw)
        assertNotNull(msg)
        assertEquals("abc-123", msg!!.sessionId)
    }

    @Test fun `Session defaults cols=80 rows=24`() {
        val raw = """{"id":"550e8400-e29b-41d4-a716-446655440000","pid":1,
            "tty":"/dev/t","shell":"zsh","term_app":"T","out_pipe":"/t",
            "is_active":true}"""
        val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
        val session = json.decodeFromString<Session>(raw)
        assertEquals(80, session.cols)
        assertEquals(24, session.rows)
    }
}
