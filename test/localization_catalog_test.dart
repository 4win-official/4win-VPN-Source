import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/l10n/app_localizations.dart';

void main() {
  test(
    'English preserves the app\'s existing copy and Persian translates it',
    () {
      final english = AppLocalizations(const Locale('en'));
      final persian = AppLocalizations(const Locale('fa'));

      expect(english.text('Settings'), 'Settings');
      expect(persian.text('Settings'), 'تنظیمات');
      expect(persian.text('Connecting...'), 'در حال اتصال...');
    },
  );

  test('dynamic UI templates preserve values and unknown user data', () {
    final persian = AppLocalizations(const Locale('fa'));

    expect(
      persian.text('Invalid IP or CIDR: 192.0.2.1'),
      'IP یا CIDR نامعتبر: 192.0.2.1',
    );
    expect(persian.text('Connected to FR'), 'به FR متصل شد');
    expect(
      persian.text('Download: 12.4 KB/s • Upload: 1.1 KB/s'),
      'دریافت: 12.4 KB/s • ارسال: 1.1 KB/s',
    );
    expect(
      persian.text('A user-provided server name'),
      'A user-provided server name',
    );
  });
}
