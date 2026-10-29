import 'package:flutter/material.dart';

import 'persian_translations.dart';

/// App-owned, offline localization for user-visible interface text.
///
/// English source strings are lookup keys so the app can be migrated without
/// changing protocol names, imported configuration, server records, or other
/// network-facing data. Missing Persian entries deliberately fall back to the
/// English source string; the localization coverage test guards UI literals.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  static const String persianDisplayName = 'فارسی';
  static const String englishDisplayName = 'English';

  static const Map<String, String> _persian = appPersianTranslations;
  static final List<_LocalizedTemplateEntry> _templates = _buildTemplates();

  static const AppLocalizations _fallback = AppLocalizations(Locale('en'));

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      _fallback;

  /// Translate app-authored UI copy. Unknown entries remain English rather
  /// than invoking a runtime machine-translation service.
  String text(String source) {
    if (locale.languageCode != 'fa') return source;
    final direct = _persian[source];
    if (direct != null) return direct;

    // Dynamic UI messages are catalogued with their original Dart interpolation
    // markers (for example, "Version $version"). Match the fixed copy while
    // copying every runtime value verbatim into the Persian translation.
    for (final entry in _templates) {
      final template = entry.template;
      final match = template.pattern.matchAsPrefix(source);
      if (match == null || match.end != source.length) continue;
      var translated = entry.translation;
      for (var i = 0; i < template.placeholders.length; i++) {
        translated = translated.replaceFirst(
          template.placeholders[i],
          match.group(i + 1) ?? '',
        );
      }
      return translated;
    }
    return source;
  }

  static List<_LocalizedTemplateEntry> _buildTemplates() {
    final templates = <_LocalizedTemplateEntry>[];
    for (final entry in _persian.entries) {
      final template = _compileTemplate(entry.key);
      if (template != null) {
        templates.add(_LocalizedTemplateEntry(entry.value, template));
      }
    }
    return List<_LocalizedTemplateEntry>.unmodifiable(templates);
  }

  static _LocalizedTemplate? _compileTemplate(String source) {
    if (!source.contains(r'$')) return null;
    final pattern = StringBuffer('^');
    final placeholders = <String>[];
    for (var i = 0; i < source.length;) {
      if (source[i] != r'$') {
        pattern.write(RegExp.escape(source[i]));
        i++;
        continue;
      }
      final start = i;
      i++;
      if (i < source.length && source[i] == '{') {
        var depth = 1;
        i++;
        while (i < source.length && depth > 0) {
          if (source[i] == '{') depth++;
          if (source[i] == '}') depth--;
          i++;
        }
      } else {
        while (i < source.length &&
            RegExp(r'[A-Za-z0-9_]').hasMatch(source[i])) {
          i++;
        }
      }
      if (i == start + 1) {
        pattern.write(r'\$');
        continue;
      }
      final marker = source.substring(start, i);
      placeholders.add(marker);
      pattern.write(r'([\s\S]*?)');
    }
    pattern.write(r'$');
    return _LocalizedTemplate(RegExp(pattern.toString()), placeholders);
  }
}

class _LocalizedTemplate {
  const _LocalizedTemplate(this.pattern, this.placeholders);

  final RegExp pattern;
  final List<String> placeholders;
}

class _LocalizedTemplateEntry {
  const _LocalizedTemplateEntry(this.translation, this.template);

  final String translation;
  final _LocalizedTemplate template;
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

extension AppLocalizationContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// A Text-compatible widget for app-owned literal copy. Dynamic content that
/// may contain user-entered/server data should continue to use Flutter's Text.
class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Text(
      l10n.text(data),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null
          ? null
          : l10n.text(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
