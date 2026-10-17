import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GeocodingService extends ChangeNotifier {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;

  GeocodingService._internal();

  String _currentTitle = 'Locating address...';
  String _currentSubtitle = 'Fetching current area...';
  String _fullAddress = '';
  bool _isLoading = false;

  double? _lastLat;
  double? _lastLng;
  DateTime? _lastRequestTime;

  String get currentTitle => _currentTitle;
  String get currentSubtitle => _currentSubtitle;
  String get fullAddress {
    if (_fullAddress.isNotEmpty) return _fullAddress;
    if (_currentTitle.isNotEmpty && _currentTitle != 'Locating address...') {
      return _currentSubtitle.isNotEmpty ? '$_currentTitle, $_currentSubtitle' : _currentTitle;
    }
    return '';
  }
  bool get isLoading => _isLoading;

  final HttpClient _client = HttpClient();

  /// Updates address from coordinates, using distance caching and rate limiting.
  Future<void> updateFromPosition(double lat, double lng) async {
    // If coordinates are invalid, skip
    if (lat == 0.0 && lng == 0.0) return;

    // Proximity check: If user hasn't moved more than 40 meters and we already have an address, don't re-fetch
    if (_lastLat != null && _lastLng != null && _fullAddress.isNotEmpty) {
      final distance = Geolocator.distanceBetween(_lastLat!, _lastLng!, lat, lng);
      if (distance < 40) {
        return;
      }
    }

    // Rate-limiting check: OSM Nominatim requires max 1 req/sec
    final now = DateTime.now();
    if (_lastRequestTime != null && now.difference(_lastRequestTime!).inMilliseconds < 1200) {
      return;
    }

    _lastRequestTime = now;
    _isLoading = true;
    notifyListeners();

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'json',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });

      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 5));
      request.headers.set('User-Agent', 'TrackMyPhone/1.0 (contact@trackmyphone.app)');
      request.headers.set('Accept-Language', 'en');

      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final displayName = data['display_name'] as String? ?? '';
        final address = data['address'] as Map<String, dynamic>? ?? {};

        final road = address['road'] as String?;
        final suburb = address['suburb'] as String? ?? address['neighbourhood'] as String? ?? address['subdistrict'] as String?;
        final city = address['city'] as String? ?? address['town'] as String? ?? address['village'] as String? ?? address['municipality'] as String?;
        final state = address['state'] as String?;
        final country = address['country'] as String?;

        // Construct primary title
        if (road != null && road.isNotEmpty) {
          if (suburb != null && suburb.isNotEmpty && suburb != road) {
            _currentTitle = '$road, $suburb';
          } else {
            _currentTitle = road;
          }
        } else if (suburb != null && suburb.isNotEmpty) {
          _currentTitle = suburb;
        } else if (city != null && city.isNotEmpty) {
          _currentTitle = city;
        } else {
          _currentTitle = 'Current Location';
        }

        // Construct secondary subtitle
        final subParts = <String>[];
        if (city != null && city.isNotEmpty && !_currentTitle.contains(city)) {
          subParts.add(city);
        }
        if (state != null && state.isNotEmpty) {
          subParts.add(state);
        }
        if (country != null && country.isNotEmpty) {
          subParts.add(country);
        }

        _currentSubtitle = subParts.isNotEmpty ? subParts.join(', ') : displayName;
        _fullAddress = displayName;
        _lastLat = lat;
        _lastLng = lng;
      } else {
        _setFallbackAddress(lat, lng);
      }
    } catch (_) {
      _setFallbackAddress(lat, lng);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _setFallbackAddress(double lat, double lng) {
    if (_fullAddress.isEmpty) {
      _currentTitle = 'Lat: ${lat.toStringAsFixed(4)}°, Lng: ${lng.toStringAsFixed(4)}°';
      _currentSubtitle = 'GPS Location';
      _fullAddress = '$_currentTitle, $_currentSubtitle';
      _lastLat = lat;
      _lastLng = lng;
    }
  }
}

final geocodingService = GeocodingService();
