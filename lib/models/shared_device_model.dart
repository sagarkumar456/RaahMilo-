import 'package:cloud_firestore/cloud_firestore.dart';

class SharedDeviceModel {
  final String id;
  final String ownerId;
  final String ownerEmail;
  final String ownerName;
  final String sharedWithEmail;
  final bool isActive;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final String address;
  final DateTime updatedAt;
  final String? tripId;

  SharedDeviceModel({
    required this.id,
    required this.ownerId,
    required this.ownerEmail,
    required this.ownerName,
    required this.sharedWithEmail,
    required this.isActive,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.address,
    required this.updatedAt,
    this.tripId,
  });

  factory SharedDeviceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final loc = data['lastLocation'] as Map<String, dynamic>? ?? {};
    final ts = loc['updatedAt'] as Timestamp? ??
        (data['updatedAt'] as Timestamp? ?? Timestamp.now());

    final email = data['ownerEmail'] as String? ?? 'Family Member';
    final rawName = data['ownerName'] as String? ?? '';
    String name = rawName.trim();
    if (name.isEmpty || name.toLowerCase() == 'user' || name.toLowerCase() == 'guest_owner') {
      final prefix = email.split('@').first;
      name = prefix
          .replaceAll(RegExp(r'[._-]'), ' ')
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => s[0].toUpperCase() + s.substring(1))
          .join(' ');
    }

    return SharedDeviceModel(
      id: doc.id,
      ownerId: data['ownerId'] as String? ?? '',
      ownerEmail: email,
      ownerName: name.isNotEmpty ? name : 'User A',
      sharedWithEmail: data['sharedWithEmail'] as String? ?? '',
      isActive: data['active'] as bool? ?? true,
      latitude: (loc['lat'] as num?)?.toDouble() ?? 28.6139,
      longitude: (loc['lng'] as num?)?.toDouble() ?? 77.2090,
      speedKmh: ((loc['speed'] as num?)?.toDouble() ?? 0.0) * 3.6,
      address: (loc['address'] as String?)?.isNotEmpty == true
          ? loc['address'] as String
          : 'Live Location Active',
      updatedAt: ts.toDate(),
      tripId: data['tripId'] as String?,
    );
  }
}
