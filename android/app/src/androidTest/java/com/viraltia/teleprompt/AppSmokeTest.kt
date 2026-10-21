package com.viraltia.teleprompt

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Runs on an isolated test emulator; never changes the clock or grants paid access. */
@RunWith(AndroidJUnit4::class)
class AppSmokeTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun activateFreeTrialCreateScriptAndRead() {
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithTag("start_trial").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("new_script").fetchSemanticsNodes().isNotEmpty()
        }
        if (compose.onAllNodesWithTag("start_trial").fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithTag("start_trial").performClick()
        }
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithTag("new_script").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("new_script").performClick()
        compose.onNodeWithTag("editor_text").performTextInput("Test de lectura.\n\n".repeat(80))
        compose.onNodeWithTag("open_reader").performClick()
        compose.onNodeWithTag("play_reader").assertExists().performClick()
        compose.onNodeWithTag("reset_reader").performClick()
        compose.onNodeWithTag("close_reader").performClick()
        compose.onNodeWithTag("editor_text").assertTextContains("Test de lectura.", substring = true)
    }
}
