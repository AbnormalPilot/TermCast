package com.termcast.android

import com.termcast.android.terminal.XtermBridge
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class XtermBridgeTest {
    @Test fun `onInput decodes base64 and calls callback`() {
        var received: ByteArray? = null
        val bridge = XtermBridge(
            onInputCallback = { received = it },
            onResizeCallback = { _, _ -> },
            onReadyCallback = {}
        )
        val bytes = byteArrayOf(0x1b, 0x5b, 0x41)
        val b64 = android.util.Base64.encodeToString(bytes, android.util.Base64.DEFAULT)
        bridge.onInput(b64)
        assertArrayEquals(bytes, received)
    }

    @Test fun `onResize calls callback with correct dimensions`() {
        var cols = 0; var rows = 0
        val bridge = XtermBridge(
            onInputCallback = {},
            onResizeCallback = { c, r -> cols = c; rows = r },
            onReadyCallback = {}
        )
        bridge.onResize(120, 40)
        assertEquals(120, cols)
        assertEquals(40, rows)
    }

    @Test fun `onReady calls ready callback`() {
        var readyCalled = false
        val bridge = XtermBridge(
            onInputCallback = {},
            onResizeCallback = { _, _ -> },
            onReadyCallback = { readyCalled = true }
        )
        bridge.onReady()
        assertTrue(readyCalled)
    }

    @Test fun `onInput with empty base64 produces empty byte array`() {
        var received: ByteArray? = null
        val bridge = XtermBridge(
            onInputCallback = { received = it },
            onResizeCallback = { _, _ -> },
            onReadyCallback = {}
        )
        // Empty base64 string decodes to empty array
        bridge.onInput("")
        assertNotNull(received)
        assertEquals(0, received!!.size)
    }
}
