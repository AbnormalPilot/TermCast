package com.termcast.android.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Session(
    val id: String,
    val pid: Int,
    val tty: String,
    val shell: String,
    @SerialName("term_app") val termApp: String,
    @SerialName("out_pipe") val outPipe: String,
    @SerialName("is_active") val isActive: Boolean,
    val cols: Int = 80,
    val rows: Int = 24
)
