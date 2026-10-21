import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
