package com.termcast.android.ui.theme

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFF4FC3F7),
    background = Color(0xFF000000),
    surface = Color(0xFF121212),
    onSurface = Color(0xFFEEEEEE)
)

@Composable
fun TermCastTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = DarkColors, content = content)
}
