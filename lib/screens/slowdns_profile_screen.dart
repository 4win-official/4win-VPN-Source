import 'dart:convert';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

import '../models/slowdns_config.dart';
import 'dns_scanner_screen.dart';

/// A DNSTT profile editor. Unsupported engine settings are never saved as if
/// they worked; resolver scanning only supplies plaintext UDP endpoints.
class SlowDnsProfileScreen extends StatefulWidget {
  const SlowDnsProfileScreen({super.key, this.onSave});

  final Future<bool> Function(SlowDnsConfig)? onSave;

  @override
  State<SlowDnsProfileScreen> createState() => _SlowDnsProfileScreenState();
}

class _SlowDnsProfileScreenState extends State<SlowDnsProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _domain = TextEditingController();
  final _key = TextEditingController();
  final _resolver = TextEditingController();
  final _doh = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fallback = TextEditingController();
  String _transport = 'udp';
  bool _showPassword = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _domain,
      _key,
      _resolver,
      _doh,
      _username,
      _password,
      _fallback,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _defaultPort => _transport == 'dot' ? 853 : 53;

  Future<void> _scan() async {
    final current = SlowDnsConfig.parseResolverAddress(
      _resolver.text,
      defaultPort: _defaultPort,
    );
    var selectedPort = current?.port ?? _defaultPort;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DnsScannerScreen(
          probeDomain: _domain.text.trim().isEmpty ? null : _domain.text.trim(),
          initialPort: selectedPort,
          onPortSelected: (port) => selectedPort = port,
        ),
      ),
    );
    if (!mounted || picked == null) return;
    _resolver.text = '$picked:$selectedPort';
  }

  String? _credentialError(String? value, String peer) {
    final text = value ?? '';
    if (text.isEmpty && peer.isEmpty) return null;
    if (text.isEmpty || peer.isEmpty) {
      return 'Provide both username and password.';
    }
    if (utf8.encode(text).length > 255) return 'Use at most 255 UTF-8 bytes.';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    final endpoint = SlowDnsConfig.parseResolverAddress(
      _resolver.text,
      defaultPort: _defaultPort,
    );
    final profile = SlowDnsConfig(
      name: _name.text.trim(),
      domain: _domain.text.trim(),
      pubKey: _key.text.trim(),
      nameServer: _transport == 'doh' ? '' : (endpoint?.host ?? ''),
      port: _transport == 'doh' ? null : endpoint?.port,
      dnsTransport: _transport,
      dohUrl: _transport == 'doh' ? _doh.text.trim() : null,
      username: _username.text.isEmpty ? null : _username.text,
      password: _password.text.isEmpty ? null : _password.text,
      resolvers: _transport == 'doh'
          ? const []
          : _fallback.text
                .split(RegExp(r'[\s,;]+'))
                .where((v) => v.isNotEmpty)
                .toList(),
    );
    if (profile.validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(profile.validationError!)));
      return;
    }
    if (_transport != 'doh' && endpoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Enter a valid DNS resolver and port.')),
      );
      return;
    }
    if (widget.onSave != null) {
      setState(() => _saving = true);
      var saved = false;
      try {
        saved = await widget.onSave!(profile);
      } catch (_) {
        // Never expose configuration secrets through exception messages.
      }
      if (!mounted) return;
      setState(() => _saving = false);
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText(
              'Could not save profile. Check for a duplicate name and try again.',
            ),
          ),
        );
        return;
      }
    }
    Navigator.of(context).pop(profile);
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? helper,
    String? hint,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: obscure,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      ),
      validator: validator,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Add Slow DNS Profile'),
      actions: [
        IconButton(
          onPressed: _saving ? null : _save,
          tooltip: context.l10n.text('Save profile'),
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const LocalizedText('DNSTT', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _field(
            controller: _name,
            label: context.l10n.text('Profile Name'),
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Profile name is required.'
                : null,
          ),
          _field(
            controller: _domain,
            label: context.l10n.text('Domain'),
            helper: 'DNSTT tunnel domain',
            hint: context.l10n.text('tunnel.example.com'),
            validator: (v) => SlowDnsConfig.isValidDnsName(v ?? '')
                ? null
                : 'Enter a valid tunnel DNS name.',
          ),
          _field(
            controller: _key,
            label: context.l10n.text('Public Key'),
            helper: "Server's Noise protocol public key in hex format",
            validator: (v) => SlowDnsConfig.isValidPublicKey(v)
                ? null
                : 'Enter exactly 64 hexadecimal characters.',
          ),
          LocalizedText('DNS Transport', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final transport in const {
                'udp': 'UDP',
                'tcp': 'TCP',
                'dot': 'DoT',
                'doh': 'DoH',
              }.entries)
                ChoiceChip(
                  label: Text(transport.value),
                  selected: _transport == transport.key,
                  onSelected: transport.key == 'tcp'
                      ? null
                      : (_) => setState(() {
                          final previous = SlowDnsConfig.parseResolverAddress(
                            _resolver.text,
                            defaultPort: _defaultPort,
                          );
                          final oldDefault = _defaultPort;
                          _transport = transport.key;
                          // Preserve explicit nonstandard ports; update only standard ports.
                          if (previous != null && previous.port == oldDefault) {
                            final host = previous.host.contains(':')
                                ? '[${previous.host}]'
                                : previous.host;
                            _resolver.text = '$host:$_defaultPort';
                          }
                        }),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 20),
            child: LocalizedText(
              'TCP resolver transport is not supported by the current DNSTT engine.',
            ),
          ),
          if (_transport == 'doh')
            _field(
              controller: _doh,
              label: context.l10n.text('DNS Resolver (DoH URL)'),
              hint: context.l10n.text('https://dns.example/dns-query'),
              helper: 'HTTPS only. No fallback to plaintext DNS.',
              validator: (v) => SlowDnsConfig.isValidDohUrl(v)
                  ? null
                  : 'Enter a valid HTTPS resolver URL.',
            )
          else
            _field(
              controller: _resolver,
              label: context.l10n.text('DNS Resolver'),
              hint: context.l10n.text(_transport == 'dot' ? 'dns.example:853' : '1.1.1.1:53'),
              helper: 'IPv4 or domain (host:port). IPv6 is not supported.',
              suffix: IconButton(
                tooltip: context.l10n.text(_transport == 'udp'
                    ? 'Scan for Working Resolvers'
                    : 'Scanner tests UDP only'),
                onPressed: _transport == 'udp' ? _scan : null,
                icon: const Icon(Icons.radar),
              ),
              validator: (v) =>
                  SlowDnsConfig.parseResolverAddress(
                        v ?? '',
                        defaultPort: _defaultPort,
                      ) !=
                      null
                  ? null
                  : 'Enter a valid resolver and a port from 1 to 65535.',
            ),
          FilledButton.icon(
            onPressed: _transport == 'udp' ? _scan : null,
            icon: const Icon(Icons.search),
            label: const LocalizedText('Scan for Working Resolvers'),
          ),
          if (_transport != 'udp')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LocalizedText(
                'The scanner checks UDP resolvers; it does not verify DoT or DoH endpoints.',
              ),
            ),
          const SizedBox(height: 20),
          const SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: LocalizedText('Authoritative Mode'),
            subtitle: LocalizedText('Not supported by the current DNSTT engine.'),
            value: false,
            onChanged: null,
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: LocalizedText('DNS Query Size'),
            subtitle: LocalizedText(
              'Managed by the engine. Custom query sizes are not supported.'),
            leading: Icon(Icons.info_outline),
          ),
          const SizedBox(height: 16),
          LocalizedText(
            'Connection Method',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: LocalizedText('SOCKS'), selected: true),
              ChoiceChip(label: LocalizedText('SSH'), selected: false),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LocalizedText(
              'The DNSTT server must forward to a remote SOCKS5 endpoint. SSH chaining is not supported; these credentials are for SOCKS5, not SSH.',
            ),
          ),
          _field(
            controller: _username,
            label: context.l10n.text('SOCKS5 Username (optional)'),
            validator: (v) => _credentialError(v, _password.text),
          ),
          _field(
            controller: _password,
            label: context.l10n.text('SOCKS5 Password (optional)'),
            obscure: !_showPassword,
            validator: (v) => _credentialError(v, _username.text),
            suffix: IconButton(
              tooltip: context.l10n.text(_showPassword ? 'Hide password' : 'Show password'),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          ExpansionTile(
            title: const LocalizedText('Advanced'),
            children: [
              if (_transport != 'doh')
                _field(
                  controller: _fallback,
                  label: context.l10n.text('Failover Resolvers (optional)'),
                  maxLines: 3,
                  helper:
                      'Up to 31 additional bare IPs or hostnames, separated by spaces or commas. Uses the primary resolver port. Tried in order.',
                  validator: (v) {
                    final entries = (v ?? '')
                        .split(RegExp(r'[\s,;]+'))
                        .where((v) => v.isNotEmpty)
                        .toList();
                    if (entries.length > 31) {
                      return 'Use at most 31 additional resolvers.';
                    }
                    return entries.every(SlowDnsConfig.isValidResolverEndpoint)
                        ? null
                        : 'Use bare IP addresses or hostnames without ports.';
                  },
                ),
              const ListTile(
                title: LocalizedText('Local Proxy'),
                subtitle: LocalizedText(
                  'The app manages the local listen address and port. Arbitrary application UDP is blocked; TCP and tunneled DNS are supported.'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const LocalizedText('Save Profile'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}
