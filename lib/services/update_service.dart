import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// نتیجه بررسی آپدیت
class UpdateInfo {
  final String latestVersion; // مثلا "1.4.2" (بدون v)
  final String tagName; // مثلا "v1.4.2"
  final String releaseUrl; // لینک صفحه ریلیز
  final String? apkDownloadUrl; // لینک مستقیم دانلود فایل APK
  final String? releaseNotes; // توضیحات ریلیز

  UpdateInfo({
    required this.latestVersion,
    required this.tagName,
    required this.releaseUrl,
    this.apkDownloadUrl,
    this.releaseNotes,
  });
}

/// سرویس بررسی و دانلود آپدیت از طریق GitHub Releases
///
/// ریپوی ریلیزها: 4win-official/4win-VPN  (دقت: این با ریپوی سورس فرق داره)
/// تگ‌ها به شکل v1.4.2 هستند.
class UpdateService {
  // مهم: ریپوی ریلیزها 4win-VPN است نه 4win-VPN-Source
  static const String _owner = '4win-official';
  static const String _repo = '4win-VPN';

  static const String _latestApiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  static const String releasesPageUrl =
      'https://github.com/$_owner/$_repo/releases';

  /// گرفتن نسخه فعلی اپ (مثلا "1.4.4")
  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      debugPrint('UpdateService: failed to read current version: $e');
      return '0.0.0';
    }
  }

  /// بررسی اینکه آیا نسخه جدیدتری موجود است یا نه.
  /// اگر آپدیت جدیدی باشد UpdateInfo برمی‌گرداند، در غیر این صورت null.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final currentVersion = await getCurrentVersion();

      final response = await http.get(
        Uri.parse(_latestApiUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': '4win-VPN-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('UpdateService: GitHub API returned ${response.statusCode}');
        return null;
      }

      final Map<String, dynamic> data = json.decode(response.body);

      final String tagName = (data['tag_name'] ?? '').toString();
      if (tagName.isEmpty) return null;

      // نسخه را از تگ استخراج کن (v1.4.2 -> 1.4.2)
      final String latestVersion = _normalizeVersion(tagName);

      // پیدا کردن لینک مستقیم فایل APK از assets
      String? apkUrl;
      final assets = data['assets'];
      if (assets is List) {
        for (final asset in assets) {
          final name = (asset['name'] ?? '').toString().toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = (asset['browser_download_url'] ?? '').toString();
            // ترجیح فایل universal اگر چند تا apk بود
            if (name.contains('universal') || name.contains('all')) {
              break;
            }
          }
        }
      }

      final releaseUrl = (data['html_url'] ?? '$releasesPageUrl/tag/$tagName')
          .toString();
      final notes = (data['body'] ?? '').toString();

      // مقایسه نسخه‌ها
      if (_isNewerVersion(latestVersion, currentVersion)) {
        return UpdateInfo(
          latestVersion: latestVersion,
          tagName: tagName,
          releaseUrl: releaseUrl,
          apkDownloadUrl: apkUrl,
          releaseNotes: notes.isEmpty ? null : notes,
        );
      }

      // نسخه جدیدی نیست
      return null;
    } catch (e) {
      debugPrint('UpdateService: checkForUpdate error: $e');
      return null;
    }
  }

  /// دانلود فایل APK و سپس باز کردن آن برای نصب.
  /// onProgress مقدار 0.0 تا 1.0 را گزارش می‌دهد.
  /// در صورت موفقیت true برمی‌گرداند.
  Future<bool> downloadAndInstallApk(
    String apkUrl, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        debugPrint('UpdateService: download failed ${response.statusCode}');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/4win_vpn_update.apk';
      final file = File(filePath);

      // اگر فایل قبلی هست پاکش کن
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }

      await sink.flush();
      await sink.close();

      // باز کردن APK برای نصب (intent نصب اندروید را باز می‌کند)
      final result = await OpenFilex.open(filePath);
      debugPrint(
          'UpdateService: open APK result: ${result.type} ${result.message}');

      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('UpdateService: downloadAndInstallApk error: $e');
      return false;
    }
  }

  /// تبدیل تگ به نسخه عددی (v1.4.2 -> 1.4.2)
  String _normalizeVersion(String tag) {
    var v = tag.trim();
    if (v.toLowerCase().startsWith('v')) {
      v = v.substring(1);
    }
    return v;
  }

  /// آیا [candidate] از [current] جدیدتر است؟ (مقایسه semantic مثل 1.4.10 > 1.4.9)
  bool _isNewerVersion(String candidate, String current) {
    final c = _parseVersion(candidate);
    final cur = _parseVersion(current);

    final len = c.length > cur.length ? c.length : cur.length;
    for (int i = 0; i < len; i++) {
      final a = i < c.length ? c[i] : 0;
      final b = i < cur.length ? cur[i] : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false; // برابرند
  }

  /// پارس کردن نسخه به لیست اعداد ("1.4.2" -> [1,4,2])
  List<int> _parseVersion(String version) {
    // فقط بخش قبل از + را بگیر (مثلا build number را حذف کن)
    var v = version.split('+').first.trim();
    return v
        .split('.')
        .map((part) =>
            int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}
