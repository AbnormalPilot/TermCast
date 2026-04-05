package com.termcast.android

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
        val bytes = PairingCredentials.fromHex("abcd")
        assertArrayEquals(byteArrayOf(0xAB.toByte(), 0xCD.toByte()), bytes)
    }

    @Test
    fun hexDecodingUppercase() {
        val bytes = PairingCredentials.fromHex("ABCD")
        assertArrayEquals(byteArrayOf(0xAB.toByte(), 0xCD.toByte()), bytes)
    }
}
