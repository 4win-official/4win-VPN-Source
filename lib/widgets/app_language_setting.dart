import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_locale_provider.dart';

class AppLanguageSetting extends StatelessWidget {
  const AppLanguageSetting({super.key});

  Future<void> _showLanguageDialog(BuildContext context) async {
    final provider = context.read<AppLocaleProvider>();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Language'),
        content: RadioGroup<String>(
          groupValue: provider.languageCode,
          onChanged: (value) => Navigator.pop(dialogContext, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: 'en',
                title: const Text(AppLocalizations.englishDisplayName),
              ),
              RadioListTile<String>(
                value: 'fa',
                title: const Text(AppLocalizations.persianDisplayName),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LocalizedText('Cancel'),
          ),
        ],
      ),
    );
    if (selected != null) await provider.setLanguage(selected);
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLocaleProvider>();
    final selectedLanguageName = language.languageCode == 'fa'
        ? AppLocalizations.persianDisplayName
        : AppLocalizations.englishDisplayName;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.translate),
      title: const LocalizedText('Language'),
      subtitle: Text(selectedLanguageName),
      trailing: Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left
            : Icons.chevron_right,
      ),
      onTap: () => _showLanguageDialog(context),
    );
  }
}
