import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/ip_geolocation_service.dart';
import '../services/vpn_service.dart' show VpnConnectionStatus;

/// Lightweight Simple-mode background map. Country geometry is local; only
/// country highlights and the route depend on successful public-IP lookups.
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
  List<_MapCountry> _countries = const <_MapCountry>[];
  IpLocation? _source;
  IpLocation? _destination;
  int _sourceLookupGeneration = 0;
  int _destinationLookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMap());
    unawaited(_lookupSource());
    if (widget.status == VpnConnectionStatus.connected) {
      unawaited(_lookupDestination());
    }
  }

  @override
  void didUpdateWidget(covariant SimpleModeWorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status) return;

    if (widget.status == VpnConnectionStatus.connected) {
      if (_source == null) unawaited(_lookupSource());
      unawaited(_lookupDestination());
    } else if (widget.connecting ||
        widget.status == VpnConnectionStatus.connecting) {
      // Keep the direct/source request independent; invalidate only a pending
      // destination request while the tunnel is being established.
      _destinationLookupGeneration++;
    } else if (_isDirectState(widget.status)) {
      _destinationLookupGeneration++;
      unawaited(_lookupSource());
    }
  }

  Future<void> _loadMap() async {
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
      // Keep the screen usable if an asset is unavailable; never invent a
      // country highlight when there is no usable map or IP metadata.
    }
  }

  Future<void> _lookupSource() async {
    final generation = ++_sourceLookupGeneration;
    if (mounted) {
      setState(() {
        _source = null;
        _destination = null;
      });
    }
    final location = await _lookupSourceIpLocation();
    if (!mounted || generation != _sourceLookupGeneration) return;
    setState(() => _source = location);
  }

  Future<void> _lookupDestination() async {
    final generation = ++_destinationLookupGeneration;
    if (mounted) setState(() => _destination = null);
    final location = await _lookupDestinationIpLocation();
    if (!mounted ||
        generation != _destinationLookupGeneration ||
        !_isTunnelActive(widget.status)) {
      return;
    }
    setState(() => _destination = location);
  }

  @override
  void dispose() {
    _sourceLookupGeneration++;
    _destinationLookupGeneration++;
    _geolocation?.close();
    super.dispose();
  }

  Future<IpLocation?> _lookupSourceIpLocation() {
    final sourceLookup = widget.lookupSourceIpLocation;
    if (sourceLookup != null) return sourceLookup();

    // Preserve the existing injected lookup for direct-state widget tests, but
    // never mistake a connected destination lookup for the direct source.
    if (!_isTunnelActive(widget.status)) {
      final currentLookup = widget.lookupCurrentIpLocation;
      if (currentLookup != null) return currentLookup();
    }
    return (_geolocation ??= IpGeolocationService()).lookupCurrent();
  }

  Future<IpLocation?> _lookupDestinationIpLocation() {
    final lookup = widget.lookupCurrentIpLocation;
    if (lookup != null) return lookup();
    // A direct current-IP lookup is not a safe substitute for tunnel egress.
    return Future<IpLocation?>.value(null);
  }

  @override
  Widget build(BuildContext context) {
    final tunnelActive = _isTunnelActive(widget.status);
    final showSource = tunnelActive
        ? _source != null &&
              _destination != null &&
              _source!.countryCode != _destination!.countryCode
        : _source != null;
    final showDestination = tunnelActive && _destination != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('simple-world-map-canvas'),
            painter: _WorldMapPainter(
              countries: _countries,
              source: _source,
              destination: _destination,
              tunnelActive: tunnelActive,
              isDark: widget.isDark,
            ),
          ),
        ),
        if (showSource || showDestination)
          PositionedDirectional(
            top: 6,
            start: 0,
            end: 0,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 4,
              children: [
                if (showSource)
                  _MapLegendItem(
                    color: const Color(0xFFFF626A),
                    label: context.l10n.text('Your location'),
                  ),
                if (showDestination)
                  _MapLegendItem(
                    color: const Color(0xFF44D18C),
                    label: context.l10n.text('VPN location'),
                  ),
              ],
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

class _MapLegendItem extends StatelessWidget {
  const _MapLegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF08090A).withValues(alpha: 0.58)
          : Colors.white.withValues(alpha: 0.64),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : const Color(0xFF41464D),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
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
    final rawCode = json['c'];
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
        if (points.length >= 4) polygons.add(points);
      }
    }
    return _MapCountry(
      code: rawCode is String ? rawCode : '',
      polygons: polygons,
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  const _WorldMapPainter({
    required this.countries,
    required this.source,
    required this.destination,
    required this.tunnelActive,
    required this.isDark,
  });

  final List<_MapCountry> countries;
  final IpLocation? source;
  final IpLocation? destination;
  final bool tunnelActive;
  final bool isDark;

  static const Color _sourceColor = Color(0xFFFF626A);
  static const Color _destinationColor = Color(0xFF44D18C);
  static const List<Offset> _starPoints = [
    Offset(0.08, 0.18),
    Offset(0.15, 0.76),
    Offset(0.21, 0.35),
    Offset(0.29, 0.88),
    Offset(0.37, 0.12),
    Offset(0.43, 0.72),
    Offset(0.52, 0.23),
    Offset(0.59, 0.91),
    Offset(0.66, 0.14),
    Offset(0.73, 0.81),
    Offset(0.81, 0.28),
    Offset(0.89, 0.68),
    Offset(0.94, 0.14),
    Offset(0.12, 0.49),
    Offset(0.85, 0.48),
    Offset(0.48, 0.53),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _drawAtmosphere(canvas, size);
    final sourceCode = tunnelActive ? source?.countryCode : source?.countryCode;
    final destinationCode = tunnelActive ? destination?.countryCode : null;
    final showSource =
        !tunnelActive ||
        (sourceCode != null &&
            destinationCode != null &&
            sourceCode != destinationCode);
    final activeCodes = <String>{
      if (showSource && sourceCode != null) sourceCode,
      if (destinationCode != null) destinationCode,
    };
    final projection = _MapProjection.fit(
      size: size,
      countries: countries,
      activeCodes: activeCodes,
      source: showSource ? source : null,
      destination: destinationCode == null ? null : destination,
    );

    final projected = <_ProjectedCountry>[];
    for (final country in countries) {
      // Antarctica is omitted from the default globe framing to keep the
      // inhabited world larger and more legible on a phone screen.
      if (activeCodes.isEmpty && country.code == 'AQ') continue;
      final paths = <Path>[];
      for (final polygon in country.polygons) {
        if (polygon.length < 4) continue;
        final path = Path();
        final first = projection.project(polygon.first);
        path.moveTo(first.dx, first.dy);
        for (final point in polygon.skip(1)) {
          final mapped = projection.project(point);
          path.lineTo(mapped.dx, mapped.dy);
        }
        path.close();
        paths.add(path);
      }
      if (paths.isNotEmpty) {
        projected.add(_ProjectedCountry(country.code, paths));
      }
    }

    final landShadowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x46000000);
    for (final country in projected) {
      for (final path in country.paths) {
        canvas.drawPath(path.shift(const Offset(0, 1.8)), landShadowPaint);
      }
    }

    final baseFill = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xA8425057), Color(0xB04D5A61)]
            : const [Color(0xC1AAB8C2), Color(0xE0D5DFE5)],
      ).createShader(Offset.zero & size);
    for (final country in projected) {
      for (final path in country.paths) {
        canvas.drawPath(path, baseFill);
      }
    }

    _drawGlobeGrid(canvas, size);

    for (final country in projected) {
      final fill = _highlightFill(country.code, sourceCode, destinationCode);
      if (fill == null) continue;
      final highlightPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = fill.withValues(alpha: 0.72);
      for (final path in country.paths) {
        canvas.drawPath(path, highlightPaint);
      }
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.62
      ..strokeJoin = StrokeJoin.round
      ..color = isDark
          ? const Color(0xFFAAB2B7).withValues(alpha: 0.32)
          : const Color(0xFF69737C).withValues(alpha: 0.34);
    final selectedBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..strokeJoin = StrokeJoin.round;
    for (final country in projected) {
      final selectedColor = _highlightFill(
        country.code,
        sourceCode,
        destinationCode,
      );
      final Paint paint;
      if (selectedColor == null) {
        paint = borderPaint;
      } else {
        selectedBorderPaint.color = selectedColor;
        paint = selectedBorderPaint;
      }
      for (final path in country.paths) {
        canvas.drawPath(path, paint);
      }
    }

    final reliefEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.38
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0x229CB9C6);
    for (final country in projected) {
      if (_highlightFill(country.code, sourceCode, destinationCode) != null) {
        continue;
      }
      for (final path in country.paths) {
        canvas.drawPath(path.shift(const Offset(-0.3, -0.4)), reliefEdgePaint);
      }
    }

    if (tunnelActive &&
        source != null &&
        destination != null &&
        source!.countryCode != destination!.countryCode) {
      final from = projection.project(
        Offset(source!.longitude, source!.latitude),
      );
      final to = projection.project(
        Offset(destination!.longitude, destination!.latitude),
      );
      final control = Offset(
        (from.dx + to.dx) / 2,
        math.max(6.0, math.min(from.dy, to.dy) - size.height * 0.13),
      );
      final route = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
      canvas.drawPath(
        route,
        Paint()
          ..color = _destinationColor.withValues(alpha: isDark ? 0.24 : 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        route,
        Paint()
          ..color = Colors.white.withValues(alpha: isDark ? 0.9 : 0.86)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        route,
        Paint()
          ..color = _destinationColor.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15
          ..strokeCap = StrokeCap.round,
      );
    }

    if (tunnelActive && destination != null) {
      _drawMarker(
        canvas,
        projection.project(
          Offset(destination!.longitude, destination!.latitude),
        ),
        _destinationColor,
      );
    } else if (!tunnelActive && source != null) {
      _drawMarker(
        canvas,
        projection.project(Offset(source!.longitude, source!.latitude)),
        _sourceColor,
      );
    }
    if (tunnelActive &&
        source != null &&
        destination != null &&
        source!.countryCode != destination!.countryCode) {
      _drawMarker(
        canvas,
        projection.project(Offset(source!.longitude, source!.latitude)),
        _sourceColor,
      );
    }
  }

  Color? _highlightFill(
    String countryCode,
    String? sourceCode,
    String? destinationCode,
  ) {
    if (tunnelActive && destinationCode == countryCode) {
      return _destinationColor;
    }
    if ((!tunnelActive ||
            (sourceCode != null && sourceCode != destinationCode)) &&
        sourceCode == countryCode) {
      return _sourceColor;
    }
    return null;
  }

  void _drawAtmosphere(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final primaryTint = tunnelActive
        ? _destinationColor
        : const Color(0xFF70A9FF);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.05),
          radius: 0.92,
          colors: [
            primaryTint.withValues(alpha: isDark ? 0.12 : 0.09),
            primaryTint.withValues(alpha: isDark ? 0.035 : 0.045),
            Colors.transparent,
          ],
          stops: const [0, 0.58, 1],
        ).createShader(bounds),
    );
    final globeBounds = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.96,
      height: size.height * 0.9,
    );
    canvas.drawOval(
      globeBounds,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = (isDark ? Colors.white : const Color(0xFF486274)).withValues(
          alpha: isDark ? 0.09 : 0.11,
        ),
    );
    final starPaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFF4B718C)).withValues(
        alpha: isDark ? 0.26 : 0.16,
      );
    for (var i = 0; i < _starPoints.length; i++) {
      final point = Offset(
        _starPoints[i].dx * size.width,
        _starPoints[i].dy * size.height,
      );
      canvas.drawCircle(point, i % 4 == 0 ? 1.35 : 0.85, starPaint);
    }
  }

  void _drawGlobeGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..color = (isDark ? Colors.white : const Color(0xFF52738A)).withValues(
        alpha: isDark ? 0.105 : 0.12,
      );
    for (final fraction in const [0.2, 0.36, 0.5, 0.64, 0.8]) {
      final x = size.width * fraction;
      final bend = (size.width * 0.5 - x) * 0.34;
      final meridian = Path()
        ..moveTo(x, 0)
        ..cubicTo(
          x + bend,
          size.height * 0.32,
          x + bend,
          size.height * 0.68,
          x,
          size.height,
        );
      canvas.drawPath(meridian, gridPaint);
    }
    for (final fraction in const [0.24, 0.4, 0.6, 0.76]) {
      final y = size.height * fraction;
      final curve = fraction < 0.5 ? -size.height * 0.025 : size.height * 0.025;
      final parallel = Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * 0.5, y + curve, size.width, y);
      canvas.drawPath(parallel, gridPaint);
    }
  }

  void _drawMarker(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(
      point,
      12,
      Paint()..color = color.withValues(alpha: 0.14),
    );
    canvas.drawCircle(
      point,
      8.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = color.withValues(alpha: 0.72),
    );
    canvas.drawCircle(
      point,
      6.8,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );
    canvas.drawCircle(point, 4.7, Paint()..color = color);
    canvas.drawCircle(
      point,
      1.7,
      Paint()..color = Colors.white.withValues(alpha: 0.94),
    );
  }

  @override
  bool shouldRepaint(covariant _WorldMapPainter oldDelegate) =>
      !identical(countries, oldDelegate.countries) ||
      !identical(source, oldDelegate.source) ||
      !identical(destination, oldDelegate.destination) ||
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
    required this.offsetX,
    required this.offsetY,
  });

  final double scale;
  final double offsetX;
  final double offsetY;

  Offset project(Offset longitudeLatitude) => Offset(
    offsetX + longitudeLatitude.dx * scale,
    offsetY - longitudeLatitude.dy * scale,
  );

  factory _MapProjection.fit({
    required Size size,
    required List<_MapCountry> countries,
    required Set<String> activeCodes,
    required IpLocation? source,
    required IpLocation? destination,
  }) {
    var minLongitude = 180.0;
    var maxLongitude = -180.0;
    var minLatitude = 90.0;
    var maxLatitude = -90.0;
    var hasBounds = false;

    void include(double longitude, double latitude) {
      minLongitude = math.min(minLongitude, longitude);
      maxLongitude = math.max(maxLongitude, longitude);
      minLatitude = math.min(minLatitude, latitude);
      maxLatitude = math.max(maxLatitude, latitude);
      hasBounds = true;
    }

    for (final country in countries) {
      if (!activeCodes.contains(country.code)) continue;
      for (final polygon in country.polygons) {
        for (final point in polygon) {
          include(point.dx, point.dy);
        }
      }
    }
    if (source != null) {
      include(source.longitude, source.latitude);
    }
    if (destination != null) {
      include(destination.longitude, destination.latitude);
    }

    if (!hasBounds) {
      minLongitude = -180;
      maxLongitude = 180;
      minLatitude = -58;
      maxLatitude = 84;
    } else {
      final centerLongitude = (minLongitude + maxLongitude) / 2;
      final centerLatitude = (minLatitude + maxLatitude) / 2;
      final width = math.max(maxLongitude - minLongitude, 12.0);
      final height = math.max(maxLatitude - minLatitude, 10.0);
      minLongitude = centerLongitude - width / 2;
      maxLongitude = centerLongitude + width / 2;
      minLatitude = centerLatitude - height / 2;
      maxLatitude = centerLatitude + height / 2;
    }

    const edgePadding = 26.0;
    final availableWidth = math.max(1.0, size.width - edgePadding * 2);
    final availableHeight = math.max(1.0, size.height - edgePadding * 2);
    final longitudeSpan = math.max(1.0, maxLongitude - minLongitude);
    final latitudeSpan = math.max(1.0, maxLatitude - minLatitude);
    final scale = math.min(
      availableWidth / longitudeSpan,
      availableHeight / latitudeSpan,
    );
    final drawnWidth = longitudeSpan * scale;
    final drawnHeight = latitudeSpan * scale;
    final offsetX = (size.width - drawnWidth) / 2 - minLongitude * scale;
    final offsetY = (size.height - drawnHeight) / 2 + maxLatitude * scale;
    return _MapProjection(scale: scale, offsetX: offsetX, offsetY: offsetY);
  }
}
