import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/xray_config.dart';
import '../services/xray_service.dart';
import '../providers/vpn_provider.dart';

class XrayConfigsScreen extends StatefulWidget {
  const XrayConfigsScreen({super.key});

  @override
  State<XrayConfigsScreen> createState() => _XrayConfigsScreenState();
}

class _XrayConfigsScreenState extends State<XrayConfigsScreen> {
  final XrayService _xrayService = XrayService();
  List<XrayConfig> _configs = [];
  bool _isLoading = true;
  bool _isTesting = false;
  String? _errorMessage;
  int _testedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final configs = await _xrayService.fetchConfigs(forceRefresh: forceRefresh);
      setState(() {
        _configs = configs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load configs: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _testAllConfigs() async {
    if (_configs.isEmpty) return;

    setState(() {
      _isTesting = true;
      _testedCount = 0;
      _totalCount = _configs.length;
    });

    try {
      final testedConfigs = await _xrayService.testConfigsInParallel(
        _configs,
        onProgress: (tested, total) {
          setState(() {
            _testedCount = tested;
            _totalCount = total;
          });
        },
      );

      setState(() {
        _configs = testedConfigs;
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    }
  }

  Future<void> _showAddCustomConfigDialog() async {
    final TextEditingController configController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          title: Text(
            'Add Custom Config',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste your Xray config link:',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: configController,
                  maxLines: 4,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'vless://...\nvmess://...\ntrojan://...\nss://...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                      fontSize: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: isDark ? Colors.purple[300]! : Colors.purple,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final configText = configController.text.trim();
                if (configText.isEmpty) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a config')),
                  );
                  return;
                }

                try {
                  // Parse custom config using auto-detect
                  final customConfig = XrayConfig.fromString(configText);
                  
                  // Add custom config via VpnProvider
                  final vpnProvider = Provider.of<VpnProvider>(context, listen: false);
                  await vpnProvider.addCustomXrayConfig(customConfig);
                  
                  Navigator.of(context).pop();
                  
                  // Reload configs
                  await _loadConfigs(forceRefresh: true);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Custom config added successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  Navigator.of(context).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to add config: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Color _getPingColor(int ping) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (ping < 100) {
      return isDark ? const Color(0xFF00FF88) : Colors.green;
    } else if (ping < 200) {
      return isDark ? const Color(0xFF88FF44) : Colors.lightGreen;
    } else if (ping < 400) {
      return isDark ? const Color(0xFFFF9944) : Colors.orange;
    } else {
      return isDark ? const Color(0xFFFF4466) : Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      appBar: AppBar(
        title: const Text('Xray Configs'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddCustomConfigDialog(),
            tooltip: 'Add Custom Config',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || _isTesting ? null : () => _loadConfigs(forceRefresh: true),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Test All Button
            if (_configs.isNotEmpty && !_isLoading)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testAllConfigs,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.speed),
                    label: Text(
                      _isTesting 
                          ? 'Testing... $_testedCount/$_totalCount'
                          : 'Test All Configs',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

            // Configs List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _loadConfigs(forceRefresh: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _configs.isEmpty
                          ? const Center(child: Text('No configs found'))
                          : ListView.builder(
                              itemCount: _configs.length,
                              itemBuilder: (context, index) {
                                final config = _configs[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  color: isDark 
                                      ? const Color(0xFF1A1A1A)
                                      : Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: config.protocol == 'vless'
                                          ? Colors.purple.withValues(alpha: 0.2)
                                          : Colors.blue.withValues(alpha: 0.2),
                                      child: Icon(
                                        Icons.shield_outlined,
                                        color: config.protocol == 'vless' 
                                            ? Colors.purple 
                                            : Colors.blue,
                                      ),
                                    ),
                                    title: Text(
                                      config.remark,
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          '${config.protocol.toUpperCase()} • ${config.address}:${config.port}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (config.network != null)
                                          Text(
                                            'Network: ${config.network}${config.security != null ? " • ${config.security}" : ""}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white38 : Colors.black38,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (config.ping != null)
                                          Text(
                                            '${config.ping}ms',
                                            style: TextStyle(
                                              color: _getPingColor(config.ping!),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          )
                                        else
                                          Text(
                                            'N/A',
                                            style: TextStyle(
                                              color: isDark ? Colors.white38 : Colors.black38,
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () async {
                                      final provider = Provider.of<VpnProvider>(context, listen: false);
                                      
                                      // Select config and connect
                                      await provider.selectXrayConfigAndConnect(config);
                                      
                                      // Close screen
                                      if (mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
