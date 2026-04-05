package com.termcast.android

import app.cash.turbine.test
import androidx.arch.core.executor.testing.InstantTaskExecutorRule
import com.termcast.android.auth.PairingCredentials
import com.termcast.android.connection.ConnectionState
import com.termcast.android.connection.WSClientInterface
import com.termcast.android.models.WSMessageEnvelope
import com.termcast.android.models.Session
import com.termcast.android.sessions.SessionViewModel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

class FakeWSClient : WSClientInterface {
    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    private val _messages = MutableSharedFlow<WSMessageEnvelope>(extraBufferCapacity = 64)

    override val state: StateFlow<ConnectionState> = _state.asStateFlow()
    override val messages: SharedFlow<WSMessageEnvelope> = _messages.asSharedFlow()

    val sentMessages = mutableListOf<String>()

    override fun connect(creds: PairingCredentials) { _state.value = ConnectionState.CONNECTED }
    override fun send(json: String) { sentMessages.add(json) }
    override fun disconnect() { _state.value = ConnectionState.DISCONNECTED }

    suspend fun emit(msg: WSMessageEnvelope) { _messages.emit(msg) }
    fun setState(s: ConnectionState) { _state.value = s }
}

@RunWith(RobolectricTestRunner::class)
class SessionViewModelTest {
    @get:Rule
    val instantExecutor = InstantTaskExecutorRule()

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var fakeClient: FakeWSClient
    private lateinit var viewModel: SessionViewModel

    @Before fun setUp() {
        Dispatchers.setMain(testDispatcher)
        fakeClient = FakeWSClient()
        viewModel = SessionViewModel(fakeClient)
    }

    @After fun tearDown() { Dispatchers.resetMain() }

    private fun makeSession(
        id: String = "550e8400-e29b-41d4-a716-446655440000",
        shell: String = "zsh"
    ) = Session(
        id = id, pid = 1, tty = "/dev/ttys001", shell = shell,
        termApp = "iTerm2", outPipe = "/tmp/1.out", isActive = true
    )

    @Test fun `initial sessions list is empty`() = runTest {
        viewModel.sessions.test {
            assertTrue(awaitItem().isEmpty())
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test fun `sessions message populates list`() = runTest {
        val sessions = listOf(makeSession())
        viewModel.sessions.test {
            awaitItem() // initial empty
            fakeClient.emit(WSMessageEnvelope(type = "sessions", sessions = sessions))
            advanceUntilIdle()
            val updated = awaitItem()
            assertEquals(1, updated.size)
            assertEquals("zsh", updated.first().session.shell)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test fun `session_opened appends new session`() = runTest {
        val s = makeSession()
        viewModel.sessions.test {
            awaitItem()
            fakeClient.emit(WSMessageEnvelope(type = "session_opened", session = s))
            advanceUntilIdle()
            val updated = awaitItem()
            assertEquals(1, updated.size)
            assertFalse(updated.first().isEnded)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test fun `session_opened is idempotent`() = runTest {
        val s = makeSession()
        fakeClient.emit(WSMessageEnvelope(type = "session_opened", session = s))
        advanceUntilIdle()
        fakeClient.emit(WSMessageEnvelope(type = "session_opened", session = s))
        advanceUntilIdle()
        assertEquals(1, viewModel.sessions.value.size)
    }

    @Test fun `session_closed marks isEnded=true does not remove`() = runTest {
        val s = makeSession()
        fakeClient.emit(WSMessageEnvelope(type = "sessions", sessions = listOf(s)))
        advanceUntilIdle()
        fakeClient.emit(WSMessageEnvelope(type = "session_closed", sessionId = s.id))
        advanceUntilIdle()
        assertEquals(1, viewModel.sessions.value.size)
        assertTrue(viewModel.sessions.value.first().isEnded)
    }

    @Test fun `ping message sends pong`() = runTest {
        fakeClient.emit(WSMessageEnvelope(type = "ping"))
        advanceUntilIdle()
        assertTrue(fakeClient.sentMessages.any { it.contains("pong") })
    }

    @Test fun `attach sends attach message with session id`() = runTest {
        viewModel.attach("abc-123")
        assertTrue(fakeClient.sentMessages.any {
            it.contains("attach") && it.contains("abc-123")
        })
    }

    @Test fun `sendInput base64-encodes bytes`() = runTest {
        viewModel.sendInput("abc", byteArrayOf(0x03))
        // 0x03 base64 = "Aw=="
        assertTrue(fakeClient.sentMessages.any { it.contains("Aw==") })
    }

    @Test fun `outputFlow emits bytes for correct session`() = runTest {
        val sessionId = "abc-123"
        viewModel.outputFlow(sessionId).test {
            val b64 = java.util.Base64.getEncoder().encodeToString(byteArrayOf(0x41, 0x42))
            fakeClient.emit(WSMessageEnvelope(type = "output", sessionId = sessionId, data = b64))
            advanceUntilIdle()
            val bytes = awaitItem()
            assertArrayEquals(byteArrayOf(0x41, 0x42), bytes)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test fun `connectionState mirrors wsClient state`() = runTest {
        viewModel.connectionState.test {
            assertEquals(ConnectionState.DISCONNECTED, awaitItem())
            fakeClient.setState(ConnectionState.CONNECTED)
            assertEquals(ConnectionState.CONNECTED, awaitItem())
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `AUTH_FAILED state emitted when server rejects on first connect`() = runTest {
        val authFailedState = MutableStateFlow(ConnectionState.DISCONNECTED)
        val fakeAuthClient = object : WSClientInterface {
            override val state: StateFlow<ConnectionState> = authFailedState
            override val messages: SharedFlow<WSMessageEnvelope> = MutableSharedFlow()
            override fun connect(creds: PairingCredentials) {
                authFailedState.value = ConnectionState.AUTH_FAILED
            }
            override fun send(json: String) {}
            override fun disconnect() { authFailedState.value = ConnectionState.DISCONNECTED }
        }

        fakeAuthClient.connect(PairingCredentials("host.ts.net", byteArrayOf(1, 2, 3)))
        advanceUntilIdle()

        assertEquals(ConnectionState.AUTH_FAILED, authFailedState.value)
    }
}
