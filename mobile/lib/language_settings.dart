import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'strings.dart';

abstract interface class LanguageStore {
  Future<String?> read();
  Future<void> write(String code);
}

class PreferencesLanguageStore implements LanguageStore {
  PreferencesLanguageStore() : _preferences = SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const key = 'antitourist.language';
  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String code) => _preferences.setString(key, code);
}

class LanguageSettings extends ChangeNotifier {
  LanguageSettings({AppLanguage language = AppLanguage.ru, LanguageStore? store})
      : _language = language, _store = store;
  AppLanguage _language;
  final LanguageStore? _store;
  AppLanguage get language => _language;

  static Future<LanguageSettings> load({LanguageStore? store}) async {
    final storage = store ?? PreferencesLanguageStore();
    AppLanguage language = AppLanguage.ru;
    try { language = AppLanguage.fromCode(await storage.read()) ?? AppLanguage.ru; }
    catch (_) { /* Keep the app usable if local storage is unavailable. */ }
    return LanguageSettings(language: language, store: storage);
  }

  Future<bool> select(AppLanguage language) async {
    _language = language;
    notifyListeners();
    try { await _store?.write(language.code); return true; }
    catch (_) { return false; }
  }
}

class LanguageScope extends InheritedNotifier<LanguageSettings> {
  const LanguageScope({super.key, required LanguageSettings settings, required super.child})
      : super(notifier: settings);
  static LanguageSettings? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier;
}

extension LanguageContext on BuildContext {
  AppStrings get strings => AppStrings(LanguageScope.of(this)?.language ?? AppLanguage.ru);
}

String tr(BuildContext context, String key, [Map<String, Object> parameters = const {}]) =>
    context.strings.t(key, parameters);

class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = LanguageScope.of(context);
    if (settings == null) { return const SizedBox.shrink(); }
    return PopupMenuButton<AppLanguage>(
      key: const ValueKey('language-menu'),
      tooltip: tr(context, 'language'), icon: const Icon(Icons.language),
      initialValue: settings.language,
      onSelected: (language) async {
        final saved = await settings.select(language);
        if (!saved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'languageSaveError'))));
        }
      },
      itemBuilder: (_) => [for (final language in AppLanguage.values)
        CheckedPopupMenuItem(value: language, checked: settings.language == language,
          child: Text(language.label))]);
  }
}
