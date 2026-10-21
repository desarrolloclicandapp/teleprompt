package com.viraltia.teleprompt.ui

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.viraltia.teleprompt.R
import com.viraltia.teleprompt.data.*
import com.viraltia.teleprompt.domain.AccessState
import com.viraltia.teleprompt.ui.reader.ReaderScreen

private val Mint = Color(0xFF00D3BC)

@Composable
fun TelepromptApp(model: AppViewModel, activity: Activity) {
    val access by model.app.access.state.collectAsStateWithLifecycle()
    val billing by model.app.access.billing.state.collectAsStateWithLifecycle()
    val route by model.route.collectAsStateWithLifecycle()
    val draft by model.draft.collectAsStateWithLifecycle()
    val readerScript by model.readerScript.collectAsStateWithLifecycle()
    val preferences by model.preferences.collectAsStateWithLifecycle()
    val error by model.message.collectAsStateWithLifecycle()
    val imported by model.importResult.collectAsStateWithLifecycle()
    MaterialTheme(colorScheme = darkColorScheme(primary = Mint, secondary = Mint,
        background = Color(0xFF080B0F), surface = Color(0xFF10151E))) {
        Surface(Modifier.fillMaxSize()) {
            if (!access.ready) Loading() else if (access.error != null || access.state in setOf(AccessState.NOT_STARTED, AccessState.EXPIRED)) {
                AccessScreen(access, billing, { model.app.access.startTrial() },
                    { model.app.access.billing.purchase(activity) },
                    { model.app.access.billing.refresh(true) }, { model.app.access.retry() })
            } else {
                when (route) {
                    "reader" -> readerScript?.let { script ->
                        ReaderScreen(script, preferences, model::updatePreferences) { model.navigate("editor") }
                    } ?: Loading()
                    "editor" -> draft?.let { script -> EditorScreen(script, model) } ?: Loading()
                    "settings" -> SettingsScreen(model, access, billing, activity)
                    else -> LibraryScreen(model)
                }
            }
            if (error != null) AlertDialog(onDismissRequest = { model.message.value = null },
                text = { Text(stringResource(error!!)) }, confirmButton = {
                    TextButton(onClick = { model.message.value = null }) { Text(stringResource(R.string.done)) }
                })
            if (imported != null) AlertDialog(onDismissRequest = { model.importResult.value = null },
                text = { Text(stringResource(R.string.import_result, imported!!.first, imported!!.second)) },
                confirmButton = { TextButton(onClick = { model.importResult.value = null }) { Text(stringResource(R.string.done)) } })
        }
    }
}

@Composable private fun Loading() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable private fun BillingActions(billing: BillingUi, buy: () -> Unit, restore: () -> Unit, retry: () -> Unit) {
    Text(stringResource(R.string.lifetime), style = MaterialTheme.typography.titleLarge)
    billing.price?.let { Text(it, fontSize = 40.sp, fontWeight = FontWeight.Bold, color = Mint) }
    Text(stringResource(R.string.single_payment))
    Button(onClick = buy, enabled = billing.price != null && !billing.busy && !billing.pending,
        modifier = Modifier.testTag("buy_lifetime")) { Text(stringResource(R.string.buy_lifetime)) }
    TextButton(onClick = restore, enabled = !billing.busy) { Text(stringResource(R.string.restore)) }
    if (billing.price == null) TextButton(onClick = retry) { Text(stringResource(R.string.retry)) }
    billing.message?.let { Text(stringResource(it), color = Mint) }
}

