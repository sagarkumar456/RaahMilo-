import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'trip_model.dart';

class StoppageModel {
  final int stopNumber;
  final double latitude;
  final double longitude;
  final DateTime arrivedAt;
  final DateTime departedAt;
  final Duration duration;
  final String? address;
  final bool isEndStop;
  final bool isStart;

  StoppageModel({
    required this.stopNumber,
    required this.latitude,
    required this.longitude,
    required this.arrivedAt,
    required this.departedAt,
    required this.duration,
    this.address,
    this.isEndStop = false,
    this.isStart = false,
  });

  ll.LatLng get latLng => ll.LatLng(latitude, longitude);

  String get formattedDuration {
    if (isEndStop || isStart) return '';
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (mins >= 60) {
      return '${mins ~/ 60}h ${mins % 60}m';
    } else if (mins > 0) {
      return '$mins min${mins > 1 ? "s" : ""}';
    } else {
      return '$secs sec';
    }
  }

  String get formattedTime {
    final format = DateFormat('hh:mm a');
    if (isStart) {
      return 'Started at ${format.format(arrivedAt)}';
    }
    if (isEndStop) {
      return 'Stopped at ${format.format(arrivedAt)}';
    }
    return '${format.format(arrivedAt)} - ${format.format(departedAt)}';
  }

  String get title {
    if (isStart) return 'Start Point';
    if (isEndStop) return 'End Stoppage';
    return 'Stop #$stopNumber';
  }

  Map<String, dynamic> toJson() => {
    'stopNumber': stopNumber,
    'latitude': latitude,
    'longitude': longitude,
    'arrivedAt': arrivedAt.toIso8601String(),
    'departedAt': departedAt.toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'address': address,
    'isEndStop': isEndStop,
    'isStart': isStart,
  };

  factory StoppageModel.fromJson(Map<String, dynamic> json) => StoppageModel(
    stopNumber: json['stopNumber'] as int? ?? 1,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    arrivedAt: DateTime.parse(json['arrivedAt'] as String),
    departedAt: DateTime.parse(json['departedAt'] as String),
    duration: Duration(seconds: json['durationSeconds'] as int? ?? 0),
    address: json['address'] as String?,
    isEndStop: json['isEndStop'] as bool? ?? false,
    isStart: json['isStart'] as bool? ?? false,
  );
}

/// Robust Stoppage Detection Algorithm:
/// Analyzes a trip's GPS points to detect intermediate halts and the final end stoppage.
List<StoppageModel> extractStoppages(
  List<TripPoint> points, {
  Duration minDuration = const Duration(seconds: 30),
  double distanceThresholdMeters = 28.0,
}) {
  if (points.length < 2) return [];

  final List<StoppageModel> stoppages = [];
  int stopCounter = 1;

  // 1. Detect Intermediate Stoppages
  List<TripPoint> currentHalt = [];

  for (int i = 0; i < points.length; i++) {
    final pt = points[i];

    if (currentHalt.isEmpty) {
      currentHalt.add(pt);
      continue;
    }

    final anchor = currentHalt.first;
    final dist = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      pt.latitude,
      pt.longitude,
    );

    // If point is close to the anchor and speed is low, it's part of the same halt
    if (dist <= distanceThresholdMeters && pt.speed < 2.0) {
      currentHalt.add(pt);
    } else {
      // Movement detected. Check if previous stationary points formed a stoppage
      if (currentHalt.length >= 2) {
        final startHalt = currentHalt.first.timestamp;
        final endHalt = currentHalt.last.timestamp;
        final haltDuration = endHalt.difference(startHalt);

        // Don't treat the very start of the trip as an intermediate stop
        final isAtTripStart = (i - currentHalt.length) <= 1;

        if (haltDuration >= minDuration && !isAtTripStart) {
          // Calculate centroid of halt
          double sumLat = 0;
          double sumLng = 0;
          for (final p in currentHalt) {
            sumLat += p.latitude;
            sumLng += p.longitude;
          }
          final avgLat = sumLat / currentHalt.length;
          final avgLng = sumLng / currentHalt.length;

          stoppages.add(StoppageModel(
            stopNumber: stopCounter++,
            latitude: avgLat,
            longitude: avgLng,
            arrivedAt: startHalt,
            departedAt: endHalt,
            duration: haltDuration,
            isEndStop: false,
          ));
        }
      }
      currentHalt = [pt];
    }
  }

  // Check if remaining points at the very end formed an intermediate stoppage
  if (currentHalt.length >= 2) {
    final startHalt = currentHalt.first.timestamp;
    final endHalt = currentHalt.last.timestamp;
    final haltDuration = endHalt.difference(startHalt);
    if (haltDuration >= minDuration && (points.length - currentHalt.length > 2)) {
      double sumLat = 0;
      double sumLng = 0;
      for (final p in currentHalt) {
        sumLat += p.latitude;
        sumLng += p.longitude;
      }
      stoppages.add(StoppageModel(
        stopNumber: stopCounter++,
        latitude: sumLat / currentHalt.length,
        longitude: sumLng / currentHalt.length,
        arrivedAt: startHalt,
        departedAt: endHalt,
        duration: haltDuration,
        isEndStop: false,
      ));
    }
  }

  // 2. ALWAYS create the End Stoppage ("na end stopage banana hai")
  final lastPoint = points.last;
  final tripStart = points.first.timestamp;
  final totalTripDuration = lastPoint.timestamp.difference(tripStart);

  stoppages.add(StoppageModel(
    stopNumber: stopCounter,
    latitude: lastPoint.latitude,
    longitude: lastPoint.longitude,
    arrivedAt: lastPoint.timestamp,
    departedAt: lastPoint.timestamp,
    duration: totalTripDuration,
    isEndStop: true,
  ));

  return stoppages;
}
