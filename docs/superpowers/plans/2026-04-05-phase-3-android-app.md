# Phase 3: Android App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native Android app that scans a QR code to pair with the Mac, connects via OkHttp WebSocket over Tailscale, and renders live interactive terminal sessions using xterm.js in a bundled WebView.

**Architecture:** Single-Activity Compose app. OkHttp WebSocket client with coroutine-based StateFlow. xterm.js 5.3.0 bundled in `assets/xterm/` (zero CDN). `XtermBridge` bidirectional JS↔Kotlin bridge. Credentials in EncryptedSharedPreferences. Keyboard toolbar in Compose pinned above soft keyboard.

**Tech Stack:** Kotlin, Jetpack Compose, OkHttp 4.x, CameraX + ML Kit (QR), EncryptedSharedPreferences, Android API 26+

---

## File Map

```
apps/android/
├── build.gradle.kts                          # Root build file
├── app/
│   ├── build.gradle.kts                      # App module: dependencies
│   ├── src/main/
│   │   ├── AndroidManifest.xml               # CAMERA + INTERNET permissions
│   │   ├── assets/xterm/ → symlink           # Symlink to shared/assets/xterm/
│   │   └── java/com/termcast/android/
│   │       ├── MainActivity.kt               # Single activity, setContent
│   │       ├── models/
│   │       │   ├── Session.kt                # data class Session (JSON)
│   │       │   └── WSMessage.kt              # sealed class WSMessage + subtypes
│   │       ├── auth/
│   │       │   └── PairingRepository.kt      # EncryptedSharedPreferences
│   │       ├── connection/
│   │       │   ├── WSClient.kt               # OkHttp WebSocket + StateFlow
│   │       │   ├── ReconnectPolicy.kt        # Exponential backoff
│   │       │   └── PingPong.kt               # 5s keepalive coroutine
│   │       ├── sessions/
│   │       │   └── SessionViewModel.kt       # StateFlow: session list + state
│   │       ├── onboarding/
│   │       │   └── QRScanScreen.kt           # CameraX + ML Kit
│   │       ├── terminal/
│   │       │   ├── TerminalScreen.kt         # AndroidView(WebView) in Compose
│   │       │   ├── XtermBridge.kt            # Kotlin↔xterm.js bridge
│   │       │   ├── InputHandler.kt           # Keystroke → ANSI bytes → base64
│   │       │   └── KeyboardToolbar.kt        # Compose Row above soft keyboard
│   │       └── ui/
│   │           ├── SessionListScreen.kt      # Tab row of sessions
│   │           ├── SessionTabScreen.kt       # One tab: terminal + toolbar
│   │           ├── OfflineScreen.kt          # "Mac offline" state
│   │           └── theme/Theme.kt            # Dark terminal theme
│   └── src/test/java/com/termcast/android/
│       ├── ReconnectPolicyTest.kt
│       ├── InputHandlerTest.kt
│       └── PairingRepositoryTest.kt
```

---

## Task 1: Android Project + Dependencies

**Files:**
- Create: `apps/android/app/build.gradle.kts`
- Create: `apps/android/AndroidManifest.xml`

- [ ] **Step 1: Create Android project in Android Studio**

File → New Project → Empty Activity  
- Name: `TermCast`  
- Package: `com.termcast.android`  
- Save to: `apps/android/`  
- Min SDK: API 26 (Android 8.0)  
- Language: Kotlin  
- Build config: Kotlin DSL

- [ ] **Step 2: Add dependencies to `app/build.gradle.kts`**

```kotlin
// apps/android/app/build.gradle.kts
dependencies {
    // Jetpack Compose BOM
    implementation(platform("androidx.compose:compose-bom:2024.04.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")

    // WebSocket
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // QR scanning
    implementation("androidx.camera:camera-camera2:1.3.3")
    implementation("androidx.camera:camera-lifecycle:1.3.3")
    implementation("androidx.camera:camera-view:1.3.3")
    implementation("com.google.mlkit:barcode-scanning:17.2.0")

    // Encrypted storage
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.0")

    // JSON
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

    // Testing
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
}
```

Also add to the `plugins` block in `app/build.gradle.kts`:
```kotlin
plugins {
    id("kotlin-android")
    id("kotlinx-serialization")
}
```

And in root `build.gradle.kts`:
```kotlin
plugins {
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.23" apply false
}
```

- [ ] **Step 3: Set AndroidManifest.xml permissions**

