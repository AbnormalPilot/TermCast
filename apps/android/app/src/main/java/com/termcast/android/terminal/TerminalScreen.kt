package com.termcast.android.terminal

import android.annotation.SuppressLint
import android.util.Base64
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.flow.Flow

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun TerminalScreen(
    modifier: Modifier = Modifier,
    onInput: (ByteArray) -> Unit,
    onResize: (Int, Int) -> Unit,
    outputFlow: Flow<ByteArray>,
    resizeFlow: Flow<Pair<Int, Int>>
) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    var isReady by remember { mutableStateOf(false) }
    val pendingOutput = remember { mutableListOf<ByteArray>() }

    LaunchedEffect(isReady) {
        if (!isReady) return@LaunchedEffect
        pendingOutput.forEach { bytes ->
            webView?.termWrite(Base64.encodeToString(bytes, Base64.NO_WRAP))
        }
        pendingOutput.clear()
    }

    LaunchedEffect(Unit) {
        outputFlow.collect { bytes ->
            if (isReady) {
                webView?.termWrite(Base64.encodeToString(bytes, Base64.NO_WRAP))
            } else {
                pendingOutput.add(bytes)
            }
        }
    }

    LaunchedEffect(Unit) {
        resizeFlow.collect { (cols, rows) -> webView?.termResize(cols, rows) }
    }

    Column(modifier = modifier.background(Color.Black)) {
        AndroidView(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            factory = { context ->
                WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = WebViewClient()
                    val bridge = XtermBridge(
                        onInput = onInput,
                        onResize = onResize,
                        onReady = { isReady = true }
                    )
                    addJavascriptInterface(bridge, "TermCastBridge")
                    loadUrl("file:///android_asset/xterm/index.html")
                    webView = this
                }
            }
        )
        KeyboardToolbar(onInput = onInput)
    }
}
