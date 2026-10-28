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
    if (isStart) return '';
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (mins >= 60) {
      return '${mins ~/ 60}h ${mins % 60}m';
    } else if (mins > 0) {
      return '$mins min${mins > 1 ? "s" : ""}';
    } else if (isEndStop) {
      return '';
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
      return 'Arrived at ${format.format(arrivedAt)}';
    }
    return '${format.format(arrivedAt)} - ${format.format(departedAt)}';
  }

  String get title {
    if (isStart) return 'Start Point';
    if (isEndStop) return 'Trip Destination';
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
  double distanceThresholdMeters = 30.0,
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

    // If point is close to the anchor and speed is low (< 2.0 m/s = 7.2 km/h)
    if (dist <= distanceThresholdMeters && pt.speed < 2.0) {
      currentHalt.add(pt);
    } else {
      // Movement detected away from anchor.
      // Check if previous stationary points formed a stoppage.
      final startHalt = currentHalt.first.timestamp;

      // Telemetry speed check across the departure gap
      final distFromLast = Geolocator.distanceBetween(
        currentHalt.last.latitude,
        currentHalt.last.longitude,
        pt.latitude,
        pt.longitude,
      );
      final gapSeconds = pt.timestamp.difference(currentHalt.last.timestamp).inSeconds;
      final impliedSpeedMps = gapSeconds > 0 ? (distFromLast / gapSeconds) : 0.0;

      // If implied speed across the gap is high (> 8.0 m/s = ~29 km/h), vehicle was traveling
      // during a telemetry gap (e.g. tunnel), so end halt at currentHalt.last.
      // Otherwise, the vehicle was stationary until it departed at pt.timestamp.
      final DateTime endHalt;
      if (impliedSpeedMps > 8.0) {
        endHalt = currentHalt.last.timestamp;
      } else {
        endHalt = pt.timestamp;
      }

      final haltDuration = endHalt.difference(startHalt);
      final isAtTripStart = (i - currentHalt.length) == 0;
      final hasStationaryProof = currentHalt.length >= 2 || currentHalt.first.speed < 1.0;

      if (haltDuration >= minDuration && !isAtTripStart && hasStationaryProof) {
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
      currentHalt = [pt];
    }
  }

  // 2. Process final stationary points and ALWAYS create the End Stoppage
  final lastPoint = points.last;
  final DateTime endArrivalTime;
  final Duration endParkedDuration;

  if (currentHalt.isNotEmpty && currentHalt.first != points.first) {
    endArrivalTime = currentHalt.first.timestamp;
    endParkedDuration = lastPoint.timestamp.difference(currentHalt.first.timestamp);
  } else {
    endArrivalTime = lastPoint.timestamp;
    endParkedDuration = Duration.zero;
  }

  stoppages.add(StoppageModel(
    stopNumber: stopCounter,
    latitude: lastPoint.latitude,
    longitude: lastPoint.longitude,
    arrivedAt: endArrivalTime,
    departedAt: lastPoint.timestamp,
    duration: endParkedDuration,
    isEndStop: true,
  ));

  return stoppages;
}
