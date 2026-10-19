import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/screens/dns_scanner_screen.dart';
import 'package:vpn_swift/services/dns_vpn_connection.dart';
import 'package:vpn_swift/services/operator_ipv4_catalog.dart';

class _FakeFilePicker extends FilePicker {
  String? nextPath;
  Object? failure;
  Uint8List? savedBytes;
  String? savedFileName;
  List<String>? savedExtensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (failure != null) throw failure!;
    savedBytes = bytes;
    savedFileName = fileName;
    savedExtensions = allowedExtensions;
    return nextPath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    FilePicker.platform = _FakeFilePicker();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(360, 640),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: DnsScannerScreen()));
    await tester.pump();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(scroll.position.minScrollExtent);
      await tester.pump();
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final finder = find.bySemanticsLabel(label);
    await reveal(tester, finder);
    await tester.enterText(finder, value);
  }

  Future<void> start(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Start scan'));
    await tester.tap(find.text('Start scan'));
    await tester.pump();
  }

  testWidgets('shows exactly the two primary IPv4 choices on a narrow phone', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(320, 480));
    expect(find.text('Random public IPv4'), findsOneWidget);
    expect(find.textContaining('Supplementary'), findsNothing);
    expect(find.textContaining('optional note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('operator mode offers From/To and pasted range input', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.bySemanticsLabel('From IPv4'), findsOneWidget);
    expect(find.bySemanticsLabel('To IPv4'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Paste IPv4 addresses or CIDR ranges'),
      findsOneWidget,
    );
    expect(find.text('Import IPv4 ranges'), findsOneWidget);
    expect(find.textContaining('Enter your own IPv4 ranges'), findsOneWidget);
  });

  testWidgets('built-in choices preserve custom range input when switching', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(320, 480));
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '10.1.2.3');
    final choice = find.byType(DropdownButtonFormField<String>);
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    for (final operator in OperatorIpv4Catalog.operators) {
      expect(find.text(operator.label), findsOneWidget);
    }
    await tester.tap(find.text(OperatorIpv4Catalog.operators.first.label));
    await tester.pumpAndSettle();
    expect(find.textContaining('RIPE NCC snapshot:'), findsOneWidget);
    expect(
      find.textContaining('batches do not run automatically'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('From IPv4'), findsNothing);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom IPv4 ranges').last);
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText ==
                'Paste IPv4 addresses or CIDR ranges',
      ),
    );
    expect(input.controller!.text, '10.1.2.3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected operator batch supplies only that batch and can stop', (
    tester,
  ) async {
    await pumpScreen(tester);
    final operator = OperatorIpv4Catalog.operators.last;
    final choice = find.byType(DropdownButtonFormField<String>);
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text(operator.label));
    await tester.pumpAndSettle();
    final batchChoice = find.byType(DropdownButtonFormField<int>);
    await reveal(tester, batchChoice);
    await tester.tap(batchChoice);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        'Batch 2 / ${operator.batchCount} · ${operator.batchSize(1)} IPs',
      ),
    );
    await tester.pumpAndSettle();
    final pending = Completer<String>();
    final queried = <String>[];
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      queried.addAll(List<String>.from((call.arguments as Map)['ips'] as List));
      return pending.future;
    });
    await start(tester);
    expect(queried, operator.targetsForBatch(1).take(64).toList());
    await reveal(tester, find.byTooltip('Stop'));
    await tester.tap(find.byTooltip('Stop'));
    pending.complete('[]');
    await tester.pumpAndSettle();
    expect(queried, hasLength(64));
    await reveal(tester, find.textContaining('Tested 0 / 200000'));
    expect(
      find.textContaining('Batch 2 of ${operator.batchCount}'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasted IPv4 range is scanned and remains operator mode', (
    tester,
  ) async {
    List<String>? scanned;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      scanned = List<String>.from((call.arguments as Map)['ips'] as List);
      return '[]';
    });
    await pumpScreen(tester);
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '198.51.100.1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(scanned, ['198.51.100.1']);
  });

  testWidgets('random mode generates only public IPv4 targets', (tester) async {
    List<String>? scanned;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      scanned = List<String>.from((call.arguments as Map)['ips'] as List);
      return '[]';
    });
    await pumpScreen(tester);
    await tester.tap(find.text('Random public IPv4'));
    await tester.pump();
    await enter(tester, 'Random public IPv4 count (max 200000)', '3');
    await start(tester);
    await tester.pumpAndSettle();
    expect(scanned, hasLength(3));
    expect(scanned!.toSet(), hasLength(3));
    expect(
      scanned!.every((ip) => !ip.contains(':') && ip.split('.').length == 4),
      isTrue,
    );
  });

  testWidgets('IPv6 input is refused before native scanning', (tester) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') calls++;
      return jsonEncode([]);
    });
    await pumpScreen(tester);
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '2001:db8::1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('IPv6 is not supported'), findsWidgets);
  });

  Map<String, dynamic> safeResult(String ip) => {
    'ip': ip,
    'udpMs': 8,
    'tcpMs': 12,
    'reachable': true,
    'ednsSupported': true,
    'nxdomainSafe': true,
    'nxdomainHijacked': false,
    'tunnelCandidate': true,
    'targetResolved': true,
  };

  testWidgets('safe UDP candidate returns resolver and retains tested port', (
    tester,
  ) async {
    var scannedPort = 0;
    int? selected;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      scannedPort = (call.arguments as Map)['port'] as int;
      return jsonEncode([safeResult('1.1.1.1')]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DnsScannerScreen(
          initialPort: 5353,
          onPortSelected: (port) => selected = port,
        ),
      ),
    );
    await tester.pump();
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(scannedPort, 5353);
    await enter(tester, 'Port', '853');
    await reveal(tester, find.text('1.1.1.1 · Cloudflare'));
    await tester.tap(find.text('1.1.1.1 · Cloudflare'));
    expect(selected, 5353);
  });

  testWidgets('TCP-only or hijacked candidates cannot be selected', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      return jsonEncode([
        {...safeResult('1.1.1.1'), 'udpMs': -1},
        {...safeResult('1.1.1.2'), 'nxdomainHijacked': true},
      ]);
    });
    await pumpScreen(tester);
    await enter(
      tester,
      'Paste IPv4 addresses or CIDR ranges',
      '1.1.1.1 1.1.1.2',
    );
    await start(tester);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('1.1.1.1 · Cloudflare'));
    expect(find.textContaining('Not selectable'), findsNWidgets(2));
    await tester.tap(find.text('1.1.1.1 · Cloudflare'));
    expect(find.text('DNS resolver discovery'), findsOneWidget);
  });

  testWidgets(
    'Stop cancels pending native scan without starting later chunks',
    (tester) async {
      final pending = Completer<String>();
      var calls = 0;
      messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (
        call,
      ) async {
        if (call.method != 'scanDns') return null;
        calls++;
        return pending.future;
      });
      await pumpScreen(tester);
      await enter(tester, 'From IPv4', '1.1.1.1');
      await enter(tester, 'To IPv4', '1.1.1.3');
      await enter(tester, 'Workers (1–64)', '1');
      await start(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 1);
      await tester.tap(find.byTooltip('Stop'));
      pending.complete('[]');
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets('Workers zero is rejected before native scanning', (
    tester,
  ) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') calls++;
      return '[]';
    });
    await pumpScreen(tester);
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await enter(tester, 'Workers (1–64)', '0');
    await start(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('IPv6 From input is rejected before native scanning', (
    tester,
  ) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') calls++;
      return '[]';
    });
    await pumpScreen(tester);
    await enter(tester, 'From IPv4', '2001:db8::1');
    await enter(tester, 'To IPv4', '2001:db8::1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('IPv6 is not supported'), findsWidgets);
  });
  testWidgets('forwards custom scan config and locks fields', (tester) async {
    final pending = Completer<String>();
    Map<Object?, Object?>? args;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      args = Map<Object?, Object?>.from(call.arguments as Map);
      return pending.future;
    });
    await pumpScreen(tester);
    await enter(tester, 'Test domain or IPv4', 'Example.COM');
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await enter(tester, 'Port', '853');
    await enter(tester, 'Timeout ms', '4000');
    await enter(tester, 'Workers (1–64)', '3');
    await start(tester);
    expect(args, containsPair('domain', 'example.com'));
    expect(args, containsPair('port', 853));
    expect(args, containsPair('timeoutMs', 4000));
    expect(args, containsPair('parallel', 3));
    for (final label in [
      'Test domain or IPv4',
      'Port',
      'Timeout ms',
      'Workers (1–64)',
    ]) {
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await reveal(tester, field);
      expect(
        tester.widget<TextField>(field).enabled,
        isFalse,
      );
    }
    pending.complete('[]');
    await tester.pumpAndSettle();
  });

  testWidgets('narrow layout has no overflow', (tester) async {
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') return jsonEncode([safeResult('1.1.1.1')]);
      return null;
    });
    await pumpScreen(tester, size: const Size(280, 520));
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(find.text('Candidate resolvers (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-wave scan excludes unsafe results', (tester) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      final ip = ((call.arguments as Map)['ips'] as List).single as String;
      calls++;
      return jsonEncode([
        {...safeResult(ip), if (calls == 2) 'nxdomainHijacked': true},
      ]);
    });
    await pumpScreen(tester);
    await enter(
      tester,
      'Paste IPv4 addresses or CIDR ranges',
      '1.1.1.1 1.1.1.2 1.1.1.3',
    );
    await enter(tester, 'Workers (1–64)', '1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.text('Candidate resolvers (2)'), findsOneWidget);
  });

  testWidgets('copy all candidates copies safe IP:port endpoints', (
    tester,
  ) async {
    String? copied;
    final platform =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    platform.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') {
        return jsonEncode([
          safeResult('1.1.1.1'),
          {...safeResult('1.1.1.2'), 'nxdomainHijacked': true},
        ]);
      }
      return null;
    });
    await pumpScreen(tester);
    await enter(
      tester,
      'Paste IPv4 addresses or CIDR ranges',
      '1.1.1.1 1.1.1.2',
    );
    await enter(tester, 'Port', '853');
    await start(tester);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Copy all candidates'));
    await tester.tap(find.text('Copy all candidates'));
    await tester.pump();
    expect(copied, '1.1.1.1:853\n');
    platform.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('exports UTF8 bytes and stable metadata', (tester) async {
    final fake = _FakeFilePicker()..nextPath = '/tmp/dns-candidates-test.txt';
    FilePicker.platform = fake;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') return jsonEncode([safeResult('1.1.1.1')]);
      return null;
    });
    await pumpScreen(tester);
    await enter(tester, 'Test domain or IPv4', 'Example.COM');
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await enter(tester, 'Port', '853');
    await enter(tester, 'Timeout ms', '4000');
    await enter(tester, 'Workers (1–64)', '2');
    await start(tester);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Export TXT'));
    await tester.tap(find.text('Export TXT'));
    await tester.pumpAndSettle();
    expect(utf8.decode(fake.savedBytes!), '1.1.1.1:853\n');
    await enter(tester, 'Test domain or IPv4', '8.8.8.8');
    await enter(tester, 'Port', '5353');
    await enter(tester, 'Timeout ms', '600');
    await enter(tester, 'Workers (1–64)', '8');
    fake.nextPath = '/tmp/dns-candidates-test.json';
    await reveal(tester, find.text('Export JSON'));
    await tester.tap(find.text('Export JSON'));
    await tester.pumpAndSettle();
    final data = jsonDecode(utf8.decode(fake.savedBytes!)) as Map;
    expect(data['testTarget'], 'example.com');
    expect(data['port'], 853);
    expect(data['timeoutMs'], 4000);
    expect(data['workers'], 2);
    expect(data['cancelled'], false);
    expect((data['resolvers'] as List).single['ip'], '1.1.1.1');
  });

  testWidgets('export cancel and exception show friendly feedback', (
    tester,
  ) async {
    final fake = _FakeFilePicker();
    FilePicker.platform = fake;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') return jsonEncode([safeResult('1.1.1.1')]);
      return null;
    });
    await pumpScreen(tester);
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await start(tester);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Export TXT'));
    await tester.tap(find.text('Export TXT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exported candidate resolvers'), findsNothing);
    fake.failure = StateError('disk full');
    await tester.tap(find.text('Export JSON'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not export candidate resolvers'),
      findsOneWidget,
    );
  });

  testWidgets('stop retains completed wave and starts no later waves', (
    tester,
  ) async {
    final pending = Completer<String>();
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      calls++;
      if (calls == 1) return jsonEncode([safeResult('1.1.1.1')]);
      return pending.future;
    });
    await pumpScreen(tester);
    await enter(
      tester,
      'Paste IPv4 addresses or CIDR ranges',
      '1.1.1.1 1.1.1.2 1.1.1.3',
    );
    await enter(tester, 'Workers (1–64)', '1');
    await start(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 2);
    await tester.tap(find.byTooltip('Stop'));
    pending.complete(jsonEncode([safeResult('1.1.1.2')]));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await reveal(tester, find.text('Candidate resolvers (1)'));
    expect(find.textContaining('Cancelled (partial results)'), findsOneWidget);
    expect(find.text('Candidate resolvers (1)'), findsOneWidget);
  });
}
