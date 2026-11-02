import 'dart:convert';

import 'package:http/http.dart' as http;

typedef IpLocationLookup = Future<IpLocation?> Function();

/// Country-level location returned by the public IP's geolocation provider.
/// Coordinates are approximate and are never inferred from a VPN server label.
class IpLocation {
  const IpLocation({
    required this.countryCode,
    required this.countryName,
    required this.latitude,
    required this.longitude,
  });

  final String countryCode;
  final String countryName;
  final double latitude;
  final double longitude;

  static IpLocation? fromIpWhoIsJson(Object? value) {
    if (value is! Map<String, dynamic> || value['success'] != true) return null;

    final rawCode = value['country_code'];
    final rawName = value['country'];
    final rawLatitude = value['latitude'];
    final rawLongitude = value['longitude'];
    if (rawCode is! String || rawName is! String) return null;

    final code = rawCode.trim().toUpperCase();
    final name = rawName.trim();
    final latitude = _asDouble(rawLatitude);
    final longitude = _asDouble(rawLongitude);
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code) ||
        name.isEmpty ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return IpLocation(
      countryCode: code,
      countryName: name,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      final result = value.toDouble();
      return result.isFinite ? result : null;
    }
    if (value is String) {
      final result = double.tryParse(value);
      return result != null && result.isFinite ? result : null;
    }
    return null;
  }
}

/// Looks up the country and approximate coordinates of the current public IP.
/// The lookup is made only when the Simple-mode map needs a location, not on a
/// timer. Network, HTTP, parsing, and provider errors all return null so the UI
/// can leave the map unmarked instead of guessing.
class IpGeolocationService {
  IpGeolocationService({http.Client? client})
    : _client = client ?? http.Client();

  static final Uri _endpoint = Uri.https('ipwho.is', '/');
  final http.Client _client;

  Future<IpLocation?> lookupCurrent() async {
    return _lookup(_endpoint);
  }

  Future<IpLocation?> lookupIp(String ip) async {
    final normalized = ip.trim();
    if (normalized.isEmpty ||
        !RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(normalized) ||
        (!normalized.contains('.') && !normalized.contains(':'))) {
      return null;
    }
    return _lookup(Uri.https('ipwho.is', '/$normalized'));
  }

  Future<IpLocation?> _lookup(Uri endpoint) async {
    try {
      final response = await _client
          .get(endpoint, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return IpLocation.fromIpWhoIsJson(decoded);
    } on Object {
      return null;
    }
  }

  void close() => _client.close();
}
