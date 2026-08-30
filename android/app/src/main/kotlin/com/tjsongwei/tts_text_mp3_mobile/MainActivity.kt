package com.tjsongwei.tts_text_mp3_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    private val channelName = "tts_text_mp3/output_directory"
    private val selectDirectoryRequest = 42081
    private var pendingDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handleOutputDirectoryCall)
    }

    private fun handleOutputDirectoryCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selectDirectory" -> selectDirectory(result)
            "verifyDirectory" -> runStorageOperation(result) {
                val treeUri = Uri.parse(call.argument<String>("uri"))
                val probe = createOrReplaceFile(treeUri, ".tts-text-mp3-write-test", "text/plain")
                contentResolver.openOutputStream(probe, "w")!!.use {
                    it.write("write test".toByteArray())
                }
                DocumentsContract.deleteDocument(contentResolver, probe)
                null
            }
            "writeFile" -> runStorageOperation(result) {
                val treeUri = Uri.parse(call.argument<String>("uri"))
                val name = call.argument<String>("name") ?: throw IOException("Missing filename")
                val bytes = call.argument<ByteArray>("bytes") ?: throw IOException("Missing data")
                val fileUri = createOrReplaceFile(treeUri, name, "audio/mpeg")
                contentResolver.openOutputStream(fileUri, "w")!!.use { it.write(bytes) }
                fileUri.toString()
            }
            else -> result.notImplemented()
        }
    }

    private fun selectDirectory(result: MethodChannel.Result) {
        if (pendingDirectoryResult != null) {
            result.error("already_active", "A folder picker is already open.", null)
            return
        }
        pendingDirectoryResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        startActivityForResult(intent, selectDirectoryRequest)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != selectDirectoryRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingDirectoryResult
        pendingDirectoryResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }
        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val documentId = DocumentsContract.getTreeDocumentId(uri)
            val label = URLDecoder.decode(documentId, StandardCharsets.UTF_8.name())
            result?.success(mapOf("uri" to uri.toString(), "label" to label))
        } catch (error: Exception) {
            result?.error("not_writable", error.message, null)
        }
    }

    private fun createOrReplaceFile(treeUri: Uri, name: String, mimeType: String): Uri {
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )
        contentResolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == name) {
                    val existing = DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(idColumn))
                    DocumentsContract.deleteDocument(contentResolver, existing)
                    break
                }
            }
        }
        return DocumentsContract.createDocument(contentResolver, parent, mimeType, name)
            ?: throw IOException("Could not create $name")
    }

    private fun runStorageOperation(result: MethodChannel.Result, operation: () -> Any?) {
        try {
            result.success(operation())
        } catch (error: Exception) {
            result.error("not_writable", error.message, null)
        }
    }
}