```xml
<!-- apps/android/app/src/main/AndroidManifest.xml — add inside <manifest> -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
```

- [ ] **Step 4: Symlink xterm.js assets**

```bash
cd apps/android/app/src/main
mkdir -p assets
ln -s ../../../../../shared/assets/xterm assets/xterm
```

Verify:
```bash
ls apps/android/app/src/main/assets/xterm/
```

Expected: `VERSION`, `xterm.js`, `xterm.css`, `xterm-addon-fit.js`, `index.html`

- [ ] **Step 5: Sync and build**

```bash
cd apps/android
./gradlew assembleDebug 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/android/
git commit -m "feat(android): project scaffold with Compose, OkHttp, CameraX, ML Kit"
```

---

## Task 2: Models — Session + WSMessage

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/models/Session.kt`
- Create: `apps/android/app/src/main/java/com/termcast/android/models/WSMessage.kt`

- [ ] **Step 1: Write failing tests**

```kotlin
// apps/android/app/src/test/java/com/termcast/android/ModelsTest.kt
import com.termcast.android.models.*
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class ModelsTest {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    @Test
    fun sessionDecodesFromJSON() {
        val raw = """{"id":"550e8400-e29b-41d4-a716-446655440000",
            "pid":123,"tty":"/dev/ttys003","shell":"zsh",
            "term_app":"iTerm2","out_pipe":"/tmp/test.out",
            "is_active":true,"cols":80,"rows":24}"""
        val session = json.decodeFromString<Session>(raw)
        assertEquals("zsh", session.shell)
        assertEquals(80, session.cols)
    }

    @Test
    fun pingMessageDecodes() {
        val raw = """{"type":"ping"}"""
        val msg = json.decodeFromString<WSMessageEnvelope>(raw)
        assertEquals("ping", msg.type)
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd apps/android
./gradlew test 2>&1 | grep -E "FAILED|error"
```

Expected: `error: unresolved reference: Session`

- [ ] **Step 3: Implement Session.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/models/Session.kt
package com.termcast.android.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Session(
    val id: String,
    val pid: Int,
    val tty: String,
    val shell: String,
    @SerialName("term_app") val termApp: String,
    @SerialName("out_pipe") val outPipe: String,
    @SerialName("is_active") val isActive: Boolean,
    val cols: Int = 80,
    val rows: Int = 24
)
```

- [ ] **Step 4: Implement WSMessage.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/models/WSMessage.kt
package com.termcast.android.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// Envelope for decoding — type field determines how to interpret the rest
@Serializable
data class WSMessageEnvelope(
    val type: String,
    val sessions: List<Session>? = null,
    val session: Session? = null,
    @SerialName("session_id") val sessionId: String? = null,
    val data: String? = null,
    val cols: Int? = null,
    val rows: Int? = null
)

// Outbound messages (client → server)
@Serializable
data class AttachMessage(
    val type: String = "attach",
    @SerialName("session_id") val sessionId: String
)

@Serializable
data class InputMessage(
    val type: String = "input",
    @SerialName("session_id") val sessionId: String,
    val data: String  // base64
)

@Serializable
data class ResizeMessage(
    val type: String = "resize",
    @SerialName("session_id") val sessionId: String,
    val cols: Int,
    val rows: Int
)

@Serializable
data class PongMessage(val type: String = "pong")

private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

fun WSMessageEnvelope.Companion.parse(text: String): WSMessageEnvelope? =
    runCatching { json.decodeFromString<WSMessageEnvelope>(text) }.getOrNull()

fun AttachMessage.toJson() = json.encodeToString(this)
fun InputMessage.toJson() = json.encodeToString(this)
fun ResizeMessage.toJson() = json.encodeToString(this)
fun PongMessage.toJson() = json.encodeToString(this)

// Companion for parse() extension
private object Companion
fun WSMessageEnvelope.Companion() = Companion
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
cd apps/android
./gradlew test 2>&1 | grep -E "FAILED|passed|tests"
```

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/models/ \
        apps/android/app/src/test/java/com/termcast/android/ModelsTest.kt
git commit -m "feat(android): Session and WSMessage models with kotlinx.serialization"
```

---

## Task 3: PairingRepository

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/auth/PairingRepository.kt`

- [ ] **Step 1: Write failing tests**

```kotlin
// apps/android/app/src/test/java/com/termcast/android/PairingRepositoryTest.kt
import com.termcast.android.auth.PairingCredentials
import org.junit.Assert.*
import org.junit.Test

class PairingRepositoryTest {
    @Test
    fun credentialsRoundTrip() {
        val secret = byteArrayOf(0xAB.toByte(), 0xCD.toByte())
        val creds = PairingCredentials(host = "macbook.ts.net", secret = secret)
        assertEquals("macbook.ts.net", creds.host)
        assertArrayEquals(secret, creds.secret)
    }

    @Test
    fun hexDecoding() {
        val hex = "abcd"
        val bytes = PairingCredentials.fromHex(hex)
        assertArrayEquals(byteArrayOf(0xAB.toByte(), 0xCD.toByte()), bytes)
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: unresolved reference: PairingRepository`

- [ ] **Step 3: Implement PairingRepository.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/auth/PairingRepository.kt
package com.termcast.android.auth

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

data class PairingCredentials(val host: String, val secret: ByteArray) {
    companion object {
        fun fromHex(hex: String): ByteArray {
            check(hex.length % 2 == 0) { "Hex string must have even length" }
            return ByteArray(hex.length / 2) { i ->
                hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        }
    }
}

class PairingRepository(context: Context) {
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "termcast_pairing",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun save(host: String, secretHex: String) {
        prefs.edit()
            .putString("host", host)
            .putString("secret_hex", secretHex)
            .apply()
    }

    fun load(): PairingCredentials? {
        val host = prefs.getString("host", null) ?: return null
        val hex = prefs.getString("secret_hex", null) ?: return null
        return PairingCredentials(host = host, secret = PairingCredentials.fromHex(hex))
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    fun hasCredentials(): Boolean = prefs.getString("host", null) != null
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd apps/android
./gradlew test 2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/auth/ \
        apps/android/app/src/test/java/com/termcast/android/PairingRepositoryTest.kt
git commit -m "feat(android): PairingRepository — EncryptedSharedPreferences credential store"
```

---

## Task 4: ReconnectPolicy + InputHandler

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/connection/ReconnectPolicy.kt`
- Create: `apps/android/app/src/main/java/com/termcast/android/terminal/InputHandler.kt`

- [ ] **Step 1: Write failing tests**

```kotlin
// apps/android/app/src/test/java/com/termcast/android/ReconnectPolicyTest.kt
import com.termcast.android.connection.ReconnectPolicy
import org.junit.Assert.*
import org.junit.Test

class ReconnectPolicyTest {
    @Test fun firstDelayIsOneSecond() {
        val policy = ReconnectPolicy()
        assertEquals(1_000L, policy.nextDelayMs())
    }
    @Test fun doublesEachTime() {
        val policy = ReconnectPolicy()
        assertEquals(1_000L, policy.nextDelayMs())
        assertEquals(2_000L, policy.nextDelayMs())
        assertEquals(4_000L, policy.nextDelayMs())
    }
    @Test fun capsAt60Seconds() {
        val policy = ReconnectPolicy()
        repeat(20) { policy.nextDelayMs() }
        assertTrue(policy.nextDelayMs() <= 60_000L)
    }
    @Test fun resetRestarts() {
        val policy = ReconnectPolicy()
        policy.nextDelayMs(); policy.nextDelayMs()
        policy.reset()
        assertEquals(1_000L, policy.nextDelayMs())
    }
}

// apps/android/app/src/test/java/com/termcast/android/InputHandlerTest.kt
import com.termcast.android.terminal.InputHandler
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class InputHandlerTest {
    @Test fun plainTextPassthrough() {
        val bytes = InputHandler.encode("hello")
        assertEquals("hello", String(bytes, Charsets.UTF_8))
    }
    @Test fun ctrlC() {
        val bytes = InputHandler.encodeCtrl('c')
        assertArrayEquals(byteArrayOf(0x03), bytes)
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
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: unresolved reference: ReconnectPolicy`

- [ ] **Step 3: Implement ReconnectPolicy.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/connection/ReconnectPolicy.kt
package com.termcast.android.connection

class ReconnectPolicy {
    private var attempt = 0
    private val baseSec = 1L
    private val capSec = 60L

    fun nextDelayMs(): Long {
        val delaySec = minOf(baseSec shl attempt, capSec)
        attempt++
        return delaySec * 1000
    }

    fun reset() { attempt = 0 }
}
```

- [ ] **Step 4: Implement InputHandler.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/terminal/InputHandler.kt
package com.termcast.android.terminal

object InputHandler {
    enum class SpecialKey {
        ESCAPE, TAB, ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT
    }

    fun encode(text: String): ByteArray = text.toByteArray(Charsets.UTF_8)

    fun encodeCtrl(letter: Char): ByteArray {
        val lower = letter.lowercaseChar()
        require(lower in 'a'..'z') { "Ctrl key must be a-z" }
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
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
cd apps/android
./gradlew test 2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/connection/ReconnectPolicy.kt \
        apps/android/app/src/main/java/com/termcast/android/terminal/InputHandler.kt \
        apps/android/app/src/test/java/com/termcast/android/ReconnectPolicyTest.kt \
        apps/android/app/src/test/java/com/termcast/android/InputHandlerTest.kt
git commit -m "feat(android): ReconnectPolicy + InputHandler with full test coverage"
```

---

## Task 5: WSClient + PingPong

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/connection/WSClient.kt`
- Create: `apps/android/app/src/main/java/com/termcast/android/connection/PingPong.kt`

- [ ] **Step 1: Implement PingPong.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/connection/PingPong.kt
package com.termcast.android.connection

import kotlinx.coroutines.*

class PingPong(
    private val onSendPing: suspend () -> Unit,
    private val onTimeout: suspend () -> Unit
) {
    private var job: Job? = null
    private var pongReceived = true

    fun start(scope: CoroutineScope) {
        job = scope.launch {
            while (isActive) {
                delay(5_000)
                if (!pongReceived) {
                    onTimeout()
                    return@launch
                }
                pongReceived = false
                onSendPing()
            }
        }
    }

    fun didReceivePong() { pongReceived = true }

    fun stop() { job?.cancel() }
}
```

- [ ] **Step 2: Implement WSClient.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/connection/WSClient.kt
package com.termcast.android.connection

import android.util.Base64
import com.termcast.android.auth.PairingCredentials
import com.termcast.android.models.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.*
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

enum class ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, OFFLINE }

class WSClient(private val scope: CoroutineScope) {
    private val client = OkHttpClient.Builder()
        .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
        .build()

    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _messages = MutableSharedFlow<WSMessageEnvelope>()
    val messages: SharedFlow<WSMessageEnvelope> = _messages.asSharedFlow()

    private var socket: WebSocket? = null
    private val policy = ReconnectPolicy()
    private var pingPong: PingPong? = null
    private var reconnectJob: Job? = null

    fun connect(creds: PairingCredentials) {
        _state.value = ConnectionState.CONNECTING
        val token = buildJWT(creds.secret)
        val request = Request.Builder()
            .url("wss://${creds.host}")
            .header("Authorization", "Bearer $token")
            .build()

        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                _state.value = ConnectionState.CONNECTED
                policy.reset()
                pingPong = PingPong(
                    onSendPing = { send(PongMessage().toJson()) },
                    onTimeout = { scheduleReconnect(creds) }
                ).also { it.start(scope) }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                val msg = WSMessageEnvelope.parse(text) ?: return
                if (msg.type == "ping") pingPong?.didReceivePong()
                scope.launch { _messages.emit(msg) }
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                _state.value = ConnectionState.OFFLINE
                pingPong?.stop()
                scheduleReconnect(creds)
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                _state.value = ConnectionState.OFFLINE
                pingPong?.stop()
                scheduleReconnect(creds)
            }
        })
    }

    fun send(json: String) { socket?.send(json) }

    fun disconnect() {
        reconnectJob?.cancel()
        pingPong?.stop()
        socket?.cancel()
        socket = null
        _state.value = ConnectionState.DISCONNECTED
        policy.reset()
    }

    private fun scheduleReconnect(creds: PairingCredentials) {
        val delayMs = policy.nextDelayMs()
        reconnectJob = scope.launch {
            delay(delayMs)
            if (isActive) connect(creds)
        }
    }

    // Minimal JWT HS256
    private fun buildJWT(secret: ByteArray): String {
        fun base64url(bytes: ByteArray) =
            Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

        val header = base64url("""{"alg":"HS256","typ":"JWT"}""".toByteArray())
        val now = System.currentTimeMillis() / 1000
        val exp = now + 30 * 24 * 3600
        val payload = base64url("""{"sub":"termcast-client","iat":$now,"exp":$exp}""".toByteArray())
        val msg = "$header.$payload"
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val sig = base64url(mac.doFinal(msg.toByteArray()))
        return "$msg.$sig"
    }
}

// Extension for parsing
fun WSMessageEnvelope.Companion.parse(text: String): WSMessageEnvelope? =
    runCatching {
        kotlinx.serialization.json.Json {
            ignoreUnknownKeys = true
        }.decodeFromString<WSMessageEnvelope>(text)
    }.getOrNull()
```

- [ ] **Step 3: Build — expect no errors**

```bash
cd apps/android
./gradlew assembleDebug 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/connection/
git commit -m "feat(android): WSClient (OkHttp) + PingPong keepalive"
```

---

## Task 6: XtermBridge + TerminalScreen

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/terminal/XtermBridge.kt`
- Create: `apps/android/app/src/main/java/com/termcast/android/terminal/TerminalScreen.kt`

- [ ] **Step 1: Implement XtermBridge.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/terminal/XtermBridge.kt
package com.termcast.android.terminal

import android.webkit.JavascriptInterface
import android.webkit.WebView

class XtermBridge(
    private val onInput: (ByteArray) -> Unit,
    private val onResize: (Int, Int) -> Unit,
    private val onReady: () -> Unit
) {
    @JavascriptInterface
    fun onInput(base64: String) {
        val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
        onInput(bytes)
    }

    @JavascriptInterface
    fun onResize(cols: Int, rows: Int) {
        onResize(cols, rows)
    }

    @JavascriptInterface
    fun onReady() {
        onReady()
    }
}

// Extension functions for writing to the terminal
fun WebView.termWrite(base64: String) {
    post {
        evaluateJavascript("window.termWrite('$base64');", null)
    }
}

fun WebView.termResize(cols: Int, rows: Int) {
    post {
        evaluateJavascript("window.termResize($cols, $rows);", null)
    }
}
```

- [ ] **Step 2: Implement TerminalScreen.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/terminal/TerminalScreen.kt
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

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun TerminalScreen(
    modifier: Modifier = Modifier,
    onInput: (ByteArray) -> Unit,
    onResize: (Int, Int) -> Unit,
    outputFlow: kotlinx.coroutines.flow.Flow<ByteArray>,
    resizeFlow: kotlinx.coroutines.flow.Flow<Pair<Int, Int>>
) {
    var webView: WebView? by remember { mutableStateOf(null) }
    var isReady by remember { mutableStateOf(false) }
    val pendingOutput = remember { mutableListOf<ByteArray>() }

    // Forward output bytes to xterm.js
    LaunchedEffect(isReady) {
        if (!isReady) return@LaunchedEffect
        // Flush pending output
        pendingOutput.forEach { bytes ->
            val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
            webView?.termWrite(b64)
        }
        pendingOutput.clear()
    }

    LaunchedEffect(Unit) {
        outputFlow.collect { bytes ->
            if (isReady) {
                val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                webView?.termWrite(b64)
            } else {
                pendingOutput.add(bytes)
            }
        }
    }

    LaunchedEffect(Unit) {
        resizeFlow.collect { (cols, rows) ->
            webView?.termResize(cols, rows)
        }
    }

    Column(modifier = modifier.background(Color.Black)) {
        AndroidView(
            modifier = Modifier.weight(1f).fillMaxWidth(),
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
```

- [ ] **Step 3: Build — expect no errors**

```bash
cd apps/android
./gradlew assembleDebug 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/terminal/XtermBridge.kt \
        apps/android/app/src/main/java/com/termcast/android/terminal/TerminalScreen.kt
git commit -m "feat(android): XtermBridge + TerminalScreen — xterm.js WebView with Kotlin bridge"
```

---

## Task 7: KeyboardToolbar

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/terminal/KeyboardToolbar.kt`

- [ ] **Step 1: Implement KeyboardToolbar.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/terminal/KeyboardToolbar.kt
package com.termcast.android.terminal

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun KeyboardToolbar(onInput: (ByteArray) -> Unit) {
    var ctrlPending by remember { mutableStateOf(false) }

    Surface(
        tonalElevation = 2.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            ToolbarButton(
                label = "Ctrl",
                highlighted = ctrlPending,
                onClick = { ctrlPending = !ctrlPending }
            )
            ToolbarButton("Esc") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ESCAPE))
            }
            ToolbarButton("Tab") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.TAB))
            }
            ToolbarButton("↑") {
                if (ctrlPending) {
                    ctrlPending = false
                    onInput(InputHandler.encodeCtrl('p'))  // Ctrl+P (previous in some apps)
                } else {
                    onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_UP))
                }
            }
            ToolbarButton("↓") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_DOWN))
            }
            ToolbarButton("←") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_LEFT))
            }
            ToolbarButton("→") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_RIGHT))
            }
        }
    }
}

