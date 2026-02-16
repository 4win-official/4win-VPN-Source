import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/vpn_provider.dart';
import '../models/openvpn_config.dart';
import '../services/openvpn_service.dart';

class OpenVpnConfigsScreen extends StatefulWidget {
  const OpenVpnConfigsScreen({super.key});

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
      // انتخاب فایل .ovpn
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ovpn'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        // خواندن محتوای فایل
        String? configContent;
        if (file.bytes != null) {
          // Web platform
          configContent = String.fromCharCodes(file.bytes!);
        } else if (file.path != null) {
          // Mobile/Desktop platform
          final fileContent = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['ovpn'],
          );
          
          if (fileContent != null && fileContent.files.isNotEmpty) {
            final bytes = fileContent.files.first.bytes;
            if (bytes != null) {
              configContent = String.fromCharCodes(bytes);
            }
          }
        }

        if (configContent == null || configContent.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ Failed to read file content')),
            );
          }
          return;
        }

        // Validate config
        if (!OpenVpnService.validateConfig(configContent)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ Invalid OpenVPN config format')),
            );
          }
          return;
        }

        // استخراج نام از فایل یا محتوا
        String configName = file.name.replaceAll('.ovpn', '');
        if (configName.isEmpty) {
          configName = OpenVpnService.extractConfigName(configContent);
        }

        // نمایش دیالوگ برای username/password (اختیاری)
        await _showCredentialsDialog(configName, configContent);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error picking file: $e')),
        );
      }
    }
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
    // Save selected config
    await _service.setSelectedConfig(config.name);

    setState(() {
      _selectedConfigName = config.name;
    });

    // Connect using VpnProvider
    if (mounted) {
      final vpnProvider = Provider.of<VpnProvider>(context, listen: false);
      await vpnProvider.selectOpenVpnConfigAndConnect(config);

      Navigator.pop(context); // برگشت به صفحه اصلی
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
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDelete(config),
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
