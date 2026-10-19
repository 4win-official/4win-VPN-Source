import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/data/operator_ipv4_snapshot.dart';
import 'package:vpn_swift/services/operator_ipv4_catalog.dart';

void main() {
  test('generated snapshot has current metadata and bounded batches', () {
    expect(OperatorIpv4Catalog.operators, hasLength(2));
    for (final catalog in OperatorIpv4Catalog.operators) {
      expect(catalog.sourceUrl, contains('announced-prefixes'));
      expect(catalog.updatedAt, '2026-10-19T00:00:00Z');
      expect(catalog.rawIpv4Count, greaterThan(0));
      expect(catalog.totalAddresses, greaterThan(0));
      expect(catalog.batchCount, (catalog.totalAddresses + 199999) ~/ 200000);
      for (var i = 0; i < catalog.batchCount; i++) {
        expect(catalog.batchSize(i), lessThanOrEqualTo(200000));
      }
    }
  });

  test(
    'real snapshot batches are numeric, disjoint, and final batch is short',
    () {
      for (final catalog in OperatorIpv4Catalog.operators) {
        final first = catalog.targetsForBatch(0);
        final last = catalog.targetsForBatch(catalog.batchCount - 1);
        expect(first.first, matches(RegExp(r'^\d+\.\d+\.\d+\.\d+$')));
        expect(first.length, catalog.batchSize(0));
        expect(last.length, catalog.batchSize(catalog.batchCount - 1));
        expect(last.length, lessThanOrEqualTo(200000));
        if (catalog.batchCount > 1) {
          expect(first.last, isNot(equals(last.first)));
        }
      }
    },
  );

  test('fixture constructor preserves every address in overlapping union', () {
    final catalog = OperatorIpv4Catalog(
      id: 'fixture',
      label: 'Fixture',
      asn: 'AS0',
      sourceUrl: 'fixture',
      updatedAt: '2026-01-01T00:00:00',
      ranges: const <List<int>>[
        <int>[0, 2],
        <int>[10, 300005],
      ],
    );
    expect(catalog.totalAddresses, 3 + 299996);
    expect(catalog.batchCount, 2);
    expect(catalog.targetsForBatch(0).length, 200000);
    expect(catalog.targetsForBatch(0).first, '0.0.0.0');
    expect(catalog.targetsForBatch(0).last, '0.3.13.70');
    expect(catalog.targetsForBatch(1).length, 99999);
    expect(catalog.targetsForBatch(1).first, '0.3.13.71');
    expect(() => catalog.targetsForBatch(-1), throwsRangeError);
    expect(() => catalog.targetsForBatch(2), throwsRangeError);
    expect(
      () => OperatorIpv4Catalog(
        id: 'bad',
        label: 'bad',
        asn: 'AS0',
        sourceUrl: 'x',
        updatedAt: 'x',
        ranges: const <List<int>>[
          <int>[2, 4],
          <int>[4, 6],
        ],
      ),
      throwsArgumentError,
    );
  });

  test('generated snapshot contains no IPv6 ranges', () {
    for (final snapshot in operatorIpv4Snapshots) {
      expect(
        snapshot.ranges.every(
          (range) =>
              range.length == 2 && range[0] >= 0 && range[1] <= 0xffffffff,
        ),
        isTrue,
      );
      expect(
        snapshot.visibleIpv4Count,
        lessThanOrEqualTo(snapshot.rawIpv4Count),
      );
      expect(snapshot.collapsedTotalAddresses, greaterThan(0));
    }
  });
}