@Composable
private fun ToolbarButton(label: String, highlighted: Boolean = false, onClick: () -> Unit) {
    FilledTonalButton(
        onClick = onClick,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
        colors = if (highlighted) ButtonDefaults.filledTonalButtonColors(
            containerColor = MaterialTheme.colorScheme.primary
        ) else ButtonDefaults.filledTonalButtonColors()
    ) {
        Text(label, fontSize = 12.sp)
    }
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/android
./gradlew assembleDebug 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/terminal/KeyboardToolbar.kt
git commit -m "feat(android): KeyboardToolbar — Compose Ctrl/Esc/Tab/arrows row"
```

---

## Task 8: QRScanScreen

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/onboarding/QRScanScreen.kt`

- [ ] **Step 1: Implement QRScanScreen.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/onboarding/QRScanScreen.kt
package com.termcast.android.onboarding

import android.Manifest
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class PairingPayload(val host: String, val secret: String)

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun QRScanScreen(onPaired: (String, String) -> Unit) {
    val cameraPermission = rememberPermissionState(Manifest.permission.CAMERA)

    LaunchedEffect(Unit) {
        if (!cameraPermission.status.isGranted) cameraPermission.launchPermissionRequest()
    }

    if (!cameraPermission.status.isGranted) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("Camera permission required to scan QR code")
        }
        return
    }

    Box(Modifier.fillMaxSize()) {
        CameraPreview(onQRCode = { raw ->
            runCatching {
                val payload = Json.decodeFromString<PairingPayload>(raw)
                onPaired(payload.host, payload.secret)
            }
        })

        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            Surface(
                modifier = Modifier.padding(32.dp),
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.8f)
            ) {
                Text(
                    "Scan the QR code shown on your Mac",
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
private fun CameraPreview(onQRCode: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var scanned by remember { mutableStateOf(false) }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val provider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }
                val scanner = BarcodeScanning.getClient()
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(ContextCompat.getMainExecutor(ctx)) { proxy ->
                    if (scanned) { proxy.close(); return@setAnalyzer }
                    val image = proxy.image ?: run { proxy.close(); return@setAnalyzer }
                    val inputImg = InputImage.fromMediaImage(image, proxy.imageInfo.rotationDegrees)
                    scanner.process(inputImg)
                        .addOnSuccessListener { barcodes ->
                            barcodes.firstOrNull { it.format == Barcode.FORMAT_QR_CODE }
                                ?.rawValue?.let { value ->
                                    scanned = true
                                    onQRCode(value)
                                }
                        }
                        .addOnCompleteListener { proxy.close() }
                }
                provider.unbindAll()
                provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA,
                    preview, analysis)
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        }
    )
}
```

- [ ] **Step 2: Add accompanist permissions dependency**

```kotlin
// In app/build.gradle.kts
implementation("com.google.accompanist:accompanist-permissions:0.34.0")
```

- [ ] **Step 3: Build — expect no errors**

```bash
cd apps/android
./gradlew assembleDebug 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/onboarding/QRScanScreen.kt
git commit -m "feat(android): QRScanScreen — CameraX + ML Kit barcode scanner"
```

---

## Task 9: SessionViewModel + UI Screens

**Files:**
- Create: `apps/android/app/src/main/java/com/termcast/android/sessions/SessionViewModel.kt`
- Create: `apps/android/app/src/main/java/com/termcast/android/ui/SessionListScreen.kt`
- Create: `apps/android/app/src/main/java/com/termcast/android/ui/SessionTabScreen.kt`
- Create: `apps/android/app/src/main/java/com/termcast/android/ui/OfflineScreen.kt`

- [ ] **Step 1: Implement SessionViewModel.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/sessions/SessionViewModel.kt
package com.termcast.android.sessions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.termcast.android.models.*
import com.termcast.android.connection.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

data class SessionState(
    val session: Session,
    val isEnded: Boolean = false
)

class SessionViewModel(private val wsClient: WSClient) : ViewModel() {
    private val _sessions = MutableStateFlow<List<SessionState>>(emptyList())
    val sessions: StateFlow<List<SessionState>> = _sessions.asStateFlow()

    // Per-session output: map sessionId → SharedFlow<ByteArray>
    private val _outputFlows = mutableMapOf<String, MutableSharedFlow<ByteArray>>()
    fun outputFlow(sessionId: String): SharedFlow<ByteArray> =
        _outputFlows.getOrPut(sessionId) { MutableSharedFlow(replay = 0) }

    val connectionState: StateFlow<ConnectionState> = wsClient.state

    init {
        viewModelScope.launch {
            wsClient.messages.collect { msg -> handleMessage(msg) }
        }
    }

    fun attach(sessionId: String) {
        wsClient.send(AttachMessage(sessionId = sessionId).toJson())
    }

    fun sendInput(sessionId: String, bytes: ByteArray) {
        val b64 = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
        wsClient.send(InputMessage(sessionId = sessionId, data = b64).toJson())
    }

    fun sendResize(sessionId: String, cols: Int, rows: Int) {
        wsClient.send(ResizeMessage(sessionId = sessionId, cols = cols, rows = rows).toJson())
    }

    private fun handleMessage(msg: WSMessageEnvelope) {
        when (msg.type) {
            "sessions" -> {
                _sessions.value = (msg.sessions ?: emptyList()).map { SessionState(it) }
            }
            "session_opened" -> {
                msg.session?.let { session ->
                    val current = _sessions.value.toMutableList()
                    if (current.none { it.session.id == session.id }) {
                        current.add(SessionState(session))
                        _sessions.value = current
                    }
                }
            }
            "session_closed" -> {
                msg.sessionId?.let { id ->
                    _sessions.value = _sessions.value.map { state ->
                        if (state.session.id == id) state.copy(isEnded = true) else state
                    }
                }
            }
            "output" -> {
                val id = msg.sessionId ?: return
                val bytes = msg.data?.let {
                    android.util.Base64.decode(it, android.util.Base64.DEFAULT)
                } ?: return
                viewModelScope.launch {
                    _outputFlows.getOrPut(id) { MutableSharedFlow(replay = 0) }.emit(bytes)
                }
            }
            "ping" -> wsClient.send(PongMessage().toJson())
        }
    }
}
```

