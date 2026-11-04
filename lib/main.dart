import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_colors.dart';
import 'core/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Protect against unhandled widget errors turning screen blank in release mode
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('RaahMilo caught widget error: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('RaahMilo caught platform error: $error');
    return true; // Prevents crash
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const ColoredBox(
      color: Colors.transparent,
      child: SizedBox.shrink(),
    );
  };

  // Set system UI style (transparent status bar, light icons for dark navy splash)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const RaahMiloApp());
}

class RaahMiloApp extends StatelessWidget {
  const RaahMiloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RaahMilo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}

// Backward-compatibility alias
typedef TrackMyPhoneApp = RaahMiloApp;
