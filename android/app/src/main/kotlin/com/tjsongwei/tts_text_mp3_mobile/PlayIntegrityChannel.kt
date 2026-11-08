package com.tjsongwei.tts_text_mp3_mobile

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class PlayIntegrityChannel(context: Context, messenger: BinaryMessenger) {
    private val manager by lazy { IntegrityManagerFactory.createStandard(context) }
    private var provider: Task<StandardIntegrityManager.StandardIntegrityTokenProvider>? = null

    init {
        MethodChannel(messenger, "tts_text_mp3/play_integrity").setMethodCallHandler { call, result ->
            if (call.method != "requestToken") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val project = call.argument<String>("cloudProjectNumber")?.toLongOrNull()
            val hash = call.argument<String>("requestHash")
            if (project == null || project <= 0 || hash == null || !hash.matches(Regex("[a-f0-9]{64}"))) {
                result.error("integrity_configuration", "Invalid integrity request.", null)
                return@setMethodCallHandler
            }
            requestToken(project, hash, result, retryInvalidProvider = true)
        }
    }

    private fun requestToken(
        project: Long,
        hash: String,
        result: MethodChannel.Result,
        retryInvalidProvider: Boolean
    ) {
        val preparation = provider ?: manager.prepareIntegrityToken(
            StandardIntegrityManager.PrepareIntegrityTokenRequest.builder()
                .setCloudProjectNumber(project)
                .build()
        ).also { provider = it }

        preparation.onSuccessTask { tokenProvider ->
            tokenProvider.request(
                StandardIntegrityManager.StandardIntegrityTokenRequest.builder()
                    .setRequestHash(hash)
                    .build()
            )
        }.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                result.success(task.result.token())
                return@addOnCompleteListener
            }
            val invalidProvider = (task.exception as? StandardIntegrityException)?.errorCode ==
                StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID
            if ((!preparation.isSuccessful || invalidProvider) && provider === preparation) {
                provider = null
            }
            if (invalidProvider && retryInvalidProvider) {
                requestToken(project, hash, result, retryInvalidProvider = false)
            } else {
                result.error("integrity_unavailable", "Could not obtain a Play Integrity token.", null)
            }
        }
    }
}