- [ ] **Step 2: Implement OfflineScreen.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/ui/OfflineScreen.kt
package com.termcast.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@Composable
fun OfflineScreen(onRetry: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(Icons.Default.WifiOff, contentDescription = null,
            modifier = Modifier.size(64.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))
        Text("Mac Offline", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(8.dp))
        Text(
            "TermCast can't reach your Mac.\nMake sure it's running and connected to Tailscale.",
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(32.dp))
        Button(onClick = onRetry) { Text("Retry") }
    }
}
```

- [ ] **Step 3: Implement SessionTabScreen.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/ui/SessionTabScreen.kt
package com.termcast.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.termcast.android.sessions.SessionState
import com.termcast.android.sessions.SessionViewModel
import com.termcast.android.terminal.TerminalScreen
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

@Composable
fun SessionTabScreen(
    sessionState: SessionState,
    viewModel: SessionViewModel,
    modifier: Modifier = Modifier
) {
    val session = sessionState.session

    Box(modifier = modifier) {
        TerminalScreen(
            modifier = Modifier.fillMaxSize(),
            onInput = { bytes -> viewModel.sendInput(session.id, bytes) },
            onResize = { cols, rows -> viewModel.sendResize(session.id, cols, rows) },
            outputFlow = viewModel.outputFlow(session.id),
            resizeFlow = emptyFlow()
        )

        if (sessionState.isEnded) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopEnd) {
                Surface(
                    modifier = Modifier.padding(8.dp),
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.small
                ) {
                    Text("Session ended", modifier = Modifier.padding(8.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Implement SessionListScreen.kt**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/ui/SessionListScreen.kt
package com.termcast.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.termcast.android.sessions.SessionViewModel

@Composable
fun SessionListScreen(viewModel: SessionViewModel) {
    val sessions by viewModel.sessions.collectAsState()

    if (sessions.isEmpty()) {
        Column(
            modifier = Modifier.fillMaxSize().padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(Icons.Default.Terminal, null, Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))
            Text("No Active Sessions", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(8.dp))
            Text("Open a terminal on your Mac and it will appear here.",
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }

    var selectedTab by remember { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        ScrollableTabRow(selectedTabIndex = selectedTab) {
            sessions.forEachIndexed { index, state ->
                Tab(
                    selected = selectedTab == index,
                    onClick = { selectedTab = index },
                    text = { Text(state.session.shell) }
                )
            }
        }
        sessions.getOrNull(selectedTab)?.let { state ->
            LaunchedEffect(state.session.id) {
                viewModel.attach(state.session.id)
            }
            SessionTabScreen(
                sessionState = state,
                viewModel = viewModel,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}
```

