package com.viraltia.teleprompt.ui

import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.viraltia.teleprompt.R
import com.viraltia.teleprompt.TelepromptApplication
import com.viraltia.teleprompt.data.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class AppViewModel(val app: TelepromptApplication, private val saved: SavedStateHandle) : ViewModel() {
    private val dao = app.database.scripts()
    val scripts = dao.observe().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    private val mutablePreferences = MutableStateFlow(ReaderPreferences())
    val preferences = mutablePreferences.asStateFlow()
    val route = saved.getStateFlow("route", "library")
    private val draftMutable = MutableStateFlow<Script?>(null)
    val draft = draftMutable.asStateFlow()
    val readerScript = MutableStateFlow<Script?>(null)
    val message = MutableStateFlow<Int?>(null)
    val importResult = MutableStateFlow<Pair<Int, Int>?>(null)
    val busy = MutableStateFlow(false)
    private val writes = Mutex()
    private var preferenceWrite: Job? = null
    private var draftWrite: Job? = null

    init {
        viewModelScope.launch {
            try {
                app.preferences.initializeLibrary(dao, app.getString(R.string.welcome_title), app.getString(R.string.welcome_text))
                saved.get<String>("scriptId")?.let { id ->
                    val script = dao.find(id)
                    draftMutable.value = script
                    if (route.value == "reader") readerScript.value = script
                    if (script == null) navigate("library")
                }
            } catch (_: Exception) { message.value = R.string.storage_error }
        }
        viewModelScope.launch {
            try { app.preferences.preferences.collect { mutablePreferences.value = it } }
            catch (_: Exception) { message.value = R.string.storage_error }
        }
    }

    fun navigate(value: String) { saved["route"] = value }

    fun open(script: Script) {
        draftMutable.value = script; saved["scriptId"] = script.id; navigate("editor")
    }

    fun create() {
        viewModelScope.launch { try {
            val script = Script(title = app.getString(R.string.new_script), text = "")
            dao.save(script); open(script)
        } catch (_: Exception) { message.value = R.string.storage_error } }
    }

    fun edit(title: String, text: String) {
        draftMutable.value = draftMutable.value?.copy(title = title, text = text, updatedAt = System.currentTimeMillis())
        draftWrite?.cancel()
        draftWrite = viewModelScope.launch { delay(300); saveDraft() }
    }

    private suspend fun saveDraft(): Boolean {
        val current = draftMutable.value ?: return false
        return try { writes.withLock { dao.save(current) }; true }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { message.value = R.string.storage_error; false }
    }

    fun saveAndNavigate(to: String) {
        draftWrite?.cancel()
        viewModelScope.launch {
            if (saveDraft()) {
                if (to == "reader") readerScript.value = draftMutable.value
                navigate(to)
            }
        }
    }

    fun flushDraft() {
        if (route.value == "editor") {
            draftWrite?.cancel()
            app.scope.launch { saveDraft() }
        }
    }

    fun delete(script: Script) { viewModelScope.launch {
        try { writes.withLock { dao.delete(script.id) } }
        catch (_: Exception) { message.value = R.string.storage_error }
    } }

    fun clearLibrary() { viewModelScope.launch {
        try { writes.withLock { dao.clear() } }
        catch (_: Exception) { message.value = R.string.storage_error }
    } }

    fun updatePreferences(value: ReaderPreferences) {
        mutablePreferences.value = value
        preferenceWrite?.cancel()
        preferenceWrite = viewModelScope.launch {
            delay(150)
            try { app.preferences.save(value) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { message.value = R.string.storage_error }
        }
    }

    fun import(uris: List<Uri>) {
        if (busy.value) return
        viewModelScope.launch {
            busy.value = true
            var imported = 0; var skipped = 0
            try {
                for (uri in uris) {
                    try {
                        val document = withContext(Dispatchers.IO) { DocumentImporter.read(app.contentResolver, uri) }
                        writes.withLock {
                            val existing = dao.matchingImport(document.title, document.text)
                            dao.save(existing?.copy(updatedAt = System.currentTimeMillis()) ?:
                                Script(title = document.title, text = document.text))
                        }
                        imported++
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (_: Exception) { skipped++ }
                }
                importResult.value = imported to skipped
            } finally { busy.value = false }
        }
    }
}
