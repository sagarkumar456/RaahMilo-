import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal();

  User? get currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  // Mock demo profile fallback if running in offline/demo mode
  bool _isDemoLoggedIn = false;
  bool get isDemoLoggedIn => _isDemoLoggedIn;

  String get displayName {
    if (currentUser?.displayName != null && currentUser!.displayName!.isNotEmpty) {
      return currentUser!.displayName!;
    }
    return _isDemoLoggedIn ? 'Rohit Sharma' : 'User';
  }

  String get email {
    if (currentUser?.email != null && currentUser!.email!.isNotEmpty) {
      return currentUser!.email!;
    }
    return _isDemoLoggedIn ? 'rohit@example.com' : 'user@example.com';
  }

  String get uid {
    if (currentUser != null) {
      return currentUser!.uid;
    }
    return 'demo_usr_8f3a9d2e1c';
  }

  bool get isAuthenticated => currentUser != null || _isDemoLoggedIn;

  Future<void> signIn(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _isDemoLoggedIn = false;
      notifyListeners();
    } catch (e) {
      // If Firebase project credentials are unconfigured or offline, allow demo sign in
      if (e.toString().contains('no-app') ||
          e.toString().contains('network-request-failed') ||
          e.toString().contains('api-key-not-valid') ||
          e.toString().contains('CONFIGURATION_NOT_FOUND')) {
        _isDemoLoggedIn = true;
        notifyListeners();
        return;
      }
      rethrow;
    }
  }

  Future<void> signUp(String name, String email, String password) async {
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (name.trim().isNotEmpty) {
        await credential.user?.updateDisplayName(name.trim());
      }
      _isDemoLoggedIn = false;
      notifyListeners();
    } catch (e) {
      if (e.toString().contains('no-app') ||
          e.toString().contains('network-request-failed') ||
          e.toString().contains('api-key-not-valid') ||
          e.toString().contains('CONFIGURATION_NOT_FOUND')) {
        _isDemoLoggedIn = true;
        notifyListeners();
        return;
      }
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      if (e.toString().contains('no-app') ||
          e.toString().contains('network-request-failed') ||
          e.toString().contains('api-key-not-valid')) {
        return; // Safe demo ignore
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    _isDemoLoggedIn = false;
    notifyListeners();
  }

  void loginAsDemo() {
    _isDemoLoggedIn = true;
    notifyListeners();
  }
}

final authService = AuthService();
