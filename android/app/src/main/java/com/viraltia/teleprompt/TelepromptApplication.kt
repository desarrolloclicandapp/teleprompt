package com.viraltia.teleprompt

import android.app.Application
import androidx.room.Room
import com.viraltia.teleprompt.data.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class TelepromptApplication : Application() {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val database by lazy { Room.databaseBuilder(this, ScriptDatabase::class.java, "scripts.db").build() }
    val preferences by lazy { ReaderPreferencesStore(this) }
    val access by lazy { AccessController(this, scope) }
}
