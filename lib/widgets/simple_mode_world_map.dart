import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/ip_geolocation_service.dart';
import '../services/vpn_service.dart' show VpnConnectionStatus;

/// A quiet, country-focused map for Simple mode.
///
/// Only a successful lookup is allowed to choose the focused country. A direct
/// IP is used while disconnected; a current-IP lookup is used as the VPN exit
/// while the tunnel is active. If either lookup is unavailable, the map stays
/// unmarked rather than inferring a location.
class SimpleModeWorldMap extends StatefulWidget {
  const SimpleModeWorldMap({
    super.key,
    required this.status,
    required this.connecting,
    required this.isDark,
    this.lookupSourceIpLocation,
    this.lookupCurrentIpLocation,
  });

  final VpnConnectionStatus status;
  final bool connecting;
  final bool isDark;
  final IpLocationLookup? lookupSourceIpLocation;
  final IpLocationLookup? lookupCurrentIpLocation;

  @override
  State<SimpleModeWorldMap> createState() => _SimpleModeWorldMapState();
}

class _SimpleModeWorldMapState extends State<SimpleModeWorldMap> {
  IpGeolocationService? _geolocation;
  List<_MapCountry> _countries = const [];
  IpLocation? _directIpLocation;
  IpLocation? _vpnExitLocation;
  int _directLookupGeneration = 0;
  int _exitLookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCountries());
    unawaited(_lookupDirectIp());
    if (_isTunnelActive(widget.status)) unawaited(_lookupVpnExit());
  }

  @override
  void didUpdateWidget(covariant SimpleModeWorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status) return;

    if (_isTunnelActive(widget.status)) {
      if (_directIpLocation == null) unawaited(_lookupDirectIp());
      unawaited(_lookupVpnExit());
    } else if (_isDirectState(widget.status)) {
      _exitLookupGeneration++;
      unawaited(_lookupDirectIp());
    } else {
      // A connection attempt is not evidence of a VPN exit yet.
      _exitLookupGeneration++;
    }
  }

  Future<void> _loadCountries() async {
    try {
      final source = await rootBundle.loadString(
        'assets/maps/world_countries.json',
      );
      final decoded = jsonDecode(source);
      if (decoded is! List) return;
      final countries = decoded
          .whereType<Map<String, dynamic>>()
          .map(_MapCountry.fromJson)
          .where((country) => country.polygons.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _countries = countries);
    } on Object {
      // The screen remains usable; an unavailable asset must not imply a place.
    }
  }

  Future<void> _lookupDirectIp() async {
    final generation = ++_directLookupGeneration;
    if (mounted) {
      setState(() {
        _directIpLocation = null;
        _vpnExitLocation = null;
      });
    }

    final location = await _readDirectIpLocation();
    if (!mounted || generation != _directLookupGeneration) return;
    setState(() => _directIpLocation = location);
  }

  Future<void> _lookupVpnExit() async {
    final generation = ++_exitLookupGeneration;
    if (mounted) setState(() => _vpnExitLocation = null);

    final location = await _readVpnExitLocation();
    if (!mounted ||
        generation != _exitLookupGeneration ||
        !_isTunnelActive(widget.status)) {
      return;
    }
    setState(() => _vpnExitLocation = location);
  }

  Future<IpLocation?> _readDirectIpLocation() async {
    final explicitSourceLookup = widget.lookupSourceIpLocation;
    if (explicitSourceLookup != null) {
      return _safeLookup(explicitSourceLookup);
    }

    // Once a tunnel is active, the ordinary current-IP endpoint returns the
    // VPN exit. It cannot be used to reconstruct the user's direct IP country.
    if (_isTunnelActive(widget.status)) return null;

    final injectedCurrentLookup = widget.lookupCurrentIpLocation;
    if (injectedCurrentLookup != null) {
      return _safeLookup(injectedCurrentLookup);
    }
    return _safeLookup(
      () => (_geolocation ??= IpGeolocationService()).lookupCurrent(),
    );
  }

  Future<IpLocation?> _readVpnExitLocation() {
    final currentLookup = widget.lookupCurrentIpLocation;
    if (currentLookup == null) return Future<IpLocation?>.value(null);
    return _safeLookup(currentLookup);
  }

  Future<IpLocation?> _safeLookup(IpLocationLookup lookup) async {
    try {
      return await lookup();
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _directLookupGeneration++;
    _exitLookupGeneration++;
    _geolocation?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tunnelActive = _isTunnelActive(widget.status);
    final location = tunnelActive ? _vpnExitLocation : _directIpLocation;
    final locationColor = tunnelActive
        ? _MapPalette.exit(isDark: widget.isDark).marker
        : _MapPalette.direct(isDark: widget.isDark).marker;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('simple-world-map-canvas'),
            painter: _CountryAtlasPainter(
              countries: _countries,
              location: location,
              tunnelActive: tunnelActive,
              isDark: widget.isDark,
            ),
          ),
        ),
        if (location != null)
          PositionedDirectional(
            top: 8,
            start: 0,
            end: 0,
            child: Center(
              child: _MapLocationLabel(
                key: ValueKey(
                  'simple-world-map-location-${location.countryCode}',
                ),
                label:
                    '${context.l10n.text(tunnelActive ? 'VPN exit' : 'Direct IP')} · ${location.countryName}',
                color: locationColor,
                isDark: widget.isDark,
              ),
            ),
          ),
      ],
    );
  }
}

