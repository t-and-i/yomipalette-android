package com.tjsongwei.tts_text_mp3_mobile

import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SafeDocumentWriterTest {
    private class MemoryFiles : SafeDocumentWriter.FileOperations {
        data class Item(var name: String, var bytes: ByteArray)
        val items = mutableMapOf<String, Item>()
        private var nextId = 0
        var failWrite = false
        var failBackupRename = false
        var failPromotion = false

        fun seed(name: String, bytes: ByteArray) {
            items["existing"] = Item(name, bytes)
        }

        override fun find(name: String): String? =
            items.entries.firstOrNull { it.value.name == name }?.key

        override fun create(name: String, mimeType: String): String {
            val id = "created-${++nextId}"
            items[id] = Item(name, byteArrayOf())
            return id
        }

        override fun write(id: String, bytes: ByteArray) {
            if (failWrite) throw IOException("simulated disk full")
            items.getValue(id).bytes = bytes
        }

        override fun rename(id: String, name: String): String {
            val oldName = items.getValue(id).name
            if (failBackupRename && name.startsWith(".yomipalette-backup-")) {
                throw IOException("backup rename not supported")
            }
            if (failPromotion && oldName.startsWith(".yomipalette-pending-") &&
                name == "chapter.mp3") {
                throw IOException("promotion failed")
            }
            items.getValue(id).name = name
            return id
        }

        override fun delete(id: String) { items.remove(id) }
    }

    @Test
    fun newFileIsPublishedOnlyAfterSuccessfulWrite() {
        val files = MemoryFiles()
        val data = byteArrayOf(1, 2, 3)
        val result = SafeDocumentWriter(files).write("chapter.mp3", "audio/mpeg", data)
        assertEquals("chapter.mp3", files.items.getValue(result).name)
        assertArrayEquals(data, files.items.getValue(result).bytes)
        assertEquals(1, files.items.size)
    }

    @Test
    fun successfulReplaceRemovesBackupAfterPromotion() {
        val files = MemoryFiles()
        files.seed("chapter.mp3", byteArrayOf(1))
        SafeDocumentWriter(files).write("chapter.mp3", "audio/mpeg", byteArrayOf(2))
        assertEquals(1, files.items.size)
        assertArrayEquals(byteArrayOf(2), files.items.getValue(files.find("chapter.mp3")!!).bytes)
    }

    @Test
    fun failedWritePreservesExistingFile() {
        val files = MemoryFiles()
        files.seed("chapter.mp3", byteArrayOf(7))
        files.failWrite = true
        val failed = runCatching {
            SafeDocumentWriter(files).write("chapter.mp3", "audio/mpeg", byteArrayOf(8))
        }
        assertTrue(failed.isFailure)
        assertArrayEquals(byteArrayOf(7), files.items.getValue("existing").bytes)
        assertEquals("chapter.mp3", files.items.getValue("existing").name)
        assertEquals(1, files.items.size)
    }

    @Test
    fun failedBackupRenameDoesNotDeleteOriginal() {
        val files = MemoryFiles()
        files.seed("chapter.mp3", byteArrayOf(7))
        files.failBackupRename = true
        val failed = runCatching {
            SafeDocumentWriter(files).write("chapter.mp3", "audio/mpeg", byteArrayOf(8))
        }
        assertTrue(failed.isFailure)
        assertEquals(1, files.items.size)
        assertArrayEquals(byteArrayOf(7), files.items.getValue("existing").bytes)
    }

    @Test
    fun failedPromotionRestoresOriginalAndCleansStaging() {
        val files = MemoryFiles()
        files.seed("chapter.mp3", byteArrayOf(7))
        files.failPromotion = true
        val failed = runCatching {
            SafeDocumentWriter(files).write("chapter.mp3", "audio/mpeg", byteArrayOf(8))
        }
        assertTrue(failed.isFailure)
        assertEquals("chapter.mp3", files.items.getValue("existing").name)
        assertArrayEquals(byteArrayOf(7), files.items.getValue("existing").bytes)
        assertEquals(1, files.items.size)
    }
}
