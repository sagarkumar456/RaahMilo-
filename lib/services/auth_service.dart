import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal();

  @override
  void notifyListeners() {
    final binding = WidgetsBinding.instance;
    final phase = binding.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      super.notifyListeners();
    } else {
      binding.addPostFrameCallback((_) {
        super.notifyListeners();
      });
    }
  }

  User? get currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  // Fallback credentials if network request times out or is offline
  bool _isDemoLoggedIn = false;
  String _customEmail = '';
  String _customName = '';
  bool get isDemoLoggedIn => _isDemoLoggedIn;

  String get displayName {
    if (currentUser?.displayName != null && currentUser!.displayName!.isNotEmpty) {
      return currentUser!.displayName!;
    }
    if (_customName.isNotEmpty) return _customName;
    return 'User';
  }

  String get email {
    if (currentUser?.email != null && currentUser!.email!.isNotEmpty) {
      return currentUser!.email!;
    }
    if (_customEmail.isNotEmpty) return _customEmail;
    return 'user@example.com';
  }

  String get uid {
    if (currentUser != null) {
      return currentUser!.uid;
    }
    if (_customEmail.isNotEmpty) {
      final safeEmail = _customEmail.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      return 'usr_$safeEmail';
    }
    return _isDemoLoggedIn ? 'demo_usr_8f3a9d2e1c' : '';
  }

  bool get isAuthenticated => currentUser != null || _isDemoLoggedIn;

  void loginAsDemo({String? email, String? name}) {
    _isDemoLoggedIn = true;
    if (email != null && email.isNotEmpty) _customEmail = email;
    if (name != null && name.isNotEmpty) _customName = name;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final cleanEmail = email.trim();
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw FirebaseAuthException(
                code: 'network-request-failed',
                message: 'Connection timed out. Switched to offline mode.',
              );
            },
          );
      _isDemoLoggedIn = false;
      _customEmail = '';
      _customName = '';
      notifyListeners();
    } catch (e) {
      // If network fails, timeout, or credentials unconfigured, allow offline login with the entered email
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('network-request-failed') ||
          errStr.contains('timed out') ||
          errStr.contains('no-app') ||
          errStr.contains('api-key-not-valid') ||
          errStr.contains('configuration_not_found')) {
        _isDemoLoggedIn = true;
        _customEmail = cleanEmail;
        final prefix = cleanEmail.split('@').first;
        _customName = prefix.isNotEmpty
            ? '${prefix[0].toUpperCase()}${prefix.substring(1)}'
            : 'User';
        notifyListeners();
        return;
      }
      rethrow;
    }
  }

  Future<void> signUp(String name, String email, String password) async {
    final cleanEmail = email.trim();
    final cleanName = name.trim();
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      if (cleanName.isNotEmpty) {
        await credential.user?.updateDisplayName(cleanName);
      }
      _isDemoLoggedIn = false;
      _customEmail = '';
      _customName = '';
      notifyListeners();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('no-app') ||
          errStr.contains('network-request-failed') ||
          errStr.contains('timed out') ||
          errStr.contains('api-key-not-valid') ||
          errStr.contains('configuration_not_found')) {
        _isDemoLoggedIn = true;
        _customEmail = cleanEmail;
        _customName = cleanName.isNotEmpty ? cleanName : cleanEmail.split('@').first;
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
    _customEmail = '';
    _customName = '';
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final user = currentUser;
    final userUid = uid;

    try {
      if (userUid.isNotEmpty && !userUid.startsWith('demo_')) {
        // Delete user document
        await FirebaseFirestore.instance.collection('users').doc(userUid).delete();

        // Delete user trips
        final trips = await FirebaseFirestore.instance
            .collection('trips')
            .where('ownerId', isEqualTo: userUid)
            .get();
        for (final doc in trips.docs) {
          await doc.reference.delete();
        }

        // Delete user device shares
        final shares = await FirebaseFirestore.instance
            .collection('device_shares')
            .where('ownerId', isEqualTo: userUid)
            .get();
        for (final doc in shares.docs) {
          await doc.reference.delete();
        }
      }

      // Delete Firebase Auth user
      if (user != null) {
        await user.delete();
      }
    } catch (_) {
      // If online delete fails, sign out cleanly
    }

    await signOut();
  }
}

final authService = AuthService();
