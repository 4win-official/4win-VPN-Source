import 'package:flutter/material.dart';
import '../services/update_service.dart';

/// دیالوگ نمایش آپدیت جدید - به کاربر می‌گوید نسخه جدید موجود است
/// و دکمه "دانلود میکنم" برای دانلود و نصب.
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.currentVersion,
  });

  /// نمایش دیالوگ آپدیت
  static Future<void> show(
    BuildContext context, {
    required UpdateInfo updateInfo,
    required String currentVersion,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        updateInfo: updateInfo,
        currentVersion: currentVersion,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _updateService = UpdateService();
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _error;

  Future<void> _startDownload() async {
    final apkUrl = widget.updateInfo.apkDownloadUrl;

    // اگر لینک مستقیم APK نبود، صفحه ریلیز را باز کن
    if (apkUrl == null || apkUrl.isEmpty) {
      setState(() {
        _error = 'Installer not found. Please download from the GitHub page.';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _error = null;
      _progress = 0.0;
    });

    final success = await _updateService.downloadAndInstallApk(
      apkUrl,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
    );

    if (!mounted) return;

    if (success) {
      // نصب شروع شد، دیالوگ را ببند
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isDownloading = false;
        _error = 'Download failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final accent = isDark ? const Color(0xFF00FF88) : Colors.blue;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.system_update, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'New update available',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your current version: ${widget.currentVersion}',
            style: TextStyle(color: subTextColor, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'New version: ${widget.updateInfo.latestVersion}',
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.updateInfo.releaseNotes != null) ...[
            Text(
              'Changes:',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  widget.updateInfo.releaseNotes!,
                  style: TextStyle(color: subTextColor, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
            const SizedBox(height: 8),
            Text(
              _progress > 0
                  ? 'Downloading... ${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Downloading...',
              style: TextStyle(color: subTextColor, fontSize: 13),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: _isDownloading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Later',
                  style: TextStyle(color: subTextColor),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _startDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.download, size: 18),
                label: const Text(
                  'Download',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
    );
  }
}
