package com.viraltia.teleprompt.data

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.nio.charset.CharacterCodingException

class DocumentImporterTest {
    @Test fun preservesUnicodeParagraphsAndRemovesBom() {
        val text = "\uFEFFHola, cámara 👋\n\nSegundo párrafo"
        assertEquals(text.removePrefix("\uFEFF"), DocumentImporter.decode(text.toByteArray()))
    }
    @Test(expected = CharacterCodingException::class) fun rejectsInvalidUtf8() {
        DocumentImporter.decode(byteArrayOf(0xC3.toByte(), 0x28))
    }
    @Test fun acceptsExactLimit() {
        assertArrayEquals(byteArrayOf(1, 2), DocumentImporter.limited(ByteArrayInputStream(byteArrayOf(1, 2)), 2))
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsOversizedFiles() {
        DocumentImporter.limited(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 2)
    }
}
