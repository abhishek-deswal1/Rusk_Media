package com.example.rusk_media

import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private var volumeObserver: ContentObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, VOLUME_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // a fixed-volume device has nothing to follow; null keeps the
                // app on its own volume
                "get" -> result.success(if (audio.isVolumeFixed) null else mediaLevel(audio))
                "set" -> {
                    val level = (call.arguments as? Number)?.toDouble()
                    if (level == null) {
                        result.error("bad_args", "expected a level between 0 and 1", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        // no flags: the app draws its own meter, so no system popup
                        audio.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            (level.coerceIn(0.0, 1.0) * max).roundToInt(),
                            0,
                        )
                        // the level the phone actually took, snapped to its own steps
                        result.success(mediaLevel(audio))
                    } catch (e: SecurityException) {
                        // do not disturb can refuse volume changes
                        result.error("refused", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, VOLUME_CHANGES_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopWatchingVolume()
                    var last = mediaLevel(audio)
                    // volume levels live in system settings, so the hardware keys
                    // show up here without a broadcast receiver
                    val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                        override fun onChange(selfChange: Boolean) {
                            val now = mediaLevel(audio)
                            if (now != last) {
                                last = now
                                events.success(now)
                            }
                        }
                    }
                    contentResolver.registerContentObserver(
                        Settings.System.CONTENT_URI,
                        true,
                        observer,
                    )
                    volumeObserver = observer
                }

                override fun onCancel(arguments: Any?) = stopWatchingVolume()
            },
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopWatchingVolume()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun stopWatchingVolume() {
        volumeObserver?.let { contentResolver.unregisterContentObserver(it) }
        volumeObserver = null
    }

    private fun mediaLevel(audio: AudioManager): Double {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    private companion object {
        const val VOLUME_CHANNEL = "system_volume"
        const val VOLUME_CHANGES_CHANNEL = "system_volume/changes"
    }
}
