package com.termcast.android.terminal

object InputHandler {
    enum class SpecialKey {
        ESCAPE, TAB, ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT
    }

    fun encode(text: String): ByteArray = text.toByteArray(Charsets.UTF_8)

    fun encodeCtrl(letter: Char): ByteArray {
        val lower = letter.lowercaseChar()
        require(lower in 'a'..'z') { "Ctrl key must be a-z, got: $letter" }
        return byteArrayOf((lower.code - 'a'.code + 1).toByte())
    }

    fun encodeSpecial(key: SpecialKey): ByteArray = when (key) {
        SpecialKey.ESCAPE      -> byteArrayOf(0x1b)
        SpecialKey.TAB         -> byteArrayOf(0x09)
        SpecialKey.ARROW_UP    -> byteArrayOf(0x1b, 0x5b, 0x41)
        SpecialKey.ARROW_DOWN  -> byteArrayOf(0x1b, 0x5b, 0x42)
        SpecialKey.ARROW_RIGHT -> byteArrayOf(0x1b, 0x5b, 0x43)
        SpecialKey.ARROW_LEFT  -> byteArrayOf(0x1b, 0x5b, 0x44)
    }
}
