package com.viraltia.teleprompt.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class AccessRecord(val startedAt: Long? = null, val lastObservedAt: Long = 0,
    val receipt: String? = null, val signature: String? = null)

/** Private, atomic encrypted record. The library's reset never touches it. */
class AccessStore(context: Context, recordName: String = "access-v1") {
    private val file = AtomicFile(File(context.noBackupFilesDir, recordName))
    private val alias = "teleprompt.android.$recordName"
    private fun exists() = file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()

    private fun key(): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keys.getKey(alias, null) as? SecretKey)?.let { return it }
        // Do not silently replace a missing key when an encrypted record exists.
        check(!exists()) { "Access encryption key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    @Synchronized fun load(): AccessRecord {
        if (!exists()) return AccessRecord()
        val bytes = file.readFully()
        require(bytes.size > 13 && bytes[0].toInt() == 1)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
        val json = JSONObject(String(cipher.doFinal(bytes.copyOfRange(13, bytes.size)), Charsets.UTF_8))
        return AccessRecord(
            if (json.has("startedAt")) json.getLong("startedAt") else null,
            json.optLong("lastObservedAt"),
            if (json.has("receipt")) json.getString("receipt") else null,
            if (json.has("signature")) json.getString("signature") else null)
    }

    @Synchronized fun save(record: AccessRecord) {
        val json = JSONObject().put("lastObservedAt", record.lastObservedAt)
        record.startedAt?.let { json.put("startedAt", it) }
        record.receipt?.let { json.put("receipt", it) }
        record.signature?.let { json.put("signature", it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val bytes = byteArrayOf(1) + cipher.iv + cipher.doFinal(json.toString().toByteArray(Charsets.UTF_8))
        val output = file.startWrite()
        try { output.write(bytes); file.finishWrite(output) }
        catch (error: Exception) { file.failWrite(output); throw error }
    }

    /** Recovery is allowed only after Billing has produced a valid signed purchase.
     * An unreadable trial record alone must never create a fresh trial. */
    @Synchronized fun recoverPurchasedAccess(record: AccessRecord) {
        require(record.receipt != null && record.signature != null)
        file.delete()
        save(record)
    }
}
