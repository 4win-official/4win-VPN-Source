import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/psiphon_provider.dart';
import '../services/psiphon_manager.dart';

class PsiphonScreen extends StatefulWidget {
  const PsiphonScreen({Key? key}) : super(key: key);

  @override
  State<PsiphonScreen> createState() => _PsiphonScreenState();
}

class _PsiphonScreenState extends State<PsiphonScreen> {
  late PsiphonProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<PsiphonProvider>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Psiphon VPN'),
        elevation: 0,
      ),
      body: Consumer<PsiphonProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection Status Card
                Card(
                  elevation: 4,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: provider.isConnected
                            ? [Colors.green[600]!, Colors.green[400]!]
                            : [Colors.grey[600]!, Colors.grey[400]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          provider.isConnected
                              ? Icons.vpn_lock
                              : Icons.vpn_lock_outlined,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          provider.connectionStatus,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (provider.isConnected) ...
                          [
                            Text(
                              'Region: ${provider.selectedRegion}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Connected for ${provider.formattedConnectionTime}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ]
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Traffic Stats
                if (provider.isConnected) ...
                  [
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_upward,
                                    color: Colors.blue[600],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('Upload'),
                                  const SizedBox(height: 8),
                                  Text(
                                    provider.formattedUplink,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    provider.formattedUploadSpeed,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_downward,
                                    color: Colors.red[600],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('Download'),
                                  const SizedBox(height: 8),
                                  Text(
                                    provider.formattedDownlink,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    provider.formattedDownloadSpeed,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                // Region Selector
                const Text(
                  'Select Region',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: provider.availableRegions.map((region) {
                    final isSelected =
                        provider.selectedRegion == region;
                    return FilterChip(
                      label: Text(region),
                      selected: isSelected,
                      onSelected: provider.isLoading || provider.isConnected
                          ? null
                          : (_) {
                              // Region selection logic
                            },
                      backgroundColor: Colors.grey[200],
                      selectedColor: Colors.blue[300],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Column(
                  children: [
                    if (!provider.isConnected)
                      ElevatedButton.icon(
                        onPressed: provider.isLoading
                            ? null
                            : () {
                                _provider.startConnection(
                                  provider.selectedRegion.isEmpty
                                      ? 'Auto'
                                      : provider.selectedRegion,
                                );
                              },
                        icon: provider.isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.vpn_lock),
                        label: Text(
                          provider.isLoading ? 'Connecting...' : 'Connect',
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      )
                    else
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: provider.isLoading
                                ? null
                                : () {
                                    _provider.stopConnection();
                                  },
                            icon: const Icon(Icons.vpn_lock_off),
                            label: const Text('Disconnect'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: provider.isLoading
                                ? null
                                : () {
                                    _provider.reconnectConnection(
                                      provider.selectedRegion,
                                    );
                                  },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reconnect'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                // Error Message
                if (provider.error != null) ...
                  [
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error,
                            color: Colors.red[700],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              provider.error!,
                              style: TextStyle(
                                color: Colors.red[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}
