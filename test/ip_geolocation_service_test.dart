import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vpn_swift/services/ip_geolocation_service.dart';

void main() {
  group('IpLocation.fromIpWhoIsJson', () {
    test('parses country code, name, and coordinates from API metadata', () {
      final location = IpLocation.fromIpWhoIsJson({
        'success': true,
        'ip': '203.0.113.10',
        'country_code': 'ir',
        'country': 'Iran',
        'latitude': 32.0,
        'longitude': 53.0,
      });

      expect(location, isNotNull);
      expect(location!.countryCode, 'IR');
      expect(location.countryName, 'Iran');
      expect(location.latitude, 32.0);
      expect(location.longitude, 53.0);
    });

    test('rejects unsuccessful, missing, or out-of-range metadata', () {
      expect(
        IpLocation.fromIpWhoIsJson({'success': false, 'country_code': 'IR'}),
        isNull,
      );
      expect(
        IpLocation.fromIpWhoIsJson({
          'success': true,
          'country_code': 'IR',
          'country': 'Iran',
          'latitude': 91,
          'longitude': 53,
        }),
        isNull,
      );
      expect(
        IpLocation.fromIpWhoIsJson({
          'success': true,
          'country_code': 'ZZZ',
          'country': 'Unknown',
          'latitude': 0,
          'longitude': 0,
        }),
        isNull,
      );
    });
  });

  group('IpGeolocationService', () {
    test(
      'uses HTTPS current-IP lookup and returns parsed country metadata',
      () async {
        final client = _FakeClient(
          statusCode: 200,
          body: jsonEncode({
            'success': true,
            'country_code': 'DE',
            'country': 'Germany',
            'latitude': 51.0,
            'longitude': 10.0,
          }),
        );
        final service = IpGeolocationService(client: client);

        final result = await service.lookupCurrent();

        expect(client.requestedUri?.scheme, 'https');
        expect(client.requestedUri?.host, 'ipwho.is');
        expect(client.requestedUri?.path, '/');
        expect(result?.countryCode, 'DE');
        service.close();
        expect(client.closed, isTrue);
      },
    );

    test('geolocates the supplied VPN exit IP over HTTPS', () async {
      final client = _FakeClient(
        statusCode: 200,
        body: jsonEncode({
          'success': true,
          'country_code': 'DE',
          'country': 'Germany',
          'latitude': 51.0,
          'longitude': 10.0,
        }),
      );
      final service = IpGeolocationService(client: client);

      final result = await service.lookupIp('203.0.113.10');

      expect(client.requestedUri?.scheme, 'https');
      expect(client.requestedUri?.host, 'ipwho.is');
      expect(client.requestedUri?.path, '/203.0.113.10');
      expect(result?.countryCode, 'DE');
      expect(await service.lookupIp('not-an-ip'), isNull);
      service.close();
    });

    test(
      'returns null instead of guessing if the request cannot locate IP',
      () async {
        final client = _FakeClient(
          statusCode: 200,
          body: '{"success":false,"message":"Reserved range"}',
        );
        final service = IpGeolocationService(client: client);

        expect(await service.lookupCurrent(), isNull);
        service.close();
      },
    );

    test('returns null on HTTP errors', () async {
      final client = _FakeClient(statusCode: 429, body: '{}');
      final service = IpGeolocationService(client: client);

      expect(await service.lookupCurrent(), isNull);
      service.close();
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  Uri? requestedUri;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUri = request.url;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }

  @override
  void close() => closed = true;
}
