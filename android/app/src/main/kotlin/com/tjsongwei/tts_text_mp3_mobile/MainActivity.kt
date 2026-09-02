package com.tjsongwei.tts_text_mp3_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "tts_text_mp3/output_directory"
    private val deviceTtsChannelName = "tts_text_mp3/device_tts"
    private val selectDirectoryRequest = 42081
    private var pendingDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handleOutputDirectoryCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceTtsChannelName)
            .setMethodCallHandler(::handleDeviceTtsCall)
    }

    private fun handleDeviceTtsCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listEngines" -> {
                val probe = TextToSpeech(this, null)
                try {
                    val defaultEngine = probe.defaultEngine
                    result.success(probe.engines.map {
                        mapOf(
                            "name" to it.name,
                            "label" to it.label,
                            "isDefault" to (it.name == defaultEngine)
                        )
                    })
                } finally {
                    probe.shutdown()
                }
            }
            "listVoices" -> {
                val engine = call.argument<String>("engine")
                if (engine.isNullOrBlank()) {
                    result.error("missing_engine", "Select a TTS engine.", null)
                    return
                }
                withTts(engine, result) { tts ->
                    val voices = tts.voices.orEmpty()
                        .sortedWith(compareBy({ it.locale.toLanguageTag() }, { it.name }))
                        .map {
                            mapOf(
                                "name" to it.name,
                                "locale" to it.locale.toLanguageTag(),
                                "networkRequired" to it.isNetworkConnectionRequired
                            )
                        }
                    result.success(voices)
                    tts.shutdown()
                }
            }
            "synthesize" -> synthesizeDeviceTts(call, result)
            else -> result.notImplemented()
        }
    }

    private fun synthesizeDeviceTts(call: MethodCall, result: MethodChannel.Result) {
        val engine = call.argument<String>("engine")
        val voiceName = call.argument<String>("voice")
        val text = call.argument<String>("text")
        if (engine.isNullOrBlank() || voiceName.isNullOrBlank() || text.isNullOrEmpty()) {
            result.error("invalid_request", "Engine, voice, and text are required.", null)
            return
        }
        withTts(engine, result) { tts ->
            val voice = tts.voices?.firstOrNull { it.name == voiceName }
            if (voice == null) {
                tts.shutdown()
                result.error("voice_unavailable", "The selected device voice is unavailable.", null)
                return@withTts
            }
            tts.voice = voice
            tts.setSpeechRate((call.argument<Double>("rate") ?: 1.0).toFloat())
            tts.setPitch((call.argument<Double>("pitch") ?: 1.0).toFloat())
            val output = File.createTempFile("device-tts-", ".wav", cacheDir)
            val utteranceId = UUID.randomUUID().toString()
            val finished = AtomicBoolean(false)
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) = Unit

                override fun onDone(id: String?) {
                    if (!finished.compareAndSet(false, true)) return
                    try {
                        result.success(output.readBytes())
                    } catch (error: Exception) {
                        result.error("read_failed", error.message, null)
                    } finally {
                        output.delete()
                        tts.shutdown()
                    }
                }

                @Deprecated("Deprecated in Android")
                override fun onError(id: String?) {
                    finishWithError("Device TTS synthesis failed.")
                }

                override fun onError(id: String?, errorCode: Int) {
                    finishWithError("Device TTS synthesis failed ($errorCode).")
                }

                private fun finishWithError(message: String) {
                    if (!finished.compareAndSet(false, true)) return
                    output.delete()
                    tts.shutdown()
                    result.error("synthesis_failed", message, null)
                }
            })
            val params = Bundle().apply {
                putFloat(
                    TextToSpeech.Engine.KEY_PARAM_VOLUME,
                    (call.argument<Double>("volume") ?: 1.0).toFloat()
                )
            }
            val queued = tts.synthesizeToFile(text, params, output, utteranceId)
            if (queued != TextToSpeech.SUCCESS && finished.compareAndSet(false, true)) {
                output.delete()
                tts.shutdown()
                result.error("queue_failed", "The device TTS request could not be queued.", null)
            }
        }
    }

    private fun withTts(
        engine: String,
        result: MethodChannel.Result,
        ready: (TextToSpeech) -> Unit
    ) {
        lateinit var tts: TextToSpeech
        tts = TextToSpeech(this, { status ->
            if (status == TextToSpeech.SUCCESS) {
                ready(tts)
            } else {
                tts.shutdown()
                result.error("initialization_failed", "The selected TTS engine could not be initialized.", null)
            }
        }, engine)
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
