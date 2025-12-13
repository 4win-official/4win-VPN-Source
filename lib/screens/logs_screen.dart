import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeLogStream();
  }

  void _initializeLogStream() {
    final provider = Provider.of<VpnProvider>(context, listen: false);
    
    // Listen to log stream
    provider.vpnService.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.add(log);
          
          // Keep only last 200 logs
          if (_logs.length > 200) {
            _logs.removeAt(0);
          }
        });
        
        // Auto-scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Connection Logs',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.black54),
            tooltip: 'Clear Logs',
            onPressed: () {
              setState(() {
                _logs.clear();
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Log info banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Real-time connection logs and status updates',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Logs list
            Expanded(
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 64,
                            color: Colors.black.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No logs yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connect to VPN to see logs',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final icon = _getLogIcon(log);
                        final color = _getLogColor(log);
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                icon,
                                size: 16,
                                color: color,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  log,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: Colors.black87,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
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

  IconData _getLogIcon(String log) {
    if (log.contains('✅')) return Icons.check_circle;
    if (log.contains('❌')) return Icons.cancel;
    if (log.contains('⚠️')) return Icons.warning;
    if (log.contains('🔄')) return Icons.sync;
    if (log.contains('📋')) return Icons.assignment;
    if (log.contains('🚀')) return Icons.rocket_launch;
    if (log.contains('🌐')) return Icons.language;
    if (log.contains('🔌')) return Icons.power;
    if (log.contains('📊')) return Icons.bar_chart;
    return Icons.fiber_manual_record;
  }

  Color _getLogColor(String log) {
    if (log.contains('✅')) return const Color(0xFF4CAF50);
    if (log.contains('❌')) return Colors.red;
    if (log.contains('⚠️')) return Colors.orange;
    if (log.contains('🔄')) return Colors.blue;
    return Colors.black54;
  }
}
