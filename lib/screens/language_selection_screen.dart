import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_locale_provider.dart';

/// Waits for the stored language choice before showing the app's loading flow.
class LanguageGate extends StatefulWidget {
  const LanguageGate({super.key, required this.child});

  final Widget child;

  @override
  State<LanguageGate> createState() => _LanguageGateState();
}

class _LanguageGateState extends State<LanguageGate> {
  late final Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = context.read<AppLocaleProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final language = context.watch<AppLocaleProvider>();
        if (!language.hasSavedChoice) return const LanguageSelectionScreen();
        return widget.child;
      },
    );
  }
}

/// First-launch language choice. The language names are shown in their own
/// scripts and the choice is persisted before the rest of the app is entered.
class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({super.key});

  Future<void> _choose(BuildContext context, String languageCode) async {
    await context.read<AppLocaleProvider>().setLanguage(languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF00FF88) : Colors.blue;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.translate, size: 48),
                  const SizedBox(height: 20),
                  const LocalizedText(
                    'Choose your language',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    'Select the language used in the app interface.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  _LanguageOption(
                    label: AppLocalizations.englishDisplayName,
                    languageCode: 'en',
                    accent: accent,
                    onTap: () => _choose(context, 'en'),
                  ),
                  const SizedBox(height: 12),
                  _LanguageOption(
                    label: AppLocalizations.persianDisplayName,
                    languageCode: 'fa',
                    accent: accent,
                    onTap: () => _choose(context, 'fa'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.languageCode,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String languageCode;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          side: BorderSide(color: accent.withValues(alpha: 0.55)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: languageCode == 'fa' ? 'sans-serif' : null,
          ),
        ),
      ),
    );
  }
}