- [ ] **Step 5: Build — expect no errors**

```bash
cd apps/android
./gradlew assembleDebug 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/sessions/ \
        apps/android/app/src/main/java/com/termcast/android/ui/
git commit -m "feat(android): SessionViewModel + SessionListScreen, SessionTabScreen, OfflineScreen"
```

---

## Task 10: MainActivity + Navigation

**Files:**
- Modify: `apps/android/app/src/main/java/com/termcast/android/MainActivity.kt`

- [ ] **Step 1: Implement MainActivity**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/MainActivity.kt
package com.termcast.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.termcast.android.auth.PairingRepository
import com.termcast.android.connection.ConnectionState
import com.termcast.android.connection.WSClient
import com.termcast.android.onboarding.QRScanScreen
import com.termcast.android.sessions.SessionViewModel
import com.termcast.android.ui.*

class MainActivity : ComponentActivity() {
    private lateinit var pairingRepo: PairingRepository
    private lateinit var wsClient: WSClient
    private lateinit var sessionViewModel: SessionViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        pairingRepo = PairingRepository(this)
        wsClient = WSClient(lifecycleScope)
        sessionViewModel = SessionViewModel(wsClient)

        // Connect if already paired
        pairingRepo.load()?.let { creds -> wsClient.connect(creds) }