bool _isTunnelActive(VpnConnectionStatus status) =>
    status == VpnConnectionStatus.connected ||
    status == VpnConnectionStatus.disconnecting;

bool _isDirectState(VpnConnectionStatus status) =>
    status == VpnConnectionStatus.disconnected ||
    status == VpnConnectionStatus.error;

class _MapLocationLabel extends StatelessWidget {
  const _MapLocationLabel({
    super.key,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: isDark ? const Color(0xE51B1A21) : const Color(0xF2FFFFFF),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFF272933).withValues(alpha: 0.10),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.07),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? const Color(0xFFF2F1F4) : const Color(0xFF272832),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MapCountry {
  const _MapCountry({required this.code, required this.polygons});

  final String code;
  final List<List<Offset>> polygons;

  factory _MapCountry.fromJson(Map<String, dynamic> json) {
    final rawPolygons = json['p'];
    final polygons = <List<Offset>>[];
    if (rawPolygons is List) {
      for (final rawPolygon in rawPolygons) {
        if (rawPolygon is! List) continue;
        final points = <Offset>[];
        for (final rawPoint in rawPolygon) {
          if (rawPoint is! List || rawPoint.length < 2) continue;
          final longitude = rawPoint[0];
          final latitude = rawPoint[1];
          if (longitude is! num || latitude is! num) continue;
          points.add(Offset(longitude.toDouble(), latitude.toDouble()));
        }
        if (points.length >= 3) polygons.add(points);
      }
    }
    final rawCode = json['c'];
    return _MapCountry(
      code: rawCode is String ? rawCode.toUpperCase() : '',
      polygons: polygons,
    );
  }
}

class _MapPalette {
  const _MapPalette({
    required this.country,
    required this.border,
    required this.highlight,
    required this.highlightBorder,
    required this.marker,
  });

  final Color country;
  final Color border;
  final Color highlight;
  final Color highlightBorder;
  final Color marker;

  factory _MapPalette.direct({required bool isDark}) => isDark
      ? const _MapPalette(
          country: Color(0xFF24232B),
          border: Color(0xFF595761),
          highlight: Color(0xFF654653),
          highlightBorder: Color(0xFFD27E91),
          marker: Color(0xFFFF7D96),
        )
      : const _MapPalette(
          country: Color(0xFFD9D7DB),
          border: Color(0xFF9B969F),
          highlight: Color(0xFFE1B9C1),
          highlightBorder: Color(0xFFB54D63),
          marker: Color(0xFFC9445D),
        );

  factory _MapPalette.exit({required bool isDark}) => isDark
      ? const _MapPalette(
          country: Color(0xFF23282C),
          border: Color(0xFF53605F),
          highlight: Color(0xFF35584B),
          highlightBorder: Color(0xFF79C69D),
          marker: Color(0xFF78E2AA),
        )
      : const _MapPalette(
          country: Color(0xFFD6DED9),
          border: Color(0xFF95A39A),
          highlight: Color(0xFFB6D8C5),
          highlightBorder: Color(0xFF3F946A),
          marker: Color(0xFF238756),
        );
}

class _CountryAtlasPainter extends CustomPainter {
  const _CountryAtlasPainter({
    required this.countries,
    required this.location,
    required this.tunnelActive,
    required this.isDark,
  });

  final List<_MapCountry> countries;
  final IpLocation? location;
  final bool tunnelActive;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final bounds = Offset.zero & size;
    final palette = tunnelActive
        ? _MapPalette.exit(isDark: isDark)
        : _MapPalette.direct(isDark: isDark);
    final selectedCode = location?.countryCode.toUpperCase();
    final selectedCountry = selectedCode == null
        ? null
        : _countryForCode(selectedCode);
    final projection = location == null
        ? _MapProjection.world(size)
        : _MapProjection.focused(
            size: size,
            location: location!,
            country: selectedCountry,
          );

    canvas.save();
    canvas.clipRect(bounds);

