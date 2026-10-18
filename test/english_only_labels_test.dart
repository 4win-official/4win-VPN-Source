import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// User-entered/imported data is intentionally not covered by this check. It
/// audits only string literals shipped in the app's Dart source, with comments
/// ignored so implementation notes can use any language.
void main() {
  test('shipped app string literals are English-only', () {
    final libDirectory = Directory('lib');
    final arabicScript = RegExp(r'[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff]');
    final stringLiteral = RegExp(
      r'''(?:'([^'\\]*(?:\\.[^'\\]*)*)'|"([^"\\]*(?:\\.[^"\\]*)*)")''',
    );
    final offenders = <String>[];

    for (final entity in libDirectory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var lineNumber = 0; lineNumber < lines.length; lineNumber++) {
        final code = lines[lineNumber].replaceFirst(RegExp(r'//.*$'), '');
        for (final match in stringLiteral.allMatches(code)) {
          final literal = match.group(1) ?? match.group(2) ?? '';
          if (arabicScript.hasMatch(literal)) {
            offenders.add('${entity.path}:${lineNumber + 1}: $literal');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
