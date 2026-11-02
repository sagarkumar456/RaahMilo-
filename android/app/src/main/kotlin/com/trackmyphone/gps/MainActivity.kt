package com.trackmyphone.gps

import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.trackmyphone.gps/alert_sound"
    private var activeRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceModel" -> {
                    try {
                        val manufacturer = Build.MANUFACTURER.replaceFirstChar {
                            if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString()
                        }
                        val model = Build.MODEL
                        val deviceName = if (model.startsWith(manufacturer, ignoreCase = true)) {
                            model
                        } else {
                            "$manufacturer $model"
                        }
                        result.success(deviceName)
                    } catch (e: Exception) {
                        result.success("Android Device")
                    }
                }
                "getBatteryLevel" -> {
                    try {
                        val bm = getSystemService(BATTERY_SERVICE) as? BatteryManager
                        val batLevel = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                        result.success(batLevel)
                    } catch (e: Exception) {
                        result.success(-1)
                    }
                }
                "openMap" -> {
                    try {
                        val lat = call.argument<Double>("lat") ?: 0.0
                        val lng = call.argument<Double>("lng") ?: 0.0
                        val label = call.argument<String>("label") ?: "Device Location"

                        val geoUri = Uri.parse("geo:$lat,$lng?q=$lat,$lng(${Uri.encode(label)})")
                        val mapIntent = Intent(Intent.ACTION_VIEW, geoUri)
                        mapIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

                        if (mapIntent.resolveActivity(packageManager) != null) {
                            startActivity(mapIntent)
                            result.success(true)
                        } else {
                            val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng")
                            val webIntent = Intent(Intent.ACTION_VIEW, webUri)
                            webIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(webIntent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        try {
                            val lat = call.argument<Double>("lat") ?: 0.0
                            val lng = call.argument<Double>("lng") ?: 0.0
                            val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng")
                            val webIntent = Intent(Intent.ACTION_VIEW, webUri)
                            webIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(webIntent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("MAP_ERROR", e2.message, null)
                        }
                    }
                }
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
