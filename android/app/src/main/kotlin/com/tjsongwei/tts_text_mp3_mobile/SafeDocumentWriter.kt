package com.tjsongwei.tts_text_mp3_mobile

import java.io.IOException
import java.util.UUID

/**
 * SAF providers do not guarantee atomic replacement. Stage the complete new
 * file first. Never delete the original before it has been safely replaced.
 * The provider must support rename; otherwise fail while leaving the old file.
 */
internal class SafeDocumentWriter(private val files: FileOperations) {
    internal interface FileOperations {
        fun find(name: String): String?
        fun create(name: String, mimeType: String): String
        fun write(id: String, bytes: ByteArray)
        fun rename(id: String, name: String): String
        fun delete(id: String)
    }

    fun write(name: String, mimeType: String, bytes: ByteArray): String {
        val nonce = UUID.randomUUID().toString()
        val pendingName = ".yomipalette-pending-$nonce.mp3"
        val backupName = ".yomipalette-backup-$nonce.mp3"

        // If staging or writing fails, no change is made to the old document.
        val pending = files.create(pendingName, mimeType)
        try {
            files.write(pending, bytes)
        } catch (error: Exception) {
            runCatching { files.delete(pending) }
            throw error
        }

        val existing = try {
            files.find(name)
        } catch (error: Exception) {
            runCatching { files.delete(pending) }
            throw error
        }

        if (existing == null) {
            try {
                return files.rename(pending, name)
            } catch (error: Exception) {
                runCatching { files.delete(pending) }
                throw IOException("The document provider cannot finalize the new file.", error)
            }
        }

        val backup = try {
            files.rename(existing, backupName)
        } catch (error: Exception) {
            runCatching { files.delete(pending) }
            throw IOException("Cannot safely replace the existing file; it was not deleted.", error)
        }

        try {
            val result = files.rename(pending, name)
            // If backup cleanup fails, the newly written file still exists and
            // the previous data remains recoverable under the backup name.
            runCatching { files.delete(backup) }
            return result
        } catch (error: Exception) {
            val rollback = runCatching { files.rename(backup, name) }
            runCatching { files.delete(pending) }
            if (rollback.isFailure) {
                throw IOException(
                    "Could not finish replacement or restore the original name. " +
                        "The previous file is preserved as $backupName.",
                    error
                )
            }
            throw IOException("The original document was restored after the replacement failed.", error)
        }
    }
}
