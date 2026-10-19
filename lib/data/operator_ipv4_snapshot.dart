// GENERATED FILE. Run tools/update_operator_ipv4.py to refresh.

class OperatorIpv4Snapshot {
  const OperatorIpv4Snapshot({
    required this.id,
    required this.label,
    required this.asn,
    required this.sourceUrl,
    required this.returnedAt,
    required this.updatedAt,
    required this.rawIpv4Count,
    required this.visibleIpv4Count,
    required this.collapsedTotalAddresses,
    required this.ranges,
  });

  final String id;
  final String label;
  final String asn;
  final String sourceUrl;
  final String returnedAt;
  final String updatedAt;
  final int rawIpv4Count;
  final int visibleIpv4Count;
  final int collapsedTotalAddresses;

  /// Inclusive [start, end] IPv4 integer ranges, sorted and disjoint.
  final List<List<int>> ranges;
}

const operatorIpv4Snapshots = <OperatorIpv4Snapshot>[
  OperatorIpv4Snapshot(
    id: "mci",
    label: "MCI (Hamrah Aval)",
    asn: "AS197207",
    sourceUrl:
        "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS197207",
    returnedAt: "2026-10-19T06:01:42.718905",
    updatedAt: "2026-10-19T00:00:00Z",
    rawIpv4Count: 846,
    visibleIpv4Count: 796,
    collapsedTotalAddresses: 2301440,
    ranges: <List<int>>[
      <int>[85327872, 85360639],
      <int>[87293952, 87359487],
      <int>[90832896, 90898431],
      <int>[97107968, 97124351],
      <int>[97517568, 98041855],
      <int>[98041856, 98172927],
      <int>[98172928, 98238463],
      <int>[100270080, 100302847],
      <int>[520257536, 520290303],
      <int>[624918528, 624951295],
      <int>[627179520, 627195903],
      <int>[627195904, 627196415],
      <int>[627197440, 627197951],
      <int>[627197952, 627199999],
      <int>[627200000, 627204095],
      <int>[627204096, 627208191],
      <int>[627210240, 627212287],
      <int>[629211136, 629276671],
      <int>[775094272, 775102463],
      <int>[775103488, 775103999],
      <int>[775104000, 775104255],
      <int>[775104512, 775106559],
      <int>[775106560, 775110655],
      <int>[775110656, 775127039],
      <int>[782516224, 782532607],
      <int>[1046904832, 1046908927],
      <int>[1170358272, 1170374655],
      <int>[1358036992, 1358041087],
      <int>[1387577344, 1387593727],
      <int>[1400373248, 1400635391],
      <int>[1441775616, 1441783807],
      <int>[1446445056, 1446510591],
      <int>[1449852928, 1449857023],
      <int>[1449906176, 1449910271],
      <int>[1496133632, 1496137727],
      <int>[1506017280, 1506082815],
      <int>[1506148352, 1506279423],
      <int>[1535475712, 1535508479],
      <int>[1543176192, 1543241727],
      <int>[1567490048, 1567555583],
      <int>[1583738880, 1583742975],
      <int>[1598029824, 1598062591],
      <int>[1835835392, 1835843583],
      <int>[1842053120, 1842061311],
      <int>[1843494912, 1843511295],
      <int>[1909129216, 1909161983],
      <int>[2197798912, 2197815295],
      <int>[2654601216, 2654633983],
      <int>[2760540160, 2760556543],
      <int>[2890956800, 2890989567],
      <int>[2957099008, 2957107199],
      <int>[2994960384, 2994962431],
      <int>[2994978816, 2994995199],
      <int>[3104152576, 3104153599],
      <int>[3105234176, 3105234431],
      <int>[3162136576, 3162144767],
      <int>[3167862784, 3167866879],
      <int>[3167895552, 3167899647],
      <int>[3167928320, 3167932415],
      <int>[3168022528, 3168026623],
      <int>[3169124352, 3169140735],
      <int>[3169140736, 3169148927],
      <int>[3169154048, 3169154559],
      <int>[3222208512, 3222274047],
      <int>[3423731712, 3423797247],
    ],
  ),
  OperatorIpv4Snapshot(
    id: "irancell",
    label: "Irancell",
    asn: "AS44244",
    sourceUrl:
        "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS44244",
    returnedAt: "2026-10-19T06:01:44.506268",
    updatedAt: "2026-10-19T00:00:00Z",
    rawIpv4Count: 502,
    visibleIpv4Count: 394,
    collapsedTotalAddresses: 1231872,
    ranges: <List<int>>[
      <int>[42991616, 43007999],
      <int>[43016192, 43024383],
      <int>[43024384, 43032575],
      <int>[43040768, 43057151],
      <int>[43057152, 43122687],
      <int>[43122688, 43253759],
      <int>[91226112, 91488255],
      <int>[91488256, 91619327],
      <int>[91684864, 91750399],
      <int>[91750400, 92274687],
      <int>[1438196736, 1438197759],
      <int>[1546268672, 1546270719],
    ],
  ),
];
