package com.termcast.android.terminal

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun KeyboardToolbar(onInput: (ByteArray) -> Unit) {
    var ctrlPending by remember { mutableStateOf(false) }

    Surface(tonalElevation = 2.dp, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            ToolbarButton("Ctrl", highlighted = ctrlPending) { ctrlPending = !ctrlPending }
            ToolbarButton("Esc") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ESCAPE))
            }
            ToolbarButton("Tab") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.TAB))
            }
            ToolbarButton("↑") {
                if (ctrlPending) { ctrlPending = false; onInput(InputHandler.encodeCtrl('p')) }
                else onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_UP))
            }
            ToolbarButton("↓") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_DOWN))
            }
            ToolbarButton("←") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_LEFT))
            }
            ToolbarButton("→") {
                ctrlPending = false
                onInput(InputHandler.encodeSpecial(InputHandler.SpecialKey.ARROW_RIGHT))
            }
        }
    }
}

@Composable
private fun ToolbarButton(label: String, highlighted: Boolean = false, onClick: () -> Unit) {
    FilledTonalButton(
        onClick = onClick,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
        colors = if (highlighted) ButtonDefaults.filledTonalButtonColors(
            containerColor = MaterialTheme.colorScheme.primary
        ) else ButtonDefaults.filledTonalButtonColors()
    ) {
        Text(label, fontSize = 12.sp)
    }
}
