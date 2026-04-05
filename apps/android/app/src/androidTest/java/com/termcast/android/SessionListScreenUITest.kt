package com.termcast.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.termcast.android.auth.PairingCredentials
import com.termcast.android.connection.ConnectionState
import com.termcast.android.connection.WSClientInterface
import com.termcast.android.models.WSMessageEnvelope
import com.termcast.android.sessions.SessionViewModel
import com.termcast.android.ui.SessionListScreen
import com.termcast.android.ui.theme.TermCastTheme
import kotlinx.coroutines.flow.*
import org.junit.Rule
import org.junit.Test

class SessionListScreenUITest {
    @get:Rule val composeRule = createComposeRule()

    private fun makeEmptyViewModel(): SessionViewModel {
        val fakeClient = object : WSClientInterface {
            override val state = MutableStateFlow(ConnectionState.CONNECTED).asStateFlow()
            override val messages: SharedFlow<WSMessageEnvelope> =
                MutableSharedFlow<WSMessageEnvelope>().asSharedFlow()
            override fun connect(creds: PairingCredentials) {}
            override fun send(json: String) {}
            override fun disconnect() {}
        }
        return SessionViewModel(fakeClient)
    }

    @Test
    fun emptyState_showsNoActiveSessionsText() {
        val vm = makeEmptyViewModel()
        composeRule.setContent {
            TermCastTheme { SessionListScreen(viewModel = vm) }
        }
        composeRule.onNodeWithText("No Active Sessions").assertIsDisplayed()
    }

    @Test
    fun emptyState_showsInstructionText() {
        val vm = makeEmptyViewModel()
        composeRule.setContent {
            TermCastTheme { SessionListScreen(viewModel = vm) }
        }
        composeRule.onNodeWithText(
            "Open a terminal on your Mac",
            substring = true
        ).assertIsDisplayed()
    }
}
