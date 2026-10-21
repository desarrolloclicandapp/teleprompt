package com.viraltia.teleprompt.data

import android.content.Context
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.map

private val Context.readerDataStore by preferencesDataStore("reader")
data class ReaderPreferences(val level: Int = 1, val fontSize: Float = 26f,
    val horizontal: Boolean = false, val vertical: Boolean = false)

class ReaderPreferencesStore(context: Context) {
    private val store = context.applicationContext.readerDataStore
    private val level = intPreferencesKey("level")
    private val font = floatPreferencesKey("font_size")
    private val horizontal = booleanPreferencesKey("mirror_horizontal")
    private val vertical = booleanPreferencesKey("mirror_vertical")
    private val seeded = booleanPreferencesKey("library_initialized")
    val preferences = store.data.map {
        ReaderPreferences((it[level] ?: 1).coerceIn(1, 30),
            (it[font] ?: 26f).let { value -> if (value.isFinite()) value.coerceIn(16f, 82f) else 26f },
            it[horizontal] ?: false, it[vertical] ?: false)
    }
    suspend fun save(value: ReaderPreferences) {
        store.edit {
            it[level] = value.level.coerceIn(1, 30)
            it[font] = value.fontSize.takeIf(Float::isFinite)?.coerceIn(16f, 82f) ?: 26f
            it[horizontal] = value.horizontal; it[vertical] = value.vertical
        }
    }
    suspend fun initializeLibrary(dao: ScriptDao, welcomeTitle: String, welcomeText: String) {
        store.updateData { current ->
            if (current[seeded] == true) current else {
                if (dao.count() == 0) dao.save(Script(title = welcomeTitle, text = welcomeText))
                current.toMutablePreferences().also { it[seeded] = true }
            }
        }
    }
}
