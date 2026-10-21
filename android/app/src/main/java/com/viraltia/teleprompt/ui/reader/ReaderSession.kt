package com.viraltia.teleprompt.ui.reader

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.viraltia.teleprompt.domain.PanelGeometry
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ReaderSession : ViewModel() {
    var playing by mutableStateOf(false); private set
    var countdown by mutableIntStateOf(0); private set
    var hasStarted = false
    var offsetPixels = 0f
    var geometry: PanelGeometry? = null
    var showControls by mutableStateOf(true)
    private var countdownTask: Job? = null

    fun toggle(remote: Boolean = false) {
        if (playing || countdown > 0) { pause(); return }
        if (hasStarted || remote) { hasStarted = true; playing = true; return }
        countdownTask = viewModelScope.launch {
            for (number in 3 downTo 1) { countdown = number; delay(1000) }
            countdown = 0; hasStarted = true; playing = true
        }
    }
    fun pause() { countdownTask?.cancel(); countdownTask = null; countdown = 0; playing = false }
    fun reset() { pause(); offsetPixels = 0f; hasStarted = false }
}
