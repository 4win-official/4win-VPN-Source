import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/secret_text_cipher.dart';

/// Secret Text tool — turns any text into a 4win-only encoded string and back.
///
/// Two panels:
///   • Encrypt: plain text  → 4win secret string (share this)
///   • Decrypt: 4win secret → original plain text (only this app can do it)
class SecretTextScreen extends StatefulWidget {
  const SecretTextScreen({super.key});

  @override
  State<SecretTextScreen> createState() => _SecretTextScreenState();
}

class _SecretTextScreenState extends State<SecretTextScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  final _plainIn = TextEditingController();
  final _secretOut = TextEditingController();
  final _secretIn = TextEditingController();
  final _plainOut = TextEditingController();
  String? _decodeError;

  static const Color _accent = Color(0xFF6C4CE0); // purple

  @override
  void dispose() {
    _tab.dispose();
    _plainIn.dispose();
    _secretOut.dispose();
    _secretIn.dispose();
    _plainOut.dispose();
    super.dispose();
  }

  void _encrypt() {
    final out = SecretTextCipher.encode(_plainIn.text);
    setState(() => _secretOut.text = out);
  }

  void _decrypt() {
    try {
      final out = SecretTextCipher.decode(_secretIn.text);
      setState(() {
        _plainOut.text = out;
        _decodeError = null;
      });
    } catch (e) {
      setState(() {
        _plainOut.text = '';
        _decodeError = e is FormatException ? e.message : 'Could not decode';
      });
    }
  }

  Future<void> _copy(String text, String label) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _paste(TextEditingController c) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      c.text = data!.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secret Text'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.lock_outline), text: 'Encrypt'),
            Tab(icon: Icon(Icons.lock_open_outlined), text: 'Decrypt'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildEncryptTab(isDark),
          _buildDecryptTab(isDark),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _accent),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  InputDecoration _dec(bool isDark, String hint) => InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: isDark ? Colors.white10 : Colors.white,
      );

  Widget _buildEncryptTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Your text', Icons.edit_outlined),
          const SizedBox(height: 8),
          TextField(
            controller: _plainIn,
            maxLines: 6,
            minLines: 4,
            onChanged: (_) => _encrypt(),
            decoration: _dec(isDark, 'Type any text to encrypt…'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _paste(_plainIn).then((_) => _encrypt()),
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _encrypt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.enhanced_encryption),
                label: const Text('Encrypt'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionLabel('4win secret (share this)', Icons.vpn_key_outlined),
          const SizedBox(height: 8),
          TextField(
            controller: _secretOut,
            maxLines: 6,
            minLines: 4,
            readOnly: true,
            style: const TextStyle(
                fontFamily: 'monospace', letterSpacing: 0.5),
            decoration: _dec(isDark, 'Encrypted output appears here…'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () => _copy(_secretOut.text, 'Secret'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent.withValues(alpha: 0.15),
                foregroundColor: _accent,
                elevation: 0,
              ),
              icon: const Icon(Icons.copy),
              label: const Text('Copy secret'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only 4win VPN can decode this. Anyone without the app just sees gibberish.',
            style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildDecryptTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('4win secret', Icons.vpn_key_outlined),
          const SizedBox(height: 8),
          TextField(
            controller: _secretIn,
            maxLines: 6,
            minLines: 4,
            onChanged: (_) => _decrypt(),
            style: const TextStyle(
                fontFamily: 'monospace', letterSpacing: 0.5),
            decoration: _dec(isDark, 'Paste a 4win secret (4W~…)'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _paste(_secretIn).then((_) => _decrypt()),
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _decrypt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.no_encryption_outlined),
                label: const Text('Decrypt'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionLabel('Original text', Icons.subject),
          const SizedBox(height: 8),
          TextField(
            controller: _plainOut,
            maxLines: 6,
            minLines: 4,
            readOnly: true,
            decoration: _dec(isDark, 'Decoded text appears here…').copyWith(
              errorText: _decodeError,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () => _copy(_plainOut.text, 'Text'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent.withValues(alpha: 0.15),
                foregroundColor: _accent,
                elevation: 0,
              ),
              icon: const Icon(Icons.copy),
              label: const Text('Copy text'),
            ),
          ),
        ],
      ),
    );
  }
}
