package com.termcast.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.termcast.android.ui.OfflineScreen
import com.termcast.android.ui.theme.TermCastTheme
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*

class OfflineScreenUITest {
    @get:Rule val composeRule = createComposeRule()

    @Test
    fun offlineScreen_showsMacOfflineText() {
        composeRule.setContent {
            TermCastTheme { OfflineScreen(onRetry = {}) }
        }
        composeRule.onNodeWithText("Mac Offline").assertIsDisplayed()
    }

    @Test
    fun offlineScreen_showsRetryButton() {
        composeRule.setContent {
            TermCastTheme { OfflineScreen(onRetry = {}) }
        }
        composeRule.onNodeWithText("Retry").assertIsDisplayed()
    }

    @Test
    fun offlineScreen_retryButtonCallsCallback() {
        var retried = false
        composeRule.setContent {
            TermCastTheme { OfflineScreen(onRetry = { retried = true }) }
        }
        composeRule.onNodeWithText("Retry").performClick()
        assertTrue("Retry callback should have been called", retried)
    }

    @Test
    fun offlineScreen_showsTailscaleHint() {
        composeRule.setContent {
            TermCastTheme { OfflineScreen(onRetry = {}) }
        }
        composeRule.onNodeWithText(
            "TermCast can't reach your Mac.",
            substring = true
        ).assertIsDisplayed()
    }
}
