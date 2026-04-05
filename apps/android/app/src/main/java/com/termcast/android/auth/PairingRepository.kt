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

    override fun equals(other: Any?): Boolean =
        other is PairingCredentials && host == other.host && secret.contentEquals(other.secret)

    override fun hashCode(): Int = 31 * host.hashCode() + secret.contentHashCode()
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

    fun clear() { prefs.edit().clear().apply() }

    fun hasCredentials(): Boolean = prefs.getString("host", null) != null
}
