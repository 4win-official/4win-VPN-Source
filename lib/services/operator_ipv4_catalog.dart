import '../data/operator_ipv4_snapshot.dart';
import 'dns_scanner_service.dart';

/// A deterministic, IPv4-only catalog entry for one mobile operator.
class OperatorIpv4Catalog {
  static const int maxTargets = DnsScannerService.maxTargets;

  static final List<OperatorIpv4Catalog> operators = List.unmodifiable(
    operatorIpv4Snapshots.map(OperatorIpv4Catalog.fromSnapshot),
  );

  OperatorIpv4Catalog({
    required this.id,
    required this.label,
    required this.asn,
    required this.sourceUrl,
    required this.updatedAt,
    required List<List<int>> ranges,
    this.rawIpv4Count = 0,
  }) : _ranges = _validateRanges(ranges),
       totalAddresses = _countAddresses(ranges) {
    if (totalAddresses <= 0) {
      throw ArgumentError('An operator catalog must contain IPv4 addresses.');
    }
    batchCount = (totalAddresses + maxTargets - 1) ~/ maxTargets;
  }

  factory OperatorIpv4Catalog.fromSnapshot(OperatorIpv4Snapshot snapshot) {
    return OperatorIpv4Catalog(
      id: snapshot.id,
      label: snapshot.label,
      asn: snapshot.asn,
      sourceUrl: snapshot.sourceUrl,
      updatedAt: snapshot.updatedAt,
      rawIpv4Count: snapshot.rawIpv4Count,
      ranges: snapshot.ranges,
    );
  }

  final String id;
  final String label;
  final String asn;
  final String sourceUrl;

  /// The query end time in UTC, not the server response timestamp.
  final String updatedAt;
  final int rawIpv4Count;
  final List<List<int>> _ranges;
  final int totalAddresses;
  late final int batchCount;

  int batchSize(int index) {
    _checkBatch(index);
    final start = index * maxTargets;
    final remaining = totalAddresses - start;
    return remaining < maxTargets ? remaining : maxTargets;
  }

  /// Expands exactly one batch. Every numeric address in the collapsed union is
  /// included; no network/broadcast or private-address filtering is applied.
  List<String> targetsForBatch(int zeroBasedIndex) {
    final size = batchSize(zeroBasedIndex);
    final out = <String>[];
    final ordinal = zeroBasedIndex * maxTargets;
    var skip = ordinal;
    for (final range in _ranges) {
      final rangeSize = range[1] - range[0] + 1;
      if (skip >= rangeSize) {
        skip -= rangeSize;
        continue;
      }
      var value = range[0] + skip;
      final available = range[1] - value + 1;
      final take = available < size - out.length
          ? available
          : size - out.length;
      for (var i = 0; i < take; i++) {
        out.add(_toIpv4(value + i));
      }
      if (out.length == size) break;
      skip = 0;
    }
    if (out.length != size) {
      throw StateError(
        'Catalog ranges ended before batch $zeroBasedIndex was filled.',
      );
    }
    return out;
  }

  void _checkBatch(int index) {
    if (index < 0 || index >= batchCount) {
      throw RangeError.index(index, this, 'batch index', null, batchCount);
    }
  }

  static List<List<int>> _validateRanges(List<List<int>> input) {
    if (input.isEmpty) throw ArgumentError('ranges must not be empty');
    final copy = <List<int>>[];
    var previousEnd = -2;
    for (final range in input) {
      if (range.length != 2) throw ArgumentError('ranges must be [start, end]');
      final start = range[0], end = range[1];
      if (start < 0 || end < start || end > 0xffffffff) {
        throw ArgumentError('range is outside IPv4 or is reversed');
      }
      if (previousEnd != -2 && start <= previousEnd) {
        throw ArgumentError('ranges must be sorted and disjoint');
      }
      copy.add(List.unmodifiable(<int>[start, end]));
      previousEnd = end;
    }
    return List.unmodifiable(copy);
  }

  static int _countAddresses(List<List<int>> ranges) {
    var total = 0;
    for (final range in ranges) {
      total += range[1] - range[0] + 1;
    }
    return total;
  }

  static String _toIpv4(int value) =>
      '${(value >> 24) & 255}.${(value >> 16) & 255}.${(value >> 8) & 255}.${value & 255}';
}
