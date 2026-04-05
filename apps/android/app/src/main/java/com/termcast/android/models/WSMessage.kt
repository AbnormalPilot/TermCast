package com.termcast.android.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

@Serializable
data class WSMessageEnvelope(
    val type: String,
    val sessions: List<Session>? = null,
    val session: Session? = null,
    @SerialName("session_id") val sessionId: String? = null,
    val data: String? = null,
    val cols: Int? = null,
    val rows: Int? = null
)

// Top-level parse function (data classes don't have Companion by default)
fun parseWSMessage(text: String): WSMessageEnvelope? =
    runCatching { json.decodeFromString<WSMessageEnvelope>(text) }.getOrNull()

@Serializable
data class AttachMessage(
    val type: String = "attach",
    @SerialName("session_id") val sessionId: String
)

@Serializable
data class InputMessage(
    val type: String = "input",
    @SerialName("session_id") val sessionId: String,
    val data: String
)

@Serializable
data class ResizeMessage(
    val type: String = "resize",
    @SerialName("session_id") val sessionId: String,
    val cols: Int,
    val rows: Int
)

@Serializable
data class PongMessage(val type: String = "pong")

fun AttachMessage.toJson(): String = json.encodeToString(this)
fun InputMessage.toJson(): String = json.encodeToString(this)
fun ResizeMessage.toJson(): String = json.encodeToString(this)
fun PongMessage.toJson(): String = json.encodeToString(this)
