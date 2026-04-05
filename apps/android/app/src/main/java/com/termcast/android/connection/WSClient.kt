package com.termcast.android.connection

import android.util.Base64
import com.termcast.android.auth.PairingCredentials
import com.termcast.android.models.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.*
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

enum class ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, OFFLINE, AUTH_FAILED }

class WSClient(private val scope: CoroutineScope) : WSClientInterface {
    private val client = OkHttpClient.Builder()
        .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
        .build()

    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    override val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _messages = MutableSharedFlow<WSMessageEnvelope>()
    override val messages: SharedFlow<WSMessageEnvelope> = _messages.asSharedFlow()

    private var socket: WebSocket? = null
    private val policy = ReconnectPolicy()
    private var pingPong: PingPong? = null
    private var reconnectJob: Job? = null
    private var didEverConnect = false

    override fun connect(creds: PairingCredentials) {
        didEverConnect = false
        _state.value = ConnectionState.CONNECTING
        val token = buildJWT(creds.secret)
        val request = Request.Builder()
            .url("wss://${creds.host}")
            .header("Authorization", "Bearer $token")
            .build()

        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                didEverConnect = true
                _state.value = ConnectionState.CONNECTED
                policy.reset()
                pingPong = PingPong(
                    onSendPing = { send(PongMessage().toJson()) },
                    onTimeout = { scheduleReconnect(creds) }
                ).also { it.start(scope) }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                val msg = parseWSMessage(text) ?: return
                if (msg.type == "ping") pingPong?.didReceivePong()
                scope.launch { _messages.emit(msg) }
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                pingPong?.stop()
                // response != null means the server replied (HTTP reached server) but upgrade failed.
                // If we never connected with these creds, treat as auth failure.
                if (!didEverConnect && response != null) {
                    _state.value = ConnectionState.AUTH_FAILED
                } else {
                    _state.value = ConnectionState.OFFLINE
                    scheduleReconnect(creds)
                }
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                _state.value = ConnectionState.OFFLINE
                pingPong?.stop()
                scheduleReconnect(creds)
            }
        })
    }

    override fun send(json: String) { socket?.send(json) }

    override fun disconnect() {
        reconnectJob?.cancel()
        pingPong?.stop()
        socket?.cancel()
        socket = null
        didEverConnect = false
        _state.value = ConnectionState.DISCONNECTED
        policy.reset()
    }

    private fun scheduleReconnect(creds: PairingCredentials) {
        reconnectJob?.cancel()
        val delayMs = policy.nextDelayMs()
        reconnectJob = scope.launch {
            delay(delayMs)
            if (isActive) connect(creds)
        }
    }

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
        return "$msg.${base64url(mac.doFinal(msg.toByteArray()))}"
    }
}
