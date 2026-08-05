import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';
import '../providers/vpn_provider.dart';
import '../models/openvpn_config.dart';
import '../services/openvpn_service.dart';

class OpenVpnConfigsScreen extends StatefulWidget {
  /// When opened as a result of the user tapping/sharing an `.ovpn` file, these
  /// carry the imported file's name and content so the screen can immediately
  /// offer to add it (no manual file picking needed).
  final String? initialImportName;
  final String? initialImportContent;

  const OpenVpnConfigsScreen({
    super.key,
    this.initialImportName,
    this.initialImportContent,
  });

  @override
  State<OpenVpnConfigsScreen> createState() => _OpenVpnConfigsScreenState();
}

class _OpenVpnConfigsScreenState extends State<OpenVpnConfigsScreen> {
  final OpenVpnService _service = OpenVpnService();
  List<OpenVpnConfig> _configs = [];
  bool _isLoading = true;
  String? _selectedConfigName;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
    // If we were launched from an .ovpn file, kick off the import flow once the
    // first frame is drawn.
    final content = widget.initialImportContent;
    if (content != null && content.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startImportFromContent(
          widget.initialImportName ?? 'Imported',
          content,
        );
      });
    }
  }

  /// Imports an .ovpn whose content we already have (from a VIEW/SEND intent).
  Future<void> _startImportFromContent(
      String suggestedName, String configContent) async {
    String configName = suggestedName
        .replaceAll('.ovpn', '')
        .replaceAll('.conf', '')
        .replaceAll('.open', '')
        .trim();
    if (configName.isEmpty) {
      configName = OpenVpnService.extractConfigName(configContent);
    }

    final parsedInfo = OpenVpnConfig.parseConfigFile(configContent);
    final hasEmbeddedCredentials =
        parsedInfo['username'] != null && parsedInfo['username']!.isNotEmpty;

    if (hasEmbeddedCredentials) {
      await _showSimpleNameDialog(configName, configContent);
    } else {
      await _showCredentialsDialog(configName, configContent);
    }
  }

  Future<void> _loadConfigs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final configs = await _service.loadConfigs();
      final selectedName = await _service.getSelectedConfigName();

      setState(() {
        _configs = configs;
        _selectedConfigName = selectedName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load configs: $e')),
        );
      }
    }
  }

  Future<void> _pickAndAddConfigFile() async {
    try {
      // انتخاب فایل - استفاده از FileType.any برای پشتیبانی از تمام فرمت‌ها
      // فرمت‌های پشتیبانی شده: .ovpn, .conf, .open
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // استفاده از any برای جلوگیری از محدودیت extension
        allowMultiple: false,
        withData: true, // خواندن bytes به‌صورت خودکار
      );

      if (result == null || result.files.isEmpty) {
        // کاربر انتخاب را کنسل کرد
        return;
      }

      final file = result.files.first;
      
      // بررسی extension فایل (manual check)
      final fileName = file.name.toLowerCase();
      if (!fileName.endsWith('.ovpn') && 
          !fileName.endsWith('.conf') && 
          !fileName.endsWith('.open')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Invalid file format. Please select .ovpn, .conf, or .open file'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // خواندن محتوای فایل
      String? configContent;
      
      try {
        if (file.bytes != null) {
          // Web platform یا withData: true
          configContent = String.fromCharCodes(file.bytes!);
        } else if (file.path != null) {
          // Mobile/Desktop platform - fallback
          final fileBytes = await FilePicker.platform.pickFiles(
            type: FileType.any,
            withData: true,
          );
          
          if (fileBytes != null && fileBytes.files.isNotEmpty && fileBytes.files.first.bytes != null) {
            configContent = String.fromCharCodes(fileBytes.files.first.bytes!);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Failed to read file: $e')),
          );
        }
        return;
      }

      if (configContent == null || configContent.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ File is empty or unreadable')),
          );
        }
        return;
      }

      // Validate config
      if (!OpenVpnService.validateConfig(configContent)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Invalid OpenVPN config format. Missing required fields (client, remote, dev)'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // استخراج نام از فایل
      String configName = file.name
          .replaceAll('.ovpn', '')
          .replaceAll('.conf', '')
          .replaceAll('.open', '')
          .trim();
      
      if (configName.isEmpty) {
        configName = OpenVpnService.extractConfigName(configContent);
      }

      // ✅ بررسی اینکه آیا credentials در فایل است یا نه
      final parsedInfo = OpenVpnConfig.parseConfigFile(configContent);
      final hasEmbeddedCredentials = parsedInfo['username'] != null && parsedInfo['username']!.isNotEmpty;
      
      if (hasEmbeddedCredentials) {
        // ✅ Credentials در فایل است - مستقیم اضافه می‌کنیم
        if (kDebugMode) {
          debugPrint('✅ Credentials found in config file');
          debugPrint('   Username: ${parsedInfo['username']}');
        }
        
        // نمایش دیالوگ فقط برای تایید نام
        await _showSimpleNameDialog(configName, configContent);
      } else {
        // ❌ Credentials در فایل نیست - از کاربر بپرس
        if (kDebugMode) {
          debugPrint('⚠️ No credentials in config file - requesting from user');
        }
        
        await _showCredentialsDialog(configName, configContent);
      }
      
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Platform error: ${e.message ?? e.code}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// نمایش دیالوگ ساده فقط برای نام (وقتی credentials در فایل است)
  Future<void> _showSimpleNameDialog(String configName, String configContent) async {
    final nameController = TextEditingController(text: configName);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Config'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            const Text(
              '✅ Credentials found in config file',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Config Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();

              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name is required')),
                );
                return;
              }

              // ✅ Config با credentials embedded
              final newConfig = OpenVpnConfig(
                name: name,
                config: configContent,
                username: null, // خودکار از فایل extract می‌شود
                password: null, // خودکار از فایل extract می‌شود
              );

              final success = await _service.addConfig(newConfig);

              if (mounted) {
                Navigator.pop(context);

                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Config added successfully with embedded credentials'),
                    ),
                  );
                  _loadConfigs();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Failed to add config (name may already exist)'),
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCredentialsDialog(String configName, String configContent) async {
    final nameController = TextEditingController(text: configName);
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Config Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Config Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password (Optional)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name is required')),
                  );
                  return;
                }

                final newConfig = OpenVpnConfig(
                  name: name,
                  config: configContent,
                  username: usernameController.text.trim().isEmpty
                      ? null
                      : usernameController.text.trim(),
                  password: passwordController.text.trim().isEmpty
                      ? null
                      : passwordController.text.trim(),
                );

                final success = await _service.addConfig(newConfig);

                if (mounted) {
                  Navigator.pop(context);

                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Config added successfully'),
                      ),
                    );
                    _loadConfigs();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('❌ Failed to add config (name may already exist)'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddConfigDialog() async {
    final nameController = TextEditingController();
    final configController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add OpenVPN Config'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Config Name',
                    hintText: 'My VPN Server',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: configController,
                  decoration: InputDecoration(
                    labelText: 'Config File Content (.ovpn)',
                    hintText: 'Paste your .ovpn file content here',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      onPressed: () async {
                        final clipboardData =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        if (clipboardData != null &&
                            clipboardData.text != null) {
                          configController.text = clipboardData.text!;
                          
                          // Auto-extract name if empty
                          if (nameController.text.isEmpty) {
                            final extractedName =
                                OpenVpnService.extractConfigName(
                                    clipboardData.text!);
                            nameController.text = extractedName;
                          }
                        }
                      },
                      tooltip: 'Paste from clipboard',
                    ),
                  ),
                  maxLines: 6,
                  minLines: 3,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password (Optional)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final config = configController.text.trim();

                if (name.isEmpty || config.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name and config are required'),
                    ),
                  );
                  return;
                }

                // Validate config
                if (!OpenVpnService.validateConfig(config)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid OpenVPN config format'),
                    ),
                  );
                  return;
                }

                final newConfig = OpenVpnConfig(
                  name: name,
                  config: config,
                  username: usernameController.text.trim().isEmpty
                      ? null
                      : usernameController.text.trim(),
                  password: passwordController.text.trim().isEmpty
                      ? null
                      : passwordController.text.trim(),
                );

                final success = await _service.addConfig(newConfig);

                if (mounted) {
                  Navigator.pop(context);

                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Config added successfully'),
                      ),
                    );
                    _loadConfigs();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('❌ Failed to add config (name may already exist)'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(OpenVpnConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Config'),
        content: Text('Are you sure you want to delete "${config.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _service.removeConfig(config.name);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Config deleted successfully'),
            ),
          );
          _loadConfigs();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Failed to delete config'),
            ),
          );
        }
      }
    }
  }

  Future<void> _selectAndConnect(OpenVpnConfig config) async {
    // Save selected config.
    await _service.setSelectedConfig(config.name);

    if (!mounted) return;
    setState(() {
      _selectedConfigName = config.name;
    });

    final vpnProvider = Provider.of<VpnProvider>(context, listen: false);

    // Only SELECT the config — do NOT auto-connect and do NOT leave the list.
    // ignore: discarded_futures
    unawaited(vpnProvider.selectOpenVpnConfig(config));
  }

  /// تست ping به سرور OpenVPN (استفاده از Socket)
  Future<void> _testPing(OpenVpnConfig config) async {
    if (config.serverAddress == null || config.serverAddress!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ No server address found in config')),
        );
      }
      return;
    }

    // نمایش دیالوگ loading
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Testing connection...'),
          ],
        ),
      ),
    );

    try {
      final serverAddress = config.serverAddress!;
      final serverPort = int.tryParse(config.serverPort ?? '1194') ?? 1194;
      
      final stopwatch = Stopwatch()..start();
      
      // ✅ استفاده از Socket.connect برای تست TCP connection
      // این روش برای OpenVPN سرورها کار می‌کند
      Socket? socket;
      
      try {
        socket = await Socket.connect(
          serverAddress,
          serverPort,
          timeout: const Duration(seconds: 5),
        );
        
        stopwatch.stop();
        final pingMs = stopwatch.elapsedMilliseconds;
        
        // ✅ اتصال موفق
        if (mounted) {
          Navigator.pop(context); // بستن loading dialog
          
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Connection Test'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✅ Server is reachable',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Server: $serverAddress'),
                  Text('Port: $serverPort'),
                  const SizedBox(height: 8),
                  Text(
                    '⚡ Response Time: ${pingMs}ms',
                    style: TextStyle(
                      color: pingMs < 100 
                          ? Colors.green 
                          : pingMs < 300 
                              ? Colors.orange 
                              : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pingMs < 100 
                        ? '🟢 Excellent connection'
                        : pingMs < 300 
                            ? '🟡 Good connection'
                            : '🔴 Slow connection',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        
      } on SocketException catch (e) {
        stopwatch.stop();
        
        // ❌ اتصال ناموفق
        if (mounted) {
          Navigator.pop(context); // بستن loading dialog
          
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Connection Test'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '❌ Cannot reach server',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Server: $serverAddress'),
                  Text('Port: $serverPort'),
                  const SizedBox(height: 8),
                  Text(
                    'Error: ${e.message}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '💡 This might be due to:\n'
                      '• Server is down\n'
                      '• Firewall blocking connection\n'
                      '• Wrong port number\n'
                      '• Internet connection issue',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } on TimeoutException {
        stopwatch.stop();
        
        if (mounted) {
          Navigator.pop(context);
          
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.timer_off, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Connection Test'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⏱️ Connection timeout',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Server: $serverAddress'),
                  Text('Port: $serverPort'),
                  const SizedBox(height: 12),
                  const Text(
                    'Server did not respond within 5 seconds. It might be slow or unreachable.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } finally {
        socket?.close();
      }
      
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Test failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
      appBar: AppBar(
        title: const Text('OpenVPN Configs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _pickAndAddConfigFile,
            tooltip: 'Add .ovpn File',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.vpn_key_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No OpenVPN configs',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap upload icon to add .ovpn file',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _configs.length,
                  itemBuilder: (context, index) {
                    final config = _configs[index];
                    final isSelected = config.name == _selectedConfigName;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: isSelected ? 4 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isSelected
                            ? const BorderSide(
                                color: Colors.purple,
                                width: 2,
                              )
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              Colors.purple.withOpacity(0.2),
                          child: const Icon(
                            Icons.vpn_key,
                            color: Colors.purple,
                          ),
                        ),
                        title: Text(
                          config.name,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              '${config.serverAddress ?? 'Unknown'}:${config.serverPort ?? '?'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              'Protocol: ${config.protocol?.toUpperCase() ?? 'UDP'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (config.username != null)
                              Text(
                                'Auth: ${config.username}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Selected',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            // 🔧 دکمه Ping Test
                            IconButton(
                              icon: const Icon(Icons.speed, color: Colors.blue),
                              onPressed: () => _testPing(config),
                              tooltip: 'Test Ping',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDelete(config),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                        onTap: () => _selectAndConnect(config),
                      ),
                    );
                  },
                ),
    );
  }
}
