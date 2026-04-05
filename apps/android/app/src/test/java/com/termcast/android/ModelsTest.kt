package com.termcast.android

import com.termcast.android.models.*
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class ModelsTest {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    @Test
    fun sessionDecodesFromJSON() {
        val raw = """{"id":"550e8400-e29b-41d4-a716-446655440000","pid":123,"tty":"/dev/ttys003","shell":"zsh","term_app":"iTerm2","out_pipe":"/tmp/test.out","is_active":true,"cols":80,"rows":24}"""
        val session = json.decodeFromString<Session>(raw)
        assertEquals("zsh", session.shell)
        assertEquals(80, session.cols)
    }

    @Test
    fun pingMessageDecodes() {
        val raw = """{"type":"ping"}"""
        val msg = parseWSMessage(raw)
        assertNotNull(msg)
        assertEquals("ping", msg!!.type)
    }

    @Test
    fun pongMessageSerializes() {
        val json = PongMessage().toJson()
        assertTrue(json.contains("pong"))
    }
}
