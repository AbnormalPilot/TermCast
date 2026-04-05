package com.termcast.android.connection

import com.termcast.android.auth.PairingCredentials
import com.termcast.android.models.WSMessageEnvelope
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

interface WSClientInterface {
    val state: StateFlow<ConnectionState>
    val messages: SharedFlow<WSMessageEnvelope>
    fun connect(creds: PairingCredentials)
    fun send(json: String)
    fun disconnect()
}
