package com.termcast.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.lifecycle.lifecycleScope
import com.termcast.android.auth.PairingRepository
import com.termcast.android.connection.ConnectionState
import com.termcast.android.connection.WSClient
import com.termcast.android.onboarding.QRScanScreen
import com.termcast.android.sessions.SessionViewModel
import com.termcast.android.ui.*
import com.termcast.android.ui.theme.TermCastTheme

class MainActivity : ComponentActivity() {
    private lateinit var pairingRepo: PairingRepository
    private lateinit var wsClient: WSClient
    private lateinit var sessionViewModel: SessionViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        pairingRepo = PairingRepository(this)
        wsClient = WSClient(lifecycleScope)
        sessionViewModel = SessionViewModel(wsClient)

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
