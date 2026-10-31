package com.trackmyphone.gps

import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.trackmyphone.gps/alert_sound"
    private var activeRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playAlertSound" -> {
                    try {
                        val alertType = call.argument<String>("type") ?: "notification"
                        
                        // 1. Play ToneGenerator Beep (Guaranteed loud sound on ALARM stream even if phone is on Vibrate/Silent)
                        try {
                            val toneGen = ToneGenerator(AudioManager.STREAM_ALARM, 100)
                            toneGen.startTone(ToneGenerator.TONE_PROP_BEEP2, 450)
                        } catch (_: Exception) {}

                        // 2. Play System Notification Ringtone without premature garbage collection
                        try {
                            activeRingtone?.stop()
                            val ringtoneType = if (alertType == "alarm") {
                                RingtoneManager.TYPE_ALARM
                            } else {
                                RingtoneManager.TYPE_NOTIFICATION
                            }
                            var alertUri = RingtoneManager.getDefaultUri(ringtoneType)
                            if (alertUri == null) {
                                alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                            }
                            val r = RingtoneManager.getRingtone(applicationContext, alertUri)
                            if (r != null) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                    r.audioAttributes = AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_ALARM)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                        .build()
                                }
                                activeRingtone = r
                                r.play()
                            }
                        } catch (_: Exception) {}

                        // 3. Trigger tactile haptic vibration (Double buzz)
                        try {
                            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                val vibratorManager = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
                                vibratorManager.defaultVibrator
                            } else {
                                @Suppress("DEPRECATION")
                                getSystemService(VIBRATOR_SERVICE) as Vibrator
                            }
                            val pattern = longArrayOf(0, 300, 150, 300)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(pattern, -1)
                            }
                        } catch (_: Exception) {}

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SOUND_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
