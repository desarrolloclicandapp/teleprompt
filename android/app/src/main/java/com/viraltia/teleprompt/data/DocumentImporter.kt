package com.viraltia.teleprompt.data

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.zip.ZipInputStream

data class ImportedDocument(val title: String, val text: String)

object DocumentImporter {
    const val MAX_BYTES = 10 * 1024 * 1024
    const val MAX_XML_BYTES = 20 * 1024 * 1024
    val mimeTypes = arrayOf("text/plain", "text/markdown", "text/x-markdown",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document")

    fun read(resolver: ContentResolver, uri: Uri): ImportedDocument {
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment ?: "Document"
        val extension = name.substringAfterLast('.', "").lowercase()
        val mime = resolver.getType(uri)
        val bytes = resolver.openInputStream(uri)?.use { limited(it, MAX_BYTES) }
            ?: throw IllegalArgumentException("Document unavailable")
        val text = when {
            extension == "docx" || mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> docx(bytes)
            extension in setOf("txt", "md", "markdown") || mime?.startsWith("text/") == true -> decode(bytes)
            else -> throw IllegalArgumentException("Unsupported document type")
        }.trim().removePrefix("\uFEFF")
        require(text.isNotBlank()) { "Empty document" }
        return ImportedDocument(name.substringBeforeLast('.', name), text)
    }

    internal fun decode(bytes: ByteArray): String = Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF")

    internal fun limited(input: InputStream, maximum: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= maximum) { "Document too large" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    internal fun docx(bytes: ByteArray): String {
        val xml = ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            var entries = 0
            var expanded = 0
            while (true) {
                val entry = zip.nextEntry ?: break
                require(++entries <= 2048) { "Too many entries" }
                if (!entry.isDirectory && entry.name == "word/document.xml") return@use limited(zip, MAX_XML_BYTES - expanded)
                // Bound skipped expanded entries as well, preventing zip bombs before document.xml.
                expanded += limited(zip, MAX_XML_BYTES - expanded).size
            }
            throw IllegalArgumentException("Not a DOCX document")
        }
        require(!decode(xml).contains("<!DOCTYPE", ignoreCase = true))
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
        parser.setInput(ByteArrayInputStream(xml), null)
        val result = StringBuilder()
        var insideText = false
        val wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            if (event == XmlPullParser.START_TAG && parser.namespace == wordNamespace) {
                when (parser.name) {
                    "t" -> insideText = true
                    "tab" -> result.append('\t')
                    "br", "cr" -> result.append('\n')
                }
            } else if (event == XmlPullParser.TEXT && insideText) result.append(parser.text)
            else if (event == XmlPullParser.END_TAG && parser.namespace == wordNamespace) {
                when (parser.name) { "t" -> insideText = false; "p" -> result.append('\n') }
            }
            event = parser.next()
        }
        return result.toString()
    }
}
