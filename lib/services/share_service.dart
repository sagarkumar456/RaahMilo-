import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/shared_device_model.dart';
import 'geocoding_service.dart';
import 'tracking_service.dart';

class ShareService extends ChangeNotifier {
  static final ShareService _instance = ShareService._internal();
  factory ShareService() => _instance;

  ShareService._internal();

  /// Share current user's live location with another user by email
  Future<void> shareLocationWith(String recipientEmail) async {
    final cleanEmail = recipientEmail.trim().toLowerCase();
    if (cleanEmail.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'guest_owner';
    final userEmail = user?.email ?? 'user@trackmyphone.app';
    final userName = user?.displayName ?? (userEmail.split('@').first);

    final currentPos = trackingService.current;
    final lat = currentPos?.latitude ?? 28.6139;
    final lng = currentPos?.longitude ?? 77.2090;
    final speed = currentPos?.speed ?? 0.0;
    final address = geocodingService.fullAddress;

    final docId = '${uid}_to_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    try {
      await FirebaseFirestore.instance.collection('device_shares').doc(docId).set({
        'ownerId': uid,
        'ownerEmail': userEmail,
        'ownerName': userName,
        'sharedWithEmail': cleanEmail,
        'active': true,
        'tripId': trackingService.tripId ?? '',
        'lastLocation': {
          'lat': lat,
          'lng': lng,
          'speed': speed,
          'address': address,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also attach to active trip if tracking
      final tripId = trackingService.tripId;
      if (tripId != null && !tripId.startsWith('local_')) {
        await FirebaseFirestore.instance.collection('trips').doc(tripId).update({
          'viewerIds': FieldValue.arrayUnion([cleanEmail]),
        });
      }
    } catch (e) {
      debugPrint('Share to Firestore error: $e');
      rethrow;
    }
  }

  /// Called whenever device location updates, syncing position to active shares
  Future<void> updateMySharedLocations({
    required double lat,
    required double lng,
    required double speed,
    required String address,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('device_shares')
          .where('ownerId', isEqualTo: user.uid)
          .where('active', isEqualTo: true)
          .get();

      if (query.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in query.docs) {
        batch.update(doc.reference, {
          'lastLocation': {
            'lat': lat,
            'lng': lng,
            'speed': speed,
            'address': address,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error updating shared locations: $e');
    }
  }

  /// Real-time stream of all devices/users sharing their live location with the current user
  Stream<List<SharedDeviceModel>> getSharedWithMeStream() {
    final user = FirebaseAuth.instance.currentUser;
    final myEmail = user?.email?.trim().toLowerCase();

    if (myEmail == null || myEmail.isEmpty) {
      // If not logged in, return empty stream
      return Stream.value(<SharedDeviceModel>[]);
    }

    return FirebaseFirestore.instance
        .collection('device_shares')
        .where('sharedWithEmail', isEqualTo: myEmail)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => SharedDeviceModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Real-time stream for a single shared device
  Stream<SharedDeviceModel?> streamSingleShare(String shareId) {
    return FirebaseFirestore.instance
        .collection('device_shares')
        .doc(shareId)
        .snapshots()
        .map((doc) => doc.exists ? SharedDeviceModel.fromFirestore(doc) : null);
  }

  /// Revoke or delete share access
  Future<void> revokeShare(String shareId) async {
    try {
      await FirebaseFirestore.instance
          .collection('device_shares')
          .doc(shareId)
          .update({'active': false});
    } catch (e) {
      debugPrint('Error revoking share: $e');
    }
  }
}

final shareService = ShareService();
