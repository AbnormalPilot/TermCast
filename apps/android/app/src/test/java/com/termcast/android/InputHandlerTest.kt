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
}
