package com.termcast.android

import com.termcast.android.terminal.InputHandler
import org.junit.Assert.*
import org.junit.Test

class InputHandlerTest {
    @Test fun plainTextPassthrough() {
        assertArrayEquals("hello".toByteArray(), InputHandler.encode("hello"))
    }
    @Test fun ctrlC() {
        assertArrayEquals(byteArrayOf(0x03), InputHandler.encodeCtrl('c'))
    }
    @Test fun ctrlA() {
        assertArrayEquals(byteArrayOf(0x01), InputHandler.encodeCtrl('a'))
    }
    @Test fun escape() {
        assertArrayEquals(byteArrayOf(0x1b), InputHandler.encodeSpecial(InputHandler.SpecialKey.ESCAPE))
    }
    @Test fun tab() {
        assertArrayEquals(byteArrayOf(0x09), InputHandler.encodeSpecial(InputHandler.SpecialKey.TAB))
    }
    @Test fun arrowUp() {
        assertArrayEquals(byteArrayOf(0x1b, 0x5b, 0x41), InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_UP))
    }
    @Test fun arrowDown() {
        assertArrayEquals(byteArrayOf(0x1b, 0x5b, 0x42), InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_DOWN))
    }
    @Test fun arrowLeft() {
        assertArrayEquals(byteArrayOf(0x1b, 0x5b, 0x44), InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_LEFT))
    }
    @Test fun arrowRight() {
        assertArrayEquals(byteArrayOf(0x1b, 0x5b, 0x43), InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_RIGHT))
    }

    // MC/DC: encodeCtrl — lower in 'a'..'z' (= lower >= 'a' && lower <= 'z')

    @Test fun `MC-DC - ctrl z boundary (lower==z, both conditions true)`() {
        assertArrayEquals(byteArrayOf(0x1a), InputHandler.encodeCtrl('z'))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `MC-DC - ctrl backtick (ascii=96, one below a, first condition false)`() {
        InputHandler.encodeCtrl('`')
    }

    @Test(expected = IllegalArgumentException::class)
    fun `MC-DC - ctrl brace (ascii=123, one above z, second condition false)`() {
        InputHandler.encodeCtrl('{')
    }

    @Test fun `MC-DC - ctrl uppercase C is lowercased to c`() {
        assertArrayEquals(byteArrayOf(0x03), InputHandler.encodeCtrl('C'))
    }

    @Test fun `encode empty string returns empty array`() {
        assertArrayEquals(ByteArray(0), InputHandler.encode(""))
    }

    @Test fun `encode multi-char string is UTF-8`() {
        val expected = "hello".toByteArray(Charsets.UTF_8)
        assertArrayEquals(expected, InputHandler.encode("hello"))
    }
}
