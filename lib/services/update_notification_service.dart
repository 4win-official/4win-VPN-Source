import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_service.dart';

class UpdateNotificationLaunch {
  const UpdateNotificationLaunch({
    required this.updateInfo,
    required this.currentVersion,
  });

  final UpdateInfo updateInfo;
  final String currentVersion;
}

/// Bridges update notifications and their action back to the Android app.
class UpdateNotificationService {
  UpdateNotificationService({@visibleForTesting bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  final bool _isAndroid;
  static const MethodChannel _channel = MethodChannel(
    'com.forwin.vpn/update_notifications',
  );
  static const String _lastNotifiedTagKey = 'last_update_notification_tag';
  static const String _notificationsEnabledKey =
      'update_notifications_enabled';
  static const String _consentPromptedKey =
      'update_notification_consent_prompted';

  Future<bool> shouldPromptForConsent() async {
    if (!_isAndroid) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_consentPromptedKey) != true;
  }

  Future<void> markConsentPrompted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_consentPromptedKey, true);
  }

  /// Call only after the user opts in inside the app or explicitly enables the
  /// setting. This is the only place that requests Android notification access.
  Future<bool> enableNotificationsAfterConsent() async {
    if (!_isAndroid) return false;

    try {
      var permission = await Permission.notification.status;
      if (!permission.isGranted) {
        permission = await Permission.notification.request();
      }
      final enabled = permission.isGranted;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_notificationsEnabledKey, enabled);
      return enabled;
    } catch (error) {
      debugPrint(
        'Update notification permission could not be requested: $error',
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_notificationsEnabledKey, false);
      return false;
    }
  }

  Future<void> disableNotifications() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_notificationsEnabledKey, false);
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancelUpdateNotification');
    } on PlatformException catch (error) {
      debugPrint('Update notification could not be cleared: ${error.message}');
    }
  }

  Future<bool> areNotificationsEnabled() async {
    if (!_isAndroid) return false;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_notificationsEnabledKey) != true) {
      return false;
    }
    return (await Permission.notification.status).isGranted;
  }

  Future<void> showAvailableUpdate({
    required UpdateInfo updateInfo,
    required String currentVersion,
  }) async {
    if (!_isAndroid) return;

    try {
      if (!await areNotificationsEnabled()) return;

      final preferences = await SharedPreferences.getInstance();
      if (preferences.getString(_lastNotifiedTagKey) == updateInfo.tagName) {
        return;
      }

      final shown = await _channel
          .invokeMethod<bool>('showUpdateNotification', <String, Object?>{
            'latestVersion': updateInfo.latestVersion,
            'tagName': updateInfo.tagName,
            'currentVersion': currentVersion,
            'releaseUrl': updateInfo.releaseUrl,
            'apkDownloadUrl': updateInfo.apkDownloadUrl,
            'releaseNotes': updateInfo.releaseNotes,
          });
      if (shown == true) {
        await preferences.setString(_lastNotifiedTagKey, updateInfo.tagName);
      }
    } on PlatformException catch (error) {
      debugPrint('Update notification could not be shown: ${error.message}');
    } catch (error) {
      debugPrint('Update notification could not be shown: $error');
    }
  }

  /// Registers the callback used when a notification is tapped while the app is open.
  void setUpdateSelectedHandler(Future<void> Function()? handler) {
    if (!_isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onUpdateNotificationSelected') {
        await handler?.call();
      }
    });
  }

  /// Consumes update data attached to either a cold-start or warm-start intent.
  Future<UpdateNotificationLaunch?> consumePendingUpdate() async {
    if (!_isAndroid) return null;

    try {
      final payload = await _channel.invokeMapMethod<String, dynamic>(
        'consumePendingUpdate',
      );
      if (payload == null) return null;

      final latestVersion = (payload['latestVersion'] ?? '').toString();
      if (latestVersion.isEmpty) return null;

      final tagName = (payload['tagName'] ?? 'v$latestVersion').toString();
      final releaseUrl =
          (payload['releaseUrl'] ?? UpdateService.releasesPageUrl).toString();
      final apkDownloadUrl = payload['apkDownloadUrl']?.toString();
      final releaseNotes = payload['releaseNotes']?.toString();

      return UpdateNotificationLaunch(
        currentVersion: (payload['currentVersion'] ?? '').toString(),
        updateInfo: UpdateInfo(
          latestVersion: latestVersion,
          tagName: tagName,
          releaseUrl: releaseUrl,
          apkDownloadUrl: apkDownloadUrl,
          releaseNotes: releaseNotes?.isEmpty == true ? null : releaseNotes,
        ),
      );
    } on PlatformException catch (error) {
      debugPrint('Could not read update notification launch: ${error.message}');
      return null;
    } catch (error) {
      debugPrint('Could not read update notification launch: $error');
      return null;
    }
  }
}
