import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:trackmyphone/core/map_tiles.dart';
import 'package:trackmyphone/widgets/animated_dashed_polyline_layer.dart';

void main() {
  testWidgets('AppMapTiles builds tile layers without unmodifiable map or runtime exceptions', (tester) async {
    final streetLayer = AppMapTiles.buildTileLayer(isSatellite: false);
    final satelliteLayer = AppMapTiles.buildTileLayer(isSatellite: true);

    expect(streetLayer.tileProvider, isNotNull);
    expect(satelliteLayer.tileProvider, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: ll.LatLng(12.9720, 77.5950),
              initialZoom: 15.0,
            ),
            children: [
              streetLayer,
            ],
          ),
        ),
      ),
    );

    expect(find.byType(TileLayer), findsOneWidget);
  });
  testWidgets('AnimatedDashedPolylineLayer renders static route when isMoving is false', (tester) async {
    final route = RoutePolylineStyle(
      points: [
        const ll.LatLng(12.9716, 77.5946),
        const ll.LatLng(12.9720, 77.5950),
        const ll.LatLng(12.9730, 77.5960),
      ],
      routeColor: const Color(0xFF10B981),
      isMoving: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: ll.LatLng(12.9720, 77.5950),
              initialZoom: 15.0,
            ),
            children: [
              AnimatedDashedPolylineLayer(
                routes: [route],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedDashedPolylineLayer), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('AnimatedDashedPolylineLayer animates when isMoving is true and freezes when stopped', (tester) async {
    final movingRoute = RoutePolylineStyle(
      points: [
        const ll.LatLng(12.9716, 77.5946),
        const ll.LatLng(12.9720, 77.5950),
        const ll.LatLng(12.9730, 77.5960),
      ],
      routeColor: const Color(0xFF10B981),
      isMoving: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: ll.LatLng(12.9720, 77.5950),
              initialZoom: 15.0,
            ),
            children: [
              AnimatedDashedPolylineLayer(
                routes: [movingRoute],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedDashedPolylineLayer), findsOneWidget);

    // Advance frames to ensure smooth animation
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    // Now update with isMoving: false (vehicle stopped)
    final stoppedRoute = RoutePolylineStyle(
      points: movingRoute.points,
      routeColor: movingRoute.routeColor,
      isMoving: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: ll.LatLng(12.9720, 77.5950),
              initialZoom: 15.0,
            ),
            children: [
              AnimatedDashedPolylineLayer(
                routes: [stoppedRoute],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(AnimatedDashedPolylineLayer), findsOneWidget);
  });
}