    final projectedCountries = <_ProjectedCountry>[];
    for (final country in countries) {
      if (country.code == 'AQ') continue;
      final paths = <Path>[];
      for (final polygon in country.polygons) {
        if (polygon.length < 3) continue;
        final path = Path();
        final first = projection.project(polygon.first);
        path.moveTo(first.dx, first.dy);
        for (final point in polygon.skip(1)) {
          final projected = projection.project(point);
          path.lineTo(projected.dx, projected.dy);
        }
        path.close();
        paths.add(path);
      }
      if (paths.isNotEmpty) {
        projectedCountries.add(_ProjectedCountry(country.code, paths));
      }
    }

    final countryPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.country;
    for (final country in projectedCountries) {
      for (final path in country.paths) {
        canvas.drawPath(path, countryPaint);
      }
    }

    if (selectedCode != null) {
      final selectedPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = palette.highlight;
      for (final country in projectedCountries) {
        if (country.code != selectedCode) continue;
        for (final path in country.paths) {
          canvas.drawPath(path, selectedPaint);
        }
      }
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.65, size.shortestSide * 0.0024)
      ..strokeJoin = StrokeJoin.round
      ..color = palette.border.withValues(alpha: isDark ? 0.78 : 0.82);
    final selectedBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.shortestSide * 0.0034)
      ..strokeJoin = StrokeJoin.round
      ..color = palette.highlightBorder.withValues(alpha: 0.94);

    for (final country in projectedCountries) {
      for (final path in country.paths) {
        canvas.drawPath(path, borderPaint);
        if (country.code == selectedCode) {
          canvas.drawPath(path, selectedBorderPaint);
        }
      }
    }

    if (location != null) {
      final point = projection.project(
        Offset(location!.longitude, location!.latitude),
      );
      _drawLocationPulse(canvas, point, palette.marker, size);
    }

    canvas.restore();
  }

  _MapCountry? _countryForCode(String code) {
    for (final country in countries) {
      if (country.code == code) return country;
    }
    return null;
  }

  void _drawLocationPulse(Canvas canvas, Offset point, Color color, Size size) {
    final radius = math.min(size.shortestSide * 0.18, 54.0);
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: isDark ? 0.28 : 0.20),
            color.withValues(alpha: isDark ? 0.12 : 0.08),
            Colors.transparent,
          ],
          stops: const [0, 0.54, 1],
        ).createShader(Rect.fromCircle(center: point, radius: radius)),
    );
    canvas.drawCircle(
      point,
      15,
      Paint()..color = color.withValues(alpha: isDark ? 0.18 : 0.15),
    );
    canvas.drawCircle(
      point,
      9.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: isDark ? 0.94 : 0.98),
    );
    canvas.drawCircle(point, 5.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CountryAtlasPainter oldDelegate) =>
      !identical(countries, oldDelegate.countries) ||
      !identical(location, oldDelegate.location) ||
      tunnelActive != oldDelegate.tunnelActive ||
      isDark != oldDelegate.isDark;
}

class _ProjectedCountry {
  const _ProjectedCountry(this.code, this.paths);

  final String code;
  final List<Path> paths;
}

class _MapProjection {
  const _MapProjection({
    required this.scale,
    required this.centerX,
    required this.centerY,
    required this.focusLongitude,
    required this.centerMercatorY,
    required this.wrapLongitudes,
  });

  final double scale;
  final double centerX;
  final double centerY;
  final double focusLongitude;
  final double centerMercatorY;
  final bool wrapLongitudes;

  static double _mercatorY(double latitude) {
    final clamped = latitude.clamp(-80.0, 85.0).toDouble();
    final radians = clamped * math.pi / 180;
    return math.log(math.tan(math.pi / 4 + radians / 2));
  }

  factory _MapProjection.world(Size size) {
    const minLatitude = -58.0;
    const maxLatitude = 84.0;
    final minY = _mercatorY(minLatitude);
    final maxY = _mercatorY(maxLatitude);
    final horizontalSpan = 2 * math.pi;
    final verticalSpan = maxY - minY;
    final scale = math.min(
      size.width * 0.96 / horizontalSpan,
      size.height * 0.94 / verticalSpan,
    );
    return _MapProjection(
      scale: scale,
      centerX: size.width / 2,
      centerY: size.height / 2,
      focusLongitude: 0,
      centerMercatorY: (minY + maxY) / 2,
      wrapLongitudes: false,
    );
  }