        setContent {
            TermCastTheme {
                AppNavigation(
                    pairingRepo = pairingRepo,
                    wsClient = wsClient,
                    sessionViewModel = sessionViewModel
                )
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        wsClient.disconnect()
    }
}

@Composable
private fun AppNavigation(
    pairingRepo: PairingRepository,
    wsClient: WSClient,
    sessionViewModel: SessionViewModel
) {
    var isPaired by remember { mutableStateOf(pairingRepo.hasCredentials()) }
    val connectionState by wsClient.state.collectAsState()

    when {
        !isPaired -> QRScanScreen { host, secretHex ->
            pairingRepo.save(host, secretHex)
            pairingRepo.load()?.let { creds -> wsClient.connect(creds) }
            isPaired = true
        }
        connectionState == ConnectionState.OFFLINE -> OfflineScreen {
            pairingRepo.load()?.let { creds -> wsClient.connect(creds) }
        }
        else -> SessionListScreen(viewModel = sessionViewModel)
    }
}
```

- [ ] **Step 2: Add dark theme**

```kotlin
// apps/android/app/src/main/java/com/termcast/android/ui/theme/Theme.kt
package com.termcast.android

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFF4FC3F7),
    background = Color(0xFF000000),
    surface = Color(0xFF121212),
    onSurface = Color(0xFFEEEEEE)
)

@Composable
fun TermCastTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = DarkColors, content = content)
}
```

- [ ] **Step 3: Build release and run all tests**

```bash
cd apps/android
./gradlew assembleDebug test 2>&1 | grep -E "error:|BUILD|FAILED|tests"
```

Expected: `BUILD SUCCESSFUL`, all tests pass.

- [ ] **Step 4: Final commit**

```bash
cd ../..
git add apps/android/app/src/main/java/com/termcast/android/MainActivity.kt \
        apps/android/app/src/main/java/com/termcast/android/ui/theme/
git commit -m "feat(android): MainActivity + navigation — QR onboarding, sessions, offline"
```

---

## Done

Android app complete. All features:
- [ ] QR scan pairing (CameraX + ML Kit)
- [ ] WebSocket connect with JWT (OkHttp)
- [ ] Session list updates live
- [ ] xterm.js WebView renders terminal output
- [ ] Keyboard toolbar with Ctrl/Esc/Tab/arrows
- [ ] Offline screen with retry
- [ ] Exponential backoff reconnect

**Full system done.** All four phases complete:
- Phase 0: Monorepo scaffold
- Phase 1: Mac Agent
- Phase 2: iOS App
- Phase 3: Android App (this)
