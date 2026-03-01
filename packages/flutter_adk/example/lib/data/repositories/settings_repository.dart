import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_adk_example/config/app_constants.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/domain/models/app_settings.dart';

abstract interface class SettingsRepository {
  Future<AppSettings> load({required AppLanguage fallbackLanguage});

  Future<void> save(AppSettings settings);
}

class SharedPreferencesSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> load({required AppLanguage fallbackLanguage}) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return AppSettings(
        apiKey: prefs.getString(apiKeyPrefKey) ?? '',
        mcpUrl: prefs.getString(mcpUrlPrefKey) ?? '',
        mcpBearerToken: prefs.getString(mcpBearerTokenPrefKey) ?? '',
        language: appLanguageFromCode(
          prefs.getString(languagePrefKey) ?? fallbackLanguage.code,
        ),
        debugLogsEnabled: prefs.getBool(debugLogsEnabledPrefKey) ?? true,
      );
    } on MissingPluginException {
      return AppSettings(
        apiKey: '',
        mcpUrl: '',
        mcpBearerToken: '',
        language: fallbackLanguage,
        debugLogsEnabled: true,
      );
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String apiKey = settings.apiKey.trim();
      final String mcpUrl = settings.mcpUrl.trim();
      final String mcpBearerToken = settings.mcpBearerToken.trim();

      if (apiKey.isEmpty) {
        await prefs.remove(apiKeyPrefKey);
      } else {
        await prefs.setString(apiKeyPrefKey, apiKey);
      }

      if (mcpUrl.isEmpty) {
        await prefs.remove(mcpUrlPrefKey);
      } else {
        await prefs.setString(mcpUrlPrefKey, mcpUrl);
      }

      if (mcpBearerToken.isEmpty) {
        await prefs.remove(mcpBearerTokenPrefKey);
      } else {
        await prefs.setString(mcpBearerTokenPrefKey, mcpBearerToken);
      }

      await prefs.setString(languagePrefKey, settings.language.code);
      await prefs.setBool(debugLogsEnabledPrefKey, settings.debugLogsEnabled);
    } on MissingPluginException {
      // Keep running with in-memory state when plugin is unavailable.
    }
  }
}
