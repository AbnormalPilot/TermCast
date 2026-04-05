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

class SessionViewModel(private val wsClient: WSClientInterface) : ViewModel() {
    private val _sessions = MutableStateFlow<List<SessionState>>(emptyList())
    val sessions: StateFlow<List<SessionState>> = _sessions.asStateFlow()

    private val outputFlows = mutableMapOf<String, MutableSharedFlow<ByteArray>>()

    fun outputFlow(sessionId: String): SharedFlow<ByteArray> =
        outputFlows.getOrPut(sessionId) { MutableSharedFlow(replay = 0) }

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
                    if (_sessions.value.none { it.session.id == session.id }) {
                        _sessions.value = _sessions.value + SessionState(session)
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
                    outputFlows.getOrPut(id) { MutableSharedFlow(replay = 0) }.emit(bytes)
                }
            }
            "ping" -> wsClient.send(PongMessage().toJson())
        }
    }
}
