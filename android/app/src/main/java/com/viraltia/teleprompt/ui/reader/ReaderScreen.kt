package com.viraltia.teleprompt.ui.reader

import android.app.Activity
import android.view.KeyEvent
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.focusable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.viraltia.teleprompt.R
import com.viraltia.teleprompt.data.ReaderPreferences
import com.viraltia.teleprompt.data.Script
import com.viraltia.teleprompt.domain.PanelGeometry
import com.viraltia.teleprompt.domain.ReaderMotion
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(script: Script, preferences: ReaderPreferences,
    updatePreferences: (ReaderPreferences) -> Unit, close: () -> Unit) {
    val session: ReaderSession = viewModel(key = "reader-${script.id}")
    val context = LocalContext.current
    val activity = context as Activity
    val owner = LocalLifecycleOwner.current
    val density = LocalDensity.current.density
    val focus = remember { FocusRequester() }
    var reader by remember { mutableStateOf<ScriptReaderView?>(null) }
    var progress by remember { mutableFloatStateOf(0f) }
    var showSettings by remember { mutableStateOf(false) }
    var geometry by remember { mutableStateOf(session.geometry) }
    BackHandler { session.pause(); close() }

    DisposableEffect(owner, reader) {
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        reader?.setActive(owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED))
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) { session.pause(); reader?.setActive(false) }
            if (event == Lifecycle.Event.ON_START) reader?.setActive(true)
        }
        owner.lifecycle.addObserver(observer)
        onDispose {
            owner.lifecycle.removeObserver(observer)
            reader?.setActive(false)
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
    DisposableEffect(Unit) {
        onDispose { session.pause(); if (!activity.isChangingConfigurations) session.reset() }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }

    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black).safeDrawingPadding()
        .focusRequester(focus).onPreviewKeyEvent { event ->
            val native = event.nativeKeyEvent
            if (native.action != KeyEvent.ACTION_DOWN) false else when (native.keyCode) {
                KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_BUTTON_A -> {
                    if (native.repeatCount == 0) session.toggle(remote = true); true
                }
                KeyEvent.KEYCODE_BUTTON_B -> { if (native.repeatCount == 0) session.showControls = !session.showControls; true }
                KeyEvent.KEYCODE_MOVE_HOME -> { session.reset(); reader?.reset(); true }
                KeyEvent.KEYCODE_DPAD_UP -> { reader?.step(-24f * density); true }
                KeyEvent.KEYCODE_DPAD_DOWN -> { reader?.step(24f * density); true }
                KeyEvent.KEYCODE_DPAD_RIGHT -> { updatePreferences(preferences.copy(level = (preferences.level + 1).coerceAtMost(30))); true }
                KeyEvent.KEYCODE_DPAD_LEFT -> { updatePreferences(preferences.copy(level = (preferences.level - 1).coerceAtLeast(1))); true }
                else -> false
            }
        }.focusable()) {
        val availableWidth = maxWidth.value
        val availableHeight = maxHeight.value
        val initial = geometry ?: PanelGeometry(
            minOf(420f, availableWidth - 24), maxOf(180f, availableHeight * .48f),
            (availableWidth - minOf(420f, availableWidth - 24)) / 2, 12f)
        val panel = initial.constrain(availableWidth, availableHeight)
        LaunchedEffect(availableWidth, availableHeight) {
            geometry = panel; session.geometry = panel
        }
        fun move(dx: Float, dy: Float) {
            val current = geometry ?: panel
            val next = current.copy(x = current.x + dx / density, y = current.y + dy / density)
                .constrain(availableWidth, availableHeight)
            geometry = next; session.geometry = next
        }
        fun resize(dw: Float, dh: Float) {
            val current = geometry ?: panel
            val next = current.copy(width = current.width + dw / density, height = current.height + dh / density)
                .constrain(availableWidth, availableHeight)
            geometry = next; session.geometry = next
        }
        Box(Modifier.offset { IntOffset((panel.x * density).roundToInt(), (panel.y * density).roundToInt()) }
            .size(panel.width.dp, panel.height.dp).clip(RoundedCornerShape(24.dp)).background(Color(0xFF12161C))) {
            AndroidView(factory = { ctx -> ScriptReaderView(ctx).also { native ->
                val restoredOffset = session.offsetPixels
                native.onPosition = { offset, value -> session.offsetPixels = offset; progress = value }
                native.onTapped = { session.showControls = true }
                reader = native
                native.post { native.restoreOffset(restoredOffset) }
            } }, update = {
                it.configure(script.text, preferences); it.setPlaying(session.playing)
            }, modifier = Modifier.fillMaxSize())

            DragHandle("↔", R.string.move_panel, Modifier.align(Alignment.TopCenter).size(52.dp, 36.dp), panel,
                onDrag = ::move)
            DragHandle("↔", R.string.resize_width, Modifier.align(Alignment.CenterEnd).size(40.dp, 70.dp), panel,
                onDrag = { x, _ -> resize(x, 0f) })
            DragHandle("↕", R.string.resize_height, Modifier.align(Alignment.BottomCenter).size(70.dp, 40.dp), panel,
                onDrag = { _, y -> resize(0f, y) })
            DragHandle("↘", R.string.resize_both, Modifier.align(Alignment.BottomEnd).size(44.dp), panel,
                onDrag = ::resize)
        }
        if (session.countdown > 0) Text("${session.countdown}", fontSize = 100.sp,
            color = Color(0xFF00D3BC), modifier = Modifier.align(Alignment.Center))
        if (session.showControls) Card(Modifier.align(Alignment.BottomCenter).widthIn(max = 460.dp)
            .fillMaxWidth().padding(8.dp)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = { session.pause(); close() }, modifier = Modifier.testTag("close_reader")) { Text(stringResource(R.string.close)) }
                    TextButton(onClick = { session.reset(); reader?.reset() }, modifier = Modifier.testTag("reset_reader")) { Text(stringResource(R.string.beginning)) }
                    Button(onClick = {
                        if (!session.playing && progress >= .9999f) { session.reset(); reader?.reset() }
                        session.toggle()
                    }, modifier = Modifier.testTag("play_reader")) {
                        Text(stringResource(if (session.playing || session.countdown > 0) R.string.pause else R.string.play))
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(onClick = { showSettings = true }) { Text(stringResource(R.string.reader_settings)) }
                    TextButton(onClick = { session.showControls = false }) { Text(stringResource(R.string.hide_controls)) }
                }
                Text(stringResource(R.string.speed_level, ReaderMotion.speed(preferences.level), preferences.level))
                Slider(preferences.level.toFloat(), { updatePreferences(preferences.copy(level = it.roundToInt())) },
                    valueRange = 1f..30f, steps = 28)
                LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
            }
        }
    }
    if (showSettings) ModalBottomSheet(onDismissRequest = { showSettings = false }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp)) {
            Text(stringResource(R.string.font_size) + ": ${preferences.fontSize.roundToInt()}")
            Slider(preferences.fontSize, { updatePreferences(preferences.copy(fontSize = it)) }, valueRange = 16f..82f, steps = 65)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(stringResource(R.string.mirror_horizontal))
                Switch(preferences.horizontal, { updatePreferences(preferences.copy(horizontal = it)) })
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(stringResource(R.string.mirror_vertical))
                Switch(preferences.vertical, { updatePreferences(preferences.copy(vertical = it)) })
            }
            TextButton(onClick = { showSettings = false }) { Text(stringResource(R.string.done)) }
        }
    }
}

@Composable private fun DragHandle(label: String, description: Int, modifier: Modifier,
    geometry: PanelGeometry, onDrag: (Float, Float) -> Unit) {
    val action by rememberUpdatedState(onDrag)
    val text = stringResource(description)
    Box(modifier.semantics { contentDescription = text }
        .pointerInput(Unit) {
            detectDragGestures { change, amount -> change.consume(); action(amount.x, amount.y) }
        }.background(Color.Black.copy(alpha = .5f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
        Text(label, color = Color.White)
    }
}
