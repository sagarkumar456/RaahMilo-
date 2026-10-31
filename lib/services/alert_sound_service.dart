import 'package:flutter/services.dart';

/// Centralized service to play audible alert chimes and physical vibrations
/// across Android and fallback platforms.
class AlertSoundService {
  static const MethodChannel _channel = MethodChannel('com.trackmyphone.gps/alert_sound');

  /// Plays the phone's native loud notification chime and dual-pulse vibration
  static Future<void> playAlertSound({String type = 'notification'}) async {
    try {
      await _channel.invokeMethod('playAlertSound', {'type': type});
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }
}

