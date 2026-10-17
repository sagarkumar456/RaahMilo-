// File generated for TrackMyPhone project: sagar-portfolio-d89f9.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC0GL-bovcD_m-qC-sWLfR60I4luSc1qlk',
    appId: '1:848087329356:web:125c2bb42a38db0d07e2e9',
    messagingSenderId: '848087329356',
    projectId: 'sagar-portfolio-d89f9',
    authDomain: 'sagar-portfolio-d89f9.firebaseapp.com',
    storageBucket: 'sagar-portfolio-d89f9.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC0GL-bovcD_m-qC-sWLfR60I4luSc1qlk',
    appId: '1:848087329356:android:a0b5eab7b1e4106d07e2e9',
    messagingSenderId: '848087329356',
    projectId: 'sagar-portfolio-d89f9',
    storageBucket: 'sagar-portfolio-d89f9.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC0GL-bovcD_m-qC-sWLfR60I4luSc1qlk',
    appId: '1:848087329356:ios:5e0a552acb58871907e2e9',
    messagingSenderId: '848087329356',
    projectId: 'sagar-portfolio-d89f9',
    storageBucket: 'sagar-portfolio-d89f9.firebasestorage.app',
    iosBundleId: 'com.trackmyphone.gps',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyC0GL-bovcD_m-qC-sWLfR60I4luSc1qlk',
    appId: '1:848087329356:ios:5e0a552acb58871907e2e9',
    messagingSenderId: '848087329356',
    projectId: 'sagar-portfolio-d89f9',
    storageBucket: 'sagar-portfolio-d89f9.firebasestorage.app',
    iosBundleId: 'com.trackmyphone.gps',
  );
}
