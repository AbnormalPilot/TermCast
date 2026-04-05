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