  factory _MapProjection.focused({
    required Size size,
    required IpLocation location,
    required _MapCountry? country,
  }) {
    final bounds = country == null
        ? null
        : _countryBoundsNearLocation(country, location);
    if (bounds == null) {
      return _MapProjection(
        scale: size.width / (62 * math.pi / 180),
        centerX: size.width / 2,
        centerY: size.height / 2,
        focusLongitude: location.longitude,
        centerMercatorY: _mercatorY(location.latitude),
        wrapLongitudes: true,
      );
    }

    final countryWidth = bounds.longitudeSpan * math.pi / 180;
    final countryHeight = bounds.mercatorSpan;
    final fitByWidth = countryWidth <= 0
        ? double.infinity
        : size.width * 0.86 / countryWidth;
    final fitByHeight = countryHeight <= 0
        ? double.infinity
        : size.height * 0.82 / countryHeight;
    final maximumDetail = size.width / (6 * math.pi / 180);
    final scale = math.min(math.min(fitByWidth, fitByHeight), maximumDetail);

    return _MapProjection(
      scale: scale,
      centerX: size.width / 2,
      centerY: size.height / 2,
      focusLongitude:
          location.longitude + (bounds.minLongitude + bounds.maxLongitude) / 2,
      centerMercatorY: (bounds.minMercatorY + bounds.maxMercatorY) / 2,
      wrapLongitudes: true,
    );
  }

  Offset project(Offset longitudeLatitude) {
    var longitudeDelta = longitudeLatitude.dx - focusLongitude;
    if (wrapLongitudes) {
      longitudeDelta = (longitudeDelta + 540) % 360 - 180;
    }
    final latitude = longitudeLatitude.dy.clamp(-80.0, 85.0).toDouble();
    return Offset(
      centerX + longitudeDelta * math.pi / 180 * scale,
      centerY - (_mercatorY(latitude) - centerMercatorY) * scale,
    );
  }
}

class _CountryBounds {
  const _CountryBounds({
    required this.minLongitude,
    required this.maxLongitude,
    required this.minMercatorY,
    required this.maxMercatorY,
  });

  final double minLongitude;
  final double maxLongitude;
  final double minMercatorY;
  final double maxMercatorY;

  double get longitudeSpan => maxLongitude - minLongitude;
  double get mercatorSpan => maxMercatorY - minMercatorY;

  double distanceSquaredFromOrigin(double focusMercatorY) {
    final longitudeDistance = minLongitude > 0
        ? minLongitude
        : maxLongitude < 0
        ? maxLongitude
        : 0.0;
    final latitudeDistance = minMercatorY > focusMercatorY
        ? minMercatorY - focusMercatorY
        : maxMercatorY < focusMercatorY
        ? maxMercatorY - focusMercatorY
        : 0.0;
    return longitudeDistance * longitudeDistance +
        latitudeDistance * latitudeDistance;
  }
}

_CountryBounds? _countryBoundsNearLocation(
  _MapCountry country,
  IpLocation location,
) {
  final focusY = _mercatorLatitude(location.latitude);
  final polygonBounds = <_CountryBounds>[];
  final containingBounds = <_CountryBounds>[];

  for (final polygon in country.polygons) {
    if (polygon.length < 3) continue;
    var minLongitude = double.infinity;
    var maxLongitude = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var containsLocation = false;
    var previous = polygon.last;
    var previousX = _wrappedLongitudeDelta(previous.dx, location.longitude);

    for (final point in polygon) {
      final x = _wrappedLongitudeDelta(point.dx, location.longitude);
      final y = _mercatorLatitude(point.dy);
      minLongitude = math.min(minLongitude, x);
      maxLongitude = math.max(maxLongitude, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);

      final previousY = _mercatorLatitude(previous.dy);
      if ((previousY > focusY) != (y > focusY)) {
        final edgeX = previousX +
            (x - previousX) * (focusY - previousY) / (y - previousY);
        if (edgeX > 0) containsLocation = !containsLocation;
      }
      previous = point;
      previousX = x;
    }

    final bounds = _CountryBounds(
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
      minMercatorY: minY,
      maxMercatorY: maxY,
    );
    polygonBounds.add(bounds);
    if (containsLocation) containingBounds.add(bounds);
  }

  final candidates = containingBounds.isNotEmpty
      ? containingBounds
      : polygonBounds;
  if (candidates.isEmpty) return null;
  return candidates.reduce((best, candidate) {
    if (containingBounds.isNotEmpty) {
      return candidate.longitudeSpan * candidate.mercatorSpan <
              best.longitudeSpan * best.mercatorSpan
          ? candidate
          : best;
    }
    return candidate.distanceSquaredFromOrigin(focusY) <
            best.distanceSquaredFromOrigin(focusY)
        ? candidate
        : best;
  });
}

double _wrappedLongitudeDelta(double longitude, double reference) =>
    (longitude - reference + 540) % 360 - 180;

double _mercatorLatitude(double latitude) {
  final clamped = latitude.clamp(-80.0, 85.0).toDouble();
  final radians = clamped * math.pi / 180;
  return math.log(math.tan(math.pi / 4 + radians / 2));
}
