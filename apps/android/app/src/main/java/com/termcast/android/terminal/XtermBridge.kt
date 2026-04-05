package com.termcast.android.terminal

import android.webkit.JavascriptInterface
import android.webkit.WebView

/** Bidirectional bridge between Kotlin and xterm.js running in WebView. */
class XtermBridge(
    private val onInput: (ByteArray) -> Unit,
    private val onResize: (Int, Int) -> Unit,
    private val onReady: () -> Unit
) {
    /** Called by xterm.js when the user types — base64-encoded bytes. */
    @JavascriptInterface
    fun onInput(base64: String) {
        val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
        onInput(bytes)
    }

    /** Called by xterm.js when the terminal is resized. */
    @JavascriptInterface
    fun onResize(cols: Int, rows: Int) {
        onResize(cols, rows)
    }

    /** Called by xterm.js once the terminal is fully initialised. */
    @JavascriptInterface
    fun onReady() {
        onReady()
    }
}

/** Write base64-encoded bytes to the xterm.js terminal. Must be called from any thread. */
fun WebView.termWrite(base64: String) {
    post { evaluateJavascript("window.termWrite('$base64');", null) }
}

/** Resize the xterm.js terminal. Must be called from any thread. */
fun WebView.termResize(cols: Int, rows: Int) {
    post { evaluateJavascript("window.termResize($cols, $rows);", null) }
}
