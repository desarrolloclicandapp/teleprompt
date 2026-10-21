package com.viraltia.teleprompt

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.viraltia.teleprompt.data.AccessRecord
import com.viraltia.teleprompt.data.AccessStore
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AccessStoreTest {
    @Test fun accessRecordSurvivesRecreationAndIsNotStoredAsPlainText() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-access-${UUID.randomUUID()}"
        val store = AccessStore(context, name)
        assertEquals(AccessRecord(), store.load())
        val expected = AccessRecord(123456789, 123456999, "signed-receipt-marker", "signature-marker")
        store.save(expected)
        assertEquals(expected, AccessStore(context, name).load())
        assertFalse(File(context.noBackupFilesDir, name).readBytes().toString(Charsets.ISO_8859_1)
            .contains("signed-receipt-marker"))
    }

    @Test fun corruptedTrialIsNotSilentlyReplacedByANewTrial() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-access-${UUID.randomUUID()}"
        val store = AccessStore(context, name)
        store.save(AccessRecord(123456789, 123456999))
        File(context.noBackupFilesDir, name).writeBytes(byteArrayOf(1, 2, 3))
        var failed = false
        try { store.load() } catch (_: Exception) { failed = true }
        assertTrue(failed)
    }
}
