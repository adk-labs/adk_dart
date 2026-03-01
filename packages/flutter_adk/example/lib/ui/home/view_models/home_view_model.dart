import 'package:flutter/foundation.dart';

import 'package:flutter_adk_example/data/repositories/settings_repository.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/domain/models/app_settings.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({required SettingsRepository settingsRepository})
    : _settingsRepository = settingsRepository;

  final SettingsRepository _settingsRepository;

  AppSettings _settings = const AppSettings(
    apiKey: '',
    mcpUrl: '',
    mcpBearerToken: '',
    language: AppLanguage.en,
    debugLogsEnabled: true,
  );

  AppSettings get settings => _settings;
  AppLanguage get selectedLanguage => _settings.language;
  String get apiKey => _settings.apiKey;
  String get mcpUrl => _settings.mcpUrl;
  String get mcpBearerToken => _settings.mcpBearerToken;
  bool get debugLogsEnabled => _settings.debugLogsEnabled;
  bool get hasApiKey => _settings.hasApiKey;

  Future<void> initialize({required AppLanguage fallbackLanguage}) async {
    _settings = await _settingsRepository.load(
      fallbackLanguage: fallbackLanguage,
    );
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_settings.language == language) {
      return;
    }

    _settings = _settings.copyWith(language: language);
    notifyListeners();
    await _settingsRepository.save(_settings);
  }

  Future<void> saveSettings({
    required String apiKey,
    required String mcpUrl,
    required String mcpBearerToken,
    required bool debugLogsEnabled,
  }) async {
    _settings = _settings.copyWith(
      apiKey: apiKey,
      mcpUrl: mcpUrl,
      mcpBearerToken: mcpBearerToken,
      debugLogsEnabled: debugLogsEnabled,
    );
    notifyListeners();
    await _settingsRepository.save(_settings);
  }
}