@Composable private fun AccessScreen(access: AccessUi, billing: BillingUi,
    start: () -> Unit, buy: () -> Unit, restore: () -> Unit, retry: () -> Unit) {
    Column(Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Spacer(Modifier.height(32.dp))
        Text("Teleprompt", fontSize = 32.sp, fontWeight = FontWeight.Bold)
        if (access.error != null) {
            Text(stringResource(access.error)); Button(onClick = retry) { Text(stringResource(R.string.retry)) }
            TextButton(onClick = restore, enabled = !billing.busy) { Text(stringResource(R.string.restore)) }
            billing.message?.let { Text(stringResource(it)) }
        } else {
            Text(stringResource(if (access.state == AccessState.EXPIRED) R.string.trial_expired else R.string.trial_title),
                style = MaterialTheme.typography.headlineMedium)
            Text(stringResource(R.string.trial_body))
            BillingActions(billing, buy, restore, retry)
            HorizontalDivider()
            Text(stringResource(R.string.trial_terms))
            if (access.state == AccessState.NOT_STARTED) Button(onClick = start,
                modifier = Modifier.testTag("start_trial")) { Text(stringResource(R.string.trial_start)) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun LibraryScreen(model: AppViewModel) {
    val scripts by model.scripts.collectAsStateWithLifecycle()
    val busy by model.busy.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    var newest by rememberSaveable { mutableStateOf(true) }
    var deleting by remember { mutableStateOf<Script?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments(), model::import)
    val filtered = remember(scripts, query, newest) {
        scripts.filter { it.title.contains(query, true) || it.text.contains(query, true) }.let { list ->
            if (newest) list.sortedByDescending { it.updatedAt } else list.sortedBy { it.title.lowercase() }
        }
    }
    Scaffold(topBar = { TopAppBar(title = { Text("Teleprompt") }, actions = {
        TextButton(onClick = { model.navigate("settings") }) { Text(stringResource(R.string.settings)) }
    }) }) { insets ->
        Column(Modifier.padding(insets).padding(horizontal = 16.dp)) {
            OutlinedTextField(query, { query = it }, label = { Text(stringResource(R.string.search)) },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = model::create, modifier = Modifier.testTag("new_script")) { Text(stringResource(R.string.new_script)) }
                TextButton(onClick = { picker.launch(DocumentImporter.mimeTypes) }, enabled = !busy) {
                    Text(stringResource(R.string.import_files))
                }
            }
            TextButton(onClick = { newest = !newest }) {
                Text(stringResource(if (newest) R.string.sort_date else R.string.sort_title))
            }
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxSize()) {
                if (filtered.isEmpty()) item {
                    Text(stringResource(if (scripts.isEmpty()) R.string.empty_library else R.string.empty_search), Modifier.padding(16.dp))
                }
                items(filtered, key = { it.id }) { script ->
                    Card(Modifier.fillMaxWidth().clickable { model.open(script) }) {
                        Column(Modifier.padding(16.dp)) {
                            Text(script.title, style = MaterialTheme.typography.titleMedium)
                            Text(script.text, maxLines = 2, overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.bodySmall)
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                                TextButton(onClick = { deleting = script }) { Text(stringResource(R.string.delete)) }
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(24.dp)) }
            }
        }
    }
    deleting?.let { script -> AlertDialog(onDismissRequest = { deleting = null },
        text = { Text(stringResource(R.string.delete_question)) },
        confirmButton = { TextButton(onClick = { model.delete(script); deleting = null }) { Text(stringResource(R.string.delete)) } },
        dismissButton = { TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.cancel)) } }) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun EditorScreen(script: Script, model: AppViewModel) {
    BackHandler { model.saveAndNavigate("library") }
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.title)) }, navigationIcon = {
        TextButton(onClick = { model.saveAndNavigate("library") }) { Text(stringResource(R.string.close)) }
    }, actions = { TextButton(onClick = { model.saveAndNavigate("reader") }, enabled = script.text.isNotBlank(),
        modifier = Modifier.testTag("open_reader")) {
        Text(stringResource(R.string.read))
    } }) }) { insets ->
        Column(Modifier.padding(insets).imePadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(script.title, { model.edit(it, script.text) }, label = { Text(stringResource(R.string.title)) },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(script.text, { model.edit(script.title, it) }, label = { Text(stringResource(R.string.script_text)) },
                modifier = Modifier.fillMaxSize().testTag("editor_text"))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun SettingsScreen(model: AppViewModel, access: AccessUi, billing: BillingUi, activity: Activity) {
    var confirm by remember { mutableStateOf(false) }
    var privacy by remember { mutableStateOf(false) }
    BackHandler { model.navigate("library") }
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.settings)) }, navigationIcon = {
        TextButton(onClick = { model.navigate("library") }) { Text(stringResource(R.string.back)) }
    }) }) { insets ->
        Column(Modifier.padding(insets).verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (access.state == AccessState.LIFETIME) Text(stringResource(R.string.lifetime), color = Mint)
            else {
                Text(stringResource(R.string.trial_days, access.days))
                BillingActions(billing, { model.app.access.billing.purchase(activity) },
                    { model.app.access.billing.refresh(true) }, { model.app.access.billing.refresh() })
            }
            HorizontalDivider()
            TextButton(onClick = { confirm = true }) { Text(stringResource(R.string.delete_local)) }
            Text(stringResource(R.string.delete_local_body), style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { privacy = true }) { Text(stringResource(R.string.privacy)) }
        }
    }
    if (confirm) AlertDialog(onDismissRequest = { confirm = false }, text = { Text(stringResource(R.string.delete_local_question)) },
        confirmButton = { TextButton(onClick = { model.clearLibrary(); confirm = false }) { Text(stringResource(R.string.delete)) } },
        dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.cancel)) } })
    if (privacy) AlertDialog(onDismissRequest = { privacy = false }, title = { Text(stringResource(R.string.privacy)) },
        text = { Text(stringResource(R.string.privacy_body)) },
        confirmButton = { TextButton(onClick = { privacy = false }) { Text(stringResource(R.string.done)) } })
}
