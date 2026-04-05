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
                    Text(
                        "Session ended",
                        modifier = Modifier.padding(8.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
        }
    }
}
