import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/services/update_service.dart';

void main() {
  test('checks the 4win-VPN-Source releases repository', () {
    expect(
      UpdateService.latestReleaseApiUrl,
      'https://api.github.com/repos/4win-official/4win-VPN-Source/releases/latest',
    );
    expect(
      UpdateService.releasesPageUrl,
      'https://github.com/4win-official/4win-VPN-Source/releases',
    );
  });
}
