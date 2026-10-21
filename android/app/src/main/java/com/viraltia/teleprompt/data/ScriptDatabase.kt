package com.viraltia.teleprompt.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow
import java.util.UUID

@Entity(tableName = "scripts", indices = [Index(value = ["sourceId"], unique = true)])
data class Script(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String,
    val text: String,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val sourceId: String? = null,
    val sourcePath: String? = null,
)

@Dao
interface ScriptDao {
    @Query("SELECT * FROM scripts ORDER BY updatedAt DESC") fun observe(): Flow<List<Script>>
    @Query("SELECT * FROM scripts WHERE id = :id") suspend fun find(id: String): Script?
    @Query("SELECT * FROM scripts WHERE sourceId = :source") suspend fun bySource(source: String): Script?
    @Query("SELECT * FROM scripts WHERE title = :title AND text = :text AND sourceId IS NULL LIMIT 1")
    suspend fun matchingImport(title: String, text: String): Script?
    @Query("SELECT COUNT(*) FROM scripts") suspend fun count(): Int
    @Upsert suspend fun save(script: Script)
    @Query("DELETE FROM scripts WHERE id = :id") suspend fun delete(id: String)
    @Query("DELETE FROM scripts") suspend fun clear()
}

@Database(entities = [Script::class], version = 1, exportSchema = true)
abstract class ScriptDatabase : RoomDatabase() { abstract fun scripts(): ScriptDao }
